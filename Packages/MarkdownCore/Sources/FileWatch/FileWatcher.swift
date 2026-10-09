import CoreServices
import Darwin
import Foundation

public struct FileSnapshot: Sendable, Equatable {
    public let url: URL
    public let data: Data
    public let signature: FileSignature

    /// Obsah jako text; nevalidní UTF-8 se nahradí znakem U+FFFD.
    public var text: String { String(decoding: data, as: UTF8.self) }
}

public enum FileWatchEvent: Sendable, Equatable {
    /// Nový obsah (i po znovuvytvoření smazaného souboru).
    case updated(FileSnapshot)
    /// Soubor zmizel a po grace periodě se nevrátil. Watcher dál čeká na jeho znovuvytvoření.
    case deleted(URL)
    /// Soubor byl přejmenován nebo přesunut; watcher už sleduje novou cestu.
    case moved(from: URL, to: URL)
}

public struct FileWatcherConfiguration: Sendable {
    /// Latence FSEvents streamu.
    public var latency: TimeInterval = 0.05
    /// Trailing debounce: kontrola proběhne až po této době klidu…
    public var debounce: TimeInterval = 0.1
    /// …ale nejpozději po této době od první události (průběžné aktualizace při dlouhém zápisu).
    public var maxWait: TimeInterval = 0.4
    /// Jak dlouho smí soubor chybět, než se ohlásí smazání (delete+create, vimový backup přes rename).
    public var deleteGrace: TimeInterval = 1.5
    /// Prázdný soubor po neprázdném se přijme až po této době (truncate + write).
    public var emptyGrace: TimeInterval = 0.2
    /// Opakování čtení, když soubor končí nedokončenou UTF-8 sekvencí nebo zápis ještě běží.
    public var retryDelay: TimeInterval = 0.1
    /// Pojistný polling přes `stat()` pro lokální svazky; `nil` = vypnuto.
    public var pollInterval: TimeInterval? = 2
    /// Polling pro síťové svazky, kde FSEvents nevidí změny z jiných strojů.
    public var networkPollInterval: TimeInterval = 1

    public init() {}
}

/// Sleduje jeden soubor přes FSEvents na jeho **rodičovském adresáři** (podle cesty, ne inode),
/// takže přežije atomic save, smazání a znovuvytvoření i přejmenování.
/// FSEvents ale změnu obsahu hlásí až při zavření souboru, proto navíc běží kqueue
/// (`DispatchSource`) na aktuálním inode – ten zachytí každý `write()` do otevřeného
/// souboru (agent streamuje výstup). Obě cesty jen plánují kontrolu; pravdu určuje `stat()`.
///
/// Veškerý stav žije na privátní sériové frontě; handler se volá na ní, takže
/// konzument si má práci přehodit jinam (např. `DispatchQueue.main.async`).
/// `stop()` je povinné – FSEvents stream drží watcher naživu.
public final class FileWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (FileWatchEvent) -> Void

    private let configuration: FileWatcherConfiguration
    private let handler: Handler
    private let queue = DispatchQueue(label: "cz.elvisek.mdview.filewatch")
    private let queueKey = DispatchSpecificKey<Void>()

    // Stav – přístup jen na `queue`.
    private var url: URL
    private var filePath = ""
    private var directoryPath = ""
    private var isRunning = false
    private var stream: FSEventStreamRef?
    private var trackedDescriptor: Int32 = -1
    private var inodeSource: DispatchSourceFileSystemObject?
    private var lastSignature: FileSignature?
    private var lastData: Data?
    private var isDeleted = false
    private var missingSince: DispatchTime?
    private var emptySince: DispatchTime?
    private var pendingSince: DispatchTime?
    private var retryDeadline: DispatchTime?
    private var coalesceTimer: DispatchSourceTimer?
    private var retryTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?

    public init(url: URL, configuration: FileWatcherConfiguration = FileWatcherConfiguration(), handler: @escaping Handler) {
        self.url = url
        self.configuration = configuration
        self.handler = handler
        queue.setSpecific(key: queueKey, value: ())
    }

    /// Aktuálně sledovaná cesta (po přejmenování se mění).
    public var currentURL: URL { onQueue { url } }

    /// Spustí sledování a vrátí aktuální obsah souboru.
    public func start() throws -> FileSnapshot {
        try onQueue {
            precondition(!isRunning, "FileWatcher už běží")
            try resolvePaths(for: url)
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            guard let signature = FileSignature.read(path: filePath) else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: filePath])
            }
            lastSignature = signature
            lastData = data
            isRunning = true
            openTrackedDescriptor()
            makeTimers()
            startStream()
            return FileSnapshot(url: url, data: data, signature: signature)
        }
    }

    public func stop() {
        onQueue {
            guard isRunning else { return }
            isRunning = false
            stopStream()
            for timer in [coalesceTimer, retryTimer, pollTimer] {
                timer?.cancel()
            }
            coalesceTimer = nil
            retryTimer = nil
            pollTimer = nil
            closeTrackedDescriptor()
        }
    }

    /// Vynucená kontrola (aktivace aplikace, změna viditelnosti okna, NSFilePresenter).
    public func checkNow() {
        queue.async { [weak self] in self?.performCheck() }
    }

    // MARK: - Fronta

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    // MARK: - Cesty

    private func resolvePaths(for url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        let directory = resolved.deletingLastPathComponent().path
        guard let canonicalDirectory = Self.canonicalPath(of: directory) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: directory])
        }
        self.url = url
        directoryPath = canonicalDirectory
        filePath = (canonicalDirectory as NSString).appendingPathComponent(resolved.lastPathComponent)
    }

    /// Kanonická cesta adresáře tak, jak ji hlásí FSEvents (`/private/var/…`, skutečná velikost písmen).
    private static func canonicalPath(of directory: String) -> String? {
        let descriptor = open(directory, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        return path(of: descriptor)
    }

    private static func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Otevře `O_EVTONLY` fd na aktuální inode: slouží pro `F_GETPATH` při přejmenování
    /// a pro kqueue události zápisu. Neblokuje odpojení svazku.
    private func openTrackedDescriptor() {
        closeTrackedDescriptor()
        let descriptor = open(filePath, O_EVTONLY)
        guard descriptor >= 0 else { return }
        trackedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleCoalescedCheck() }
        source.setCancelHandler { close(descriptor) }
        source.activate()
        inodeSource = source
    }

    private func closeTrackedDescriptor() {
        // fd zavře cancel handler, až kqueue přestane zdroj používat.
        inodeSource?.cancel()
        inodeSource = nil
        trackedDescriptor = -1
    }

    private func retarget(to newPath: String) {
        let previousDirectory = directoryPath
        try? resolvePaths(for: URL(fileURLWithPath: newPath))
        if directoryPath != previousDirectory {
            startStream()
        }
        makePollTimer()
    }

    // MARK: - FSEvents

    private func startStream() {
        stopStream()
        let info = Unmanaged.passRetained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: { pointer in
                if let pointer { Unmanaged<FileWatcher>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue()
            let eventPaths = array as? [String] ?? []
            let eventFlags = Array(UnsafeBufferPointer(start: flags, count: count))
            watcher.handleEvents(paths: eventPaths, flags: eventFlags)
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [directoryPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            configuration.latency,
            flags
        ) else {
            Unmanaged<FileWatcher>.fromOpaque(info).release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard isRunning else { return }
        let directory = directoryPath.lowercased()
        let file = filePath.lowercased()
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
        )
        var relevant = false
        for (path, flag) in zip(paths, flags) {
            if flag & rescanFlags != 0 {
                relevant = true
                continue
            }
            // FSEvents je rekurzivní – šum z podadresářů (.git, node_modules) ignorujeme.
            let lowered = path.lowercased()
            if lowered == file || (lowered as NSString).deletingLastPathComponent == directory {
                relevant = true
            }
        }
        if relevant {
            scheduleCoalescedCheck()
        }
    }

    // MARK: - Časovače

    private func makeTimers() {
        let coalesce = DispatchSource.makeTimerSource(queue: queue)
        coalesce.setEventHandler { [weak self] in self?.performCheck() }
        coalesce.activate()
        coalesceTimer = coalesce

        let retry = DispatchSource.makeTimerSource(queue: queue)
        retry.setEventHandler { [weak self] in
            self?.retryDeadline = nil
            self?.performCheck()
        }
        retry.activate()
        retryTimer = retry

        makePollTimer()
    }

    private func makePollTimer() {
        pollTimer?.cancel()
        pollTimer = nil
        let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? true
        guard let interval = isLocal ? configuration.pollInterval : configuration.networkPollInterval else { return }
        let poll = DispatchSource.makeTimerSource(queue: queue)
        poll.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        poll.setEventHandler { [weak self] in self?.performCheck() }
        poll.activate()
        pollTimer = poll
    }

    private func scheduleCoalescedCheck() {
        guard isRunning else { return }
        let now = DispatchTime.now()
        let since = pendingSince ?? now
        pendingSince = since
        let deadline = min(now + configuration.debounce, since + configuration.maxWait)
        coalesceTimer?.schedule(deadline: deadline)
    }

    private func scheduleRetry(after delay: TimeInterval) {
        scheduleRetry(at: DispatchTime.now() + delay)
    }

    private func scheduleRetry(at deadline: DispatchTime) {
        if let existing = retryDeadline, existing <= deadline { return }
        retryDeadline = deadline
        retryTimer?.schedule(deadline: deadline)
    }

    // MARK: - Kontrola souboru

    private func performCheck() {
        pendingSince = nil
        guard isRunning else { return }

        guard let signature = FileSignature.read(path: filePath) else {
            handleMissingFile()
            return
        }
        missingSince = nil
        if !isDeleted, signature == lastSignature { return }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: .uncached) else {
            scheduleRetry(after: configuration.retryDelay)
            return
        }
        // Zápis ještě běží – obsah zobrazíme, ale za chvíli se podíváme znovu.
        if FileSignature.read(path: filePath) != signature || signature.size != Int64(data.count) {
            scheduleRetry(after: configuration.retryDelay)
        }

        // truncate + write: prázdný soubor hned po neprázdném nejspíš jen čeká na zápis.
        if data.isEmpty, let lastData, !lastData.isEmpty {
            let now = DispatchTime.now()
            let since = emptySince ?? now
            emptySince = since
            if now < since + configuration.emptyGrace {
                scheduleRetry(at: since + configuration.emptyGrace)
                return
            }
        }
        emptySince = nil

        let complete = Self.trimmingIncompleteUTF8(data)
        if complete.count != data.count {
            scheduleRetry(after: configuration.retryDelay)
        }

        if signature.inode != lastSignature?.inode {
            openTrackedDescriptor()
        }
        lastSignature = signature
        let wasDeleted = isDeleted
        isDeleted = false
        if !wasDeleted, complete == lastData { return }
        lastData = complete
        handler(.updated(FileSnapshot(url: url, data: complete, signature: signature)))
    }

    private func handleMissingFile() {
        guard !isDeleted else { return }
        let now = DispatchTime.now()
        let since = missingSince ?? now
        missingSince = since
        if now < since + configuration.deleteGrace {
            scheduleRetry(at: since + configuration.deleteGrace)
            return
        }

        // Přejmenování: inode držený přes fd žije pod jinou cestou (mimo Koš).
        if trackedDescriptor >= 0, let newPath = Self.path(of: trackedDescriptor), newPath != filePath,
           !newPath.contains("/.Trash/"), FileSignature.read(path: newPath) != nil {
            let previous = url
            retarget(to: newPath)
            missingSince = nil
            handler(.moved(from: previous, to: url))
            performCheck()
            return
        }

        missingSince = nil
        isDeleted = true
        lastSignature = nil
        handler(.deleted(url))
    }

    /// Odřízne nedokončenou vícebajtovou UTF-8 sekvenci na konci (soubor se právě zapisuje).
    static func trimmingIncompleteUTF8(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        var leadIndex = data.endIndex - 1
        var continuationBytes = 0
        while continuationBytes < 3, leadIndex > data.startIndex, data[leadIndex] & 0xC0 == 0x80 {
            leadIndex -= 1
            continuationBytes += 1
        }
        let expectedLength: Int
        switch data[leadIndex] {
        case 0x00...0x7F: expectedLength = 1
        case 0xC0...0xDF: expectedLength = 2
        case 0xE0...0xEF: expectedLength = 3
        case 0xF0...0xF7: expectedLength = 4
        default: return data
        }
        let available = data.endIndex - leadIndex
        return available < expectedLength ? Data(data[data.startIndex..<leadIndex]) : data
    }
}
