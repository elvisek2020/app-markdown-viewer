import Foundation
import Testing
import WebAssets
@testable import MarkdownCore

@Suite("Politika odkazů")
struct LinkPolicyTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mdview-links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# A".write(to: directory.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "log".write(to: directory.appendingPathComponent("build.log"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Fake.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("link.md"),
            withDestinationURL: directory.appendingPathComponent("build.log")
        )
    }

    private func url(_ name: String, scheme: String = "file") -> URL {
        URL(string: "\(scheme)://\(directory.appendingPathComponent(name).path)")!
    }

    @Test func markdownOpensInApp() {
        #expect(LinkPolicy.action(for: url("a.md")) == .openMarkdown(directory.appendingPathComponent("a.md").standardizedFileURL))
        #expect(LinkPolicy.action(for: url("a.md", scheme: "mdv-file")) != .ignore)
    }

    @Test func otherFilesAreOnlyRevealed() {
        #expect(LinkPolicy.action(for: url("build.log")) == .revealInFinder(directory.appendingPathComponent("build.log").standardizedFileURL))
    }

    /// CVE-2019-12173 původního MacDownu: odkaz na .app ho spustil.
    @Test func applicationsAreNeverOpened() {
        let action = LinkPolicy.action(for: URL(string: "file:///System/Applications/Calculator.app")!)
        #expect(action == .revealInFinder(URL(fileURLWithPath: "/System/Applications/Calculator.app").standardizedFileURL))
        #expect(LinkPolicy.action(for: url("Fake.app")) == .revealInFinder(directory.appendingPathComponent("Fake.app").standardizedFileURL))
    }

    @Test func symlinkWithMarkdownNameToOtherFileIsRevealed() {
        if case .openMarkdown = LinkPolicy.action(for: url("link.md")) {
            Issue.record("symlink .md na jiný typ souboru se nesmí otevřít jako Markdown")
        }
    }

    @Test func missingFileIsIgnored() {
        #expect(LinkPolicy.action(for: url("neexistuje.md")) == .ignore)
    }

    @Test(arguments: ["https://example.com", "http://example.com/a?b=c", "mailto:a@example.com"])
    func webLinksOpenExternally(link: String) {
        #expect(LinkPolicy.action(for: URL(string: link)!) == .openExternal(URL(string: link)!))
    }

    @Test(arguments: ["javascript:alert(1)", "data:text/html,<b>x</b>", "mdv-asset://app/app.js", "about:blank"])
    func dangerousSchemesAreIgnored(link: String) {
        #expect(LinkPolicy.action(for: URL(string: link)!) == .ignore)
    }

    @Test func unknownSchemesNeedConfirmation() {
        let link = URL(string: "vscode://file/etc/hosts")!
        #expect(LinkPolicy.action(for: link) == .confirmExternal(link))
    }

    @Test func previewURL() {
        let file = URL(fileURLWithPath: "/Users/test/Mé dokumenty/a b.md")
        let preview = LinkPolicy.previewURL(forFile: file)
        #expect(preview.absoluteString.hasPrefix("mdv-file:///Users/test/M"))
        #expect(preview.absoluteString.hasSuffix("%20dokumenty/a%20b.md"))
        // Swift porovnává řetězce kanonicky, takže NFC i NFD podoba „é“ jsou shodné.
        #expect(preview.path == "/Users/test/Mé dokumenty/a b.md")
        #expect(LinkPolicy.action(for: preview) == .ignore)
    }
}

@Suite("Web assety")
struct WebAssetsTests {
    @Test func coreFilesExist() {
        for path in WebAssets.coreScripts + ["template.html", "app.css"] {
            #expect(WebAssets.fileURL(for: path).map { FileManager.default.fileExists(atPath: $0.path) } == true, "\(path)")
        }
        for library in WebAssets.Library.allCases {
            #expect(WebAssets.fileURL(for: library.rawValue).map { FileManager.default.fileExists(atPath: $0.path) } == true)
        }
    }

    @Test func pathTraversalIsRejected() {
        #expect(WebAssets.fileURL(for: "../../etc/passwd") == nil)
        #expect(WebAssets.fileURL(for: "vendor/../../x") == nil)
    }
}
