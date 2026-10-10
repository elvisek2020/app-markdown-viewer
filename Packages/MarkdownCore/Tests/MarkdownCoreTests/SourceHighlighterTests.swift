import Testing
@testable import MarkdownCore

@Suite("Zvýraznění zdroje")
struct SourceHighlighterTests {
    private func lines(_ source: String) -> [String] {
        SourceHighlighter.html(for: source)
            .components(separatedBy: "</div>")
            .filter { !$0.isEmpty }
    }

    @Test func everyLineHasNumber() {
        let output = lines("# A\n\ntext\n")
        #expect(output.count == 3)
        #expect(output[0].hasPrefix("<div class=\"src-line src-heading src-h1\" data-line=\"1\">"))
        #expect(output[1].contains("data-line=\"2\""))
        #expect(output[2].contains("data-line=\"3\""))
    }

    @Test func fencedCodeIsNotHighlightedInline() {
        let output = lines("```swift\nlet a = `x` **b**\n```\n**tučně**")
        #expect(output[0].contains("src-fence"))
        #expect(output[1].contains("src-code"))
        #expect(!output[1].contains("src-strong"))
        #expect(output[2].contains("src-fence"))
        #expect(output[3].contains("<span class=\"src-strong\">**tučně**</span>"))
    }

    @Test func frontMatterLines() {
        let output = lines("---\ntitle: x\n---\n# Nadpis")
        #expect(output[0...2].allSatisfy { $0.contains("src-frontmatter") })
        #expect(output[3].contains("src-heading"))
    }

    @Test func listsQuotesAndTasks() {
        let output = lines("> - [x] hotovo s `kódem`")
        #expect(output[0].contains("<span class=\"src-quote\">&gt; </span>"))
        #expect(output[0].contains("<span class=\"src-list\">- </span>"))
        #expect(output[0].contains("<span class=\"src-task\">[x] </span>"))
        #expect(output[0].contains("<span class=\"src-code\">`kódem`</span>"))
    }

    @Test func inlineElements() {
        let output = SourceHighlighter.html(for: "[odkaz](https://a.cz) $x^2$ ~~s~~ <kbd>K</kbd> :tada: *k*")
        for cssClass in ["src-link", "src-math", "src-strike", "src-html", "src-emoji", "src-emphasis"] {
            #expect(output.contains("class=\"\(cssClass)\""), "\(cssClass)")
        }
    }

    @Test func htmlIsEscaped() {
        let output = SourceHighlighter.html(for: "<script>alert('x')</script> & \"")
        #expect(!output.contains("<script>"))
        #expect(output.contains("&amp;"))
    }

    @Test func crlfAndTrailingNewline() {
        #expect(lines("a\r\nb\r\n").count == 2)
    }

    @Test func snakeCaseIsNotEmphasis() {
        #expect(!SourceHighlighter.html(for: "snake_case_slovo").contains("src-emphasis"))
    }
}
