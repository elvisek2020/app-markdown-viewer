import Foundation
import Synchronization
import Testing
@testable import FileWatch

/// Sběr událostí z fronty watcheru.
private final class EventLog: Sendable {
    private let storage = Mutex<[FileWatchEvent]>([])

    func append(_ event: FileWatchEvent) {
        storage.withLock { $0.append(event) }
    }

    var events: [FileWatchEvent] { storage.withLock { $0 } }

    var updatedTexts: [String] {
        events.compactMap { event in
            if case .updated(let snapshot) = event { return snapshot.text }
            return nil
        }
    }

    var lastText: String? { updatedTexts.last }

    var deletions: Int {
        events.filter { if case .deleted = $0 { true } else { false } }.count
    }
}

/// Dočasný adresář se sledovaným souborem; po testu se smaže.
private final class Fixture: Sendable {
    let directory: URL
    let file: URL
    let log: EventLog
    let watcher: FileWatcher

    init(initial: String = "v0", configuration: FileWatcherConfiguration = .fast) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdview-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("doc.md")
        try initial.write(to: file, atomically: false, encoding: .utf8)
        let log = EventLog()
        self.log = log
        watcher = FileWatcher(url: file, configuration: configuration) { log.append($0) }
        _ = try watcher.start()
        // FSEvents potřebuje chvilku, než začne doručovat.
        Thread.sleep(forTimeInterval: 0.15)
    }

    deinit {
        watcher.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func atomicWrite(_ text: String, to url: URL? = nil) throws {
        try Data(text.utf8).write(to: url ?? file, options: .atomic)
    }
}

private extension FileWatcherConfiguration {
    static var fast: FileWatcherConfiguration {
        var configuration = FileWatcherConfiguration()
        configuration.deleteGrace = 0.5
        configuration.pollInterval = nil
        return configuration
    }
}

private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@Suite("FileWatcher", .serialized)
struct FileWatcherTests {
    @Test func startReturnsContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.md")
        try "# Ahoj".write(to: file, atomically: false, encoding: .utf8)
        let watcher = FileWatcher(url: file) { _ in }
        defer { watcher.stop() }
        #expect(try watcher.start().text == "# Ahoj")
    }

    @Test func inPlaceWrite() async throws {
        let fixture = try Fixture()
        try "v1".write(to: fixture.file, atomically: false, encoding: .utf8)
        #expect(await eventually { fixture.log.lastText == "v1" })
    }

    /// Bug MacDownu: watcher po atomic save „odpadl“. Musí fungovat opakovaně.
    @Test func keepsWatchingAfterAtomicSaves() async throws {
        let fixture = try Fixture()
        try fixture.atomicWrite("v1")
        #expect(await eventually { fixture.log.lastText == "v1" })
        try fixture.atomicWrite("v2")
        #expect(await eventually { fixture.log.lastText == "v2" })
        for index in 3...50 {
            try fixture.atomicWrite("v\(index)")
        }
        #expect(await eventually { fixture.log.lastText == "v50" })
    }

    @Test func appendInChunks() async throws {
        let fixture = try Fixture(initial: "")
        let handle = try FileHandle(forWritingTo: fixture.file)
        var expected = ""
        for index in 0..<40 {
            let chunk = "Řádek \(index) – agent píše…\n"
            expected += chunk
            try handle.write(contentsOf: Data(chunk.utf8))
            try await Task.sleep(for: .milliseconds(20))
        }
        try handle.close()
        #expect(await eventually { fixture.log.lastText == expected })
        // Průběžné aktualizace během zápisu (max-wait), ne jen jedna na konci.
        #expect(fixture.log.updatedTexts.count >= 2)
    }

    @Test func truncateThenWriteDoesNotFlashEmpty() async throws {
        let fixture = try Fixture(initial: "původní obsah")
        let handle = try FileHandle(forWritingTo: fixture.file)
        try handle.truncate(atOffset: 0)
        try await Task.sleep(for: .milliseconds(60))
        try handle.write(contentsOf: Data("nový obsah".utf8))
        try handle.close()
        #expect(await eventually { fixture.log.lastText == "nový obsah" })
        #expect(!fixture.log.updatedTexts.contains(""))
    }

    @Test func deleteAndRecreateWithinGrace() async throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.file)
        try await Task.sleep(for: .milliseconds(200))
        try "znovu".write(to: fixture.file, atomically: false, encoding: .utf8)
        #expect(await eventually { fixture.log.lastText == "znovu" })
        try await Task.sleep(for: .milliseconds(700))
        #expect(fixture.log.deletions == 0)
    }

    @Test func deleteIsReportedAndRecreationRecovers() async throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.file)
        #expect(await eventually { fixture.log.deletions == 1 })
        try "zpět".write(to: fixture.file, atomically: false, encoding: .utf8)
        #expect(await eventually { fixture.log.lastText == "zpět" })
    }

    @Test func recreatedWithSameContentClearsDeletion() async throws {
        let fixture = try Fixture(initial: "stejné")
        try FileManager.default.removeItem(at: fixture.file)
        #expect(await eventually { fixture.log.deletions == 1 })
        try "stejné".write(to: fixture.file, atomically: false, encoding: .utf8)
        #expect(await eventually { fixture.log.lastText == "stejné" })
    }

    @Test func renameIsTracked() async throws {
        let fixture = try Fixture()
        let renamed = fixture.directory.appendingPathComponent("prejmenovany.md")
        try FileManager.default.moveItem(at: fixture.file, to: renamed)
        #expect(await eventually {
            fixture.log.events.contains { event in
                if case .moved(_, let to) = event { return to.lastPathComponent == "prejmenovany.md" }
                return false
            }
        })
        #expect(fixture.log.deletions == 0)
        try "po přejmenování".write(to: renamed, atomically: false, encoding: .utf8)
        #expect(await eventually { fixture.log.lastText == "po přejmenování" })
    }

    @Test func ignoresUnrelatedFiles() async throws {
        let fixture = try Fixture()
        try "jiný".write(to: fixture.directory.appendingPathComponent("jiny.md"), atomically: true, encoding: .utf8)
        let subdirectory = fixture.directory.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try "x".write(to: subdirectory.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.log.events.isEmpty)
    }

    @Test func touchWithoutContentChangeIsSilent() async throws {
        let fixture = try Fixture(initial: "obsah")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fixture.file.path)
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.log.events.isEmpty)
    }

    @Test func pollingFallbackDetectsChanges() async throws {
        var configuration = FileWatcherConfiguration.fast
        configuration.pollInterval = 0.2
        let fixture = try Fixture(configuration: configuration)
        try fixture.atomicWrite("přes polling")
        #expect(await eventually { fixture.log.lastText == "přes polling" })
    }
}

@Suite("UTF-8")
struct UTF8Tests {
    @Test func trimsIncompleteSequence() {
        let full = Data("ž".utf8)  // 0xC5 0xBE
        #expect(FileWatcher.trimmingIncompleteUTF8(Data("a".utf8) + full.prefix(1)) == Data("a".utf8))
        #expect(FileWatcher.trimmingIncompleteUTF8(Data("a".utf8) + full) == Data("až".utf8))
        let rocket = Data("🚀".utf8)
        #expect(FileWatcher.trimmingIncompleteUTF8(rocket.prefix(3)) == Data())
        #expect(FileWatcher.trimmingIncompleteUTF8(Data()) == Data())
    }
}
