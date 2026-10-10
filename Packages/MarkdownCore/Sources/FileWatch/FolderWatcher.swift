import CoreServices
import Foundation

/// Hlídá celou složku (rekurzivně přes FSEvents) a hlásí změněné Markdown soubory –
/// pro strom pracovní složky a režim „sledovat agenta“. Obsah otevřeného souboru dál hlídá `FileWatcher`.
///
/// Handler se volá na privátní frontě se sadou změněných cest (soubor vytvořen, změněn, přejmenován
/// nebo smazán); `structureChanged` říká, že se mohl změnit strom (vznik, zánik, přejmenování).
/// `stop()` je povinné – FSEvents stream drží watcher naživu.
public final class FolderWatcher: @unchecked Sendable {
    public struct Change: Sendable, Equatable {
        public let paths: Set<String>
        public let structureChanged: Bool
    }

    public typealias Handler = @Sendable (Change) -> Void

    private let root: URL
    /// Kořen tak, jak ho hlásí FSEvents (`/private/var/…`) – `URL` při normalizaci `/private` odstraňuje.
    private var canonicalRoot: URL
    private let extensions: Set<String>
    private let latency: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "cz.elvisek.mdview.folderwatch")
    private var stream: FSEventStreamRef?

    public init(root: URL, extensions: Set<String>, latency: TimeInterval = 0.2, handler: @escaping Handler) {
        self.root = root
        self.canonicalRoot = URL(fileURLWithPath: Self.canonicalPath(root.path) ?? root.path)
        self.extensions = extensions
        self.latency = latency
        self.handler = handler
    }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            let info = Unmanaged.passRetained(self).toOpaque()
            var context = FSEventStreamContext(
                version: 0, info: info, retain: nil,
                release: { pointer in
                    if let pointer { Unmanaged<FolderWatcher>.fromOpaque(pointer).release() }
                },
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let eventPaths = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                watcher.handle(paths: eventPaths, flags: Array(UnsafeBufferPointer(start: flags, count: count)))
            }
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            )
            canonicalRoot = URL(fileURLWithPath: Self.canonicalPath(root.path) ?? root.path)
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, [canonicalRoot.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
            ) else {
                Unmanaged<FolderWatcher>.fromOpaque(info).release()
                return
            }
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    public func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        let structural = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        )
        let rescan = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        )
        var changed: Set<String> = []
        var structureChanged = false
        for (path, flag) in zip(paths, flags) {
            if flag & rescan != 0 {
                structureChanged = true
                continue
            }
            let isDirectory = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
            if isDirectory {
                // Vznik, zánik nebo přejmenování složky může změnit strom.
                if flag & structural != 0, FolderIndex.isRelevant(path + "/x.md", root: canonicalRoot, extensions: ["md"]) {
                    structureChanged = true
                }
                continue
            }
            guard FolderIndex.isRelevant(path, root: canonicalRoot, extensions: extensions) else { continue }
            changed.insert(path)
            if flag & structural != 0 { structureChanged = true }
        }
        guard !changed.isEmpty || structureChanged else { return }
        handler(Change(paths: changed, structureChanged: structureChanged))
    }

    static func canonicalPath(_ path: String) -> String? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
