import Foundation
import Testing
@testable import MarkdownCore

@Suite struct PlainTextTests {
    @Test func markdownSyntaxStaysLiteral() {
        let document = PlainText.render("# není nadpis\n*a* <script>x</script>\n")
        #expect(document.html.contains("# není nadpis\n*a* &lt;script&gt;x&lt;/script&gt;"))
        #expect(!document.html.contains("<h1"))
        #expect(!document.html.contains("<script"))
        #expect(document.outline.isEmpty)
    }

    @Test func blocksKeepOriginalLineNumbers() {
        let document = PlainText.render("a\nbb\n\n\nc\n")
        #expect(document.html.contains("data-sourcepos=\"1:1-2:2\""))
        #expect(document.html.contains("data-sourcepos=\"5:1-5:1\""))
        #expect(document.html.components(separatedBy: "<pre").count == 3)
    }

    @Test func sourcePaneHasNoMarkdownHighlighting() {
        let html = PlainText.render("# x\n", options: RenderOptions(includeSource: true)).sourceHTML ?? ""
        #expect(html == "<div class=\"src-line\" data-line=\"1\"># x</div>")
    }

    @Test(arguments: [
        (Data("Příliš žluťoučký".utf8), String.Encoding.utf8),
        ("Příliš žluťoučký".data(using: .utf16)!, .utf16),
        ("Příliš žluťoučký".data(using: .windowsCP1250)!, .windowsCP1250),
    ])
    func decodesAndRoundTripsEncodings(data: Data, encoding: String.Encoding) {
        let decoded = PlainText.decode(data)
        #expect(decoded.text == "Příliš žluťoučký")
        #expect(decoded.encoding == encoding)
        #expect(decoded.text.data(using: decoded.encoding) == data)
    }

    @Test func extensionsAreCaseInsensitive() {
        #expect(PlainText.isPlainText(URL(fileURLWithPath: "/tmp/A.TXT")))
        #expect(!PlainText.isPlainText(URL(fileURLWithPath: "/tmp/a.md")))
    }
}
