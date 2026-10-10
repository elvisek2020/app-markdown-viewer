import Foundation
import Synchronization
import Testing
@testable import FileWatch

private let markdown: Set<String> = ["md", "markdown"]

private func makeTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mdview-folder-\(UUID().uuidString)")
    let files = [
        "README.md", "b.md", "poznamky.txt", "docs/navod.md", "docs/obrazek.png", "docs/hluboko/plan.markdown",
        "node_modules/balik/README.md", ".git/HEAD.md", ".skryta/x.md", "prazdna/jen.txt", "build/vystup.md",
    ]
    for file in files {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# \(file)".write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}

@Suite("Index složky")
struct FolderIndexTests {
    @Test func scansMarkdownAndSkipsIgnored() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let nodes = FolderIndex.scan(root, extensions: markdown)
        #expect(nodes.map(\.name) == ["docs", "b.md", "README.md"])
        let docs = try #require(nodes.first)
        #expect(docs.children?.map(\.name) == ["hluboko", "navod.md"])
        #expect(Set(FolderIndex.files(in: nodes).map(\.name)) == ["README.md", "b.md", "navod.md", "plan.markdown"])
    }

    @Test func respectsFileLimit() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var limits = FolderIndex.Limits()
        limits.maximumFiles = 2
        #expect(FolderIndex.files(in: FolderIndex.scan(root, extensions: markdown, limits: limits)).count == 2)
    }

    @Test func relevance() {
        let root = URL(fileURLWithPath: "/tmp/projekt")
        #expect(FolderIndex.isRelevant("/tmp/projekt/docs/a.md", root: root, extensions: markdown))
        #expect(!FolderIndex.isRelevant("/tmp/projekt/node_modules/a.md", root: root, extensions: markdown))
        #expect(!FolderIndex.isRelevant("/tmp/projekt/.git/a.md", root: root, extensions: markdown))
        #expect(!FolderIndex.isRelevant("/tmp/projekt/a.txt", root: root, extensions: markdown))
        #expect(!FolderIndex.isRelevant("/tmp/jiny/a.md", root: root, extensions: markdown))
    }
}

private final class ChangeLog: Sendable {
    private let storage = Mutex<[FolderWatcher.Change]>([])
    func append(_ change: FolderWatcher.Change) { storage.withLock { $0.append(change) } }
    var paths: Set<String> { storage.withLock { $0.reduce(into: Set<String>()) { $0.formUnion($1.paths) } } }
    var structureChanged: Bool { storage.withLock { $0.contains { $0.structureChanged } } }
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

@Suite("Hlídání složky", .serialized)
struct FolderWatcherTests {
    @Test func reportsMarkdownChangesAndIgnoresOthers() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ChangeLog()
        let watcher = FolderWatcher(root: root, extensions: markdown, latency: 0.05) { log.append($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))

        try "nový".write(to: root.appendingPathComponent("docs/novy.md"), atomically: true, encoding: .utf8)
        try "změna".write(to: root.appendingPathComponent("b.md"), atomically: false, encoding: .utf8)
        try "ignorovat".write(to: root.appendingPathComponent("node_modules/balik/README.md"), atomically: true, encoding: .utf8)
        try "ignorovat".write(to: root.appendingPathComponent("poznamky.txt"), atomically: true, encoding: .utf8)

        #expect(await eventually { log.paths.contains { $0.hasSuffix("/docs/novy.md") } && log.paths.contains { $0.hasSuffix("/b.md") } })
        #expect(log.structureChanged)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!log.paths.contains { $0.contains("node_modules") || $0.hasSuffix(".txt") })
    }
}
