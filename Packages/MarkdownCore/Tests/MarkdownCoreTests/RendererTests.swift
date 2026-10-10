import Testing
@testable import MarkdownCore

private func html(_ markdown: String, _ options: RenderOptions = RenderOptions()) -> String {
    MarkdownRenderer.render(markdown, options: options).html
}

@Suite("GFM základ")
struct GFMTests {
    @Test func paragraphsCarrySourcepos() {
        #expect(html("Ahoj\n\nsvěte").contains("<p data-sourcepos=\"3:1-3:6\">světe</p>"))
    }

    @Test func tableHasSourceposOnRows() {
        let output = html("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(output.contains("<table data-sourcepos=\"1:1-3:9\">"))
        #expect(output.contains("<tr data-sourcepos=\"3:1-3:9\">"))
    }

    @Test func taskList() {
        let output = html("- [x] hotovo\n- [ ] zbývá")
        #expect(output.contains("<input type=\"checkbox\" checked=\"\" disabled=\"\" />"))
        #expect(output.contains("<input type=\"checkbox\" disabled=\"\" />"))
    }

    @Test func strikethroughAndAutolink() {
        let output = html("~~staré~~ https://example.com")
        #expect(output.contains("<del>staré</del>"))
        #expect(output.contains("<a href=\"https://example.com\">https://example.com</a>"))
    }

    @Test func footnotes() {
        let output = html("Text[^1].\n\n[^1]: Poznámka.")
        #expect(output.contains("<section class=\"footnotes\""))
        #expect(output.contains("href=\"#fn-1\""))
    }

    @Test func tagfilterEscapesScript() {
        let output = html("<script>alert(1)</script>\n\nok")
        #expect(output.contains("&lt;script>"))
        #expect(!output.contains("<script>"))
    }

    @Test func crlfLineEndings() {
        let output = html("# Nadpis\r\n\r\nOdstavec\r\n")
        #expect(output.contains("<p data-sourcepos=\"3:1-3:8\">Odstavec</p>"))
    }

    @Test func byteOrderMarkIsIgnored() {
        #expect(html("\u{FEFF}# Nadpis").contains("<h1 data-sourcepos=\"1:1-1:8\">"))
    }

    @Test func detectsFeatures() {
        let document = MarkdownRenderer.render("```mermaid\ngraph TD; A-->B\n```\n\n```swift\nlet a = 1\n```")
        #expect(document.features.contains(.mermaid))
        #expect(document.features.contains(.code))
        #expect(!document.features.contains(.math))
    }

    @Test func wordCount() {
        #expect(MarkdownRenderer.render("Jedna dvě **tři**\n\n- čtyři").wordCount == 4)
    }
}

@Suite("Matika")
struct MathTests {
    @Test func inlineMath() {
        #expect(html("Vzorec $x^2$ tady.").contains("<span class=\"math math-inline\">x^2</span>"))
    }

    @Test func underscoresStayLiteral() {
        let output = html("$a_1$ a $b_2$")
        #expect(output.contains("<span class=\"math math-inline\">a_1</span>"))
        #expect(output.contains("<span class=\"math math-inline\">b_2</span>"))
        #expect(!output.contains("<em>"))
    }

    @Test func backslashesStayLiteral() {
        #expect(html("$\\frac{a}{b} \\\\ c$").contains(">\\frac{a}{b} \\\\ c</span>"))
    }

    @Test func displayMathAcrossLines() {
        let output = html("$$\na_1 + b_2\n$$")
        #expect(output.contains("<span class=\"math math-display\">\na_1 + b_2\n</span>"))
    }

    @Test func dollarAmountsAreNotMath() {
        let output = html("Stojí $5 a $10.")
        #expect(!output.contains("math"))
        #expect(output.contains("Stojí $5 a $10."))
    }

    @Test func closingDollarFollowedByDigitIsNotMath() {
        #expect(!html("$x$5").contains("math"))
    }

    @Test func spaceAfterOpeningDollarIsNotMath() {
        #expect(!html("$ x$").contains("math"))
    }

    /// Nalezeno golden testem: matika začínající `$5` přeskočila až do code spanu za ní.
    @Test func inlineMathDoesNotCrossCodeSpan() {
        let output = html("Ceny $5 a $10. Kód `$y$`.")
        #expect(!output.contains("math"))
        #expect(output.contains("<code>$y$</code>"))
    }

    @Test func codeSpanWins() {
        let output = html("`$x$`")
        #expect(output.contains("<code>$x$</code>"))
        #expect(!output.contains("math"))
    }

    @Test func escapedDollarIsNotMath() {
        #expect(!html("\\$x\\$").contains("math"))
    }

    @Test func indentedCodeIsNotMath() {
        let output = html("Text\n\n    $x$\n")
        #expect(output.contains("<pre data-sourcepos=\"3:5-3:7\"><code>$x$\n</code></pre>"))
        #expect(!output.contains("math"))
    }

    @Test func fencedCodeIsNotMath() {
        #expect(!html("```\n$x$\n```").contains("math"))
    }

    @Test func backtickSyntax() {
        #expect(html("$`\\sqrt{2}`$").contains("<span class=\"math math-inline\">\\sqrt{2}</span>"))
    }

    @Test func mathInsideTableBlockquoteAndList() {
        let table = html("| a |\n|---|\n| $x_1$ |")
        #expect(table.contains("<span class=\"math math-inline\">x_1</span>"))
        let quote = html("> $$\n> y\n> $$")
        #expect(quote.contains("<span class=\"math math-display\">\ny\n</span>"))
        let list = html("- $z$")
        #expect(list.contains("<span class=\"math math-inline\">z</span>"))
    }

    @Test func htmlIsEscaped() {
        #expect(html("$a<b$").contains("<span class=\"math math-inline\">a&lt;b</span>"))
    }

    @Test func tripleDollarIsText() {
        #expect(!html("$$$x$$$").contains("math"))
    }

    @Test func mathFence() {
        let output = html("Text\n\n```math\nE = mc^2\n```")
        #expect(output.contains("<div class=\"math math-display\" data-sourcepos=\"3:1-5:3\">E = mc^2\n</div>"))
    }

    @Test func mathCanBeDisabled() {
        let options = RenderOptions(math: false)
        #expect(!html("$x$", options).contains("math"))
    }

    @Test func mathFeatureDetected() {
        #expect(MarkdownRenderer.render("$x$").features.contains(.math))
    }

    @Test func sourceposOfFollowingBlocksIsUnchanged() {
        let output = html("$$\na\n\nb\n$$\n\nKonec")
        #expect(output.contains("<p data-sourcepos=\"7:1-7:5\">Konec</p>"))
    }
}

@Suite("GitHub alerts")
struct AlertTests {
    @Test(arguments: AlertKind.allCases)
    func everyKind(kind: AlertKind) {
        let output = html("> [!\(kind.rawValue.uppercased())]\n> Obsah")
        #expect(output.contains("<div class=\"markdown-alert markdown-alert-\(kind.rawValue)\" data-sourcepos=\"1:1-2:7\">"))
        #expect(output.contains("<p class=\"markdown-alert-title\">"))
        #expect(output.contains("<p>Obsah</p>") || output.contains(">Obsah</p>"))
        #expect(!output.contains("[!"))
        #expect(!output.contains("<blockquote"))
    }

    @Test func lowercaseMarker() {
        #expect(html("> [!warning]\n> Pozor").contains("markdown-alert-warning"))
    }

    @Test func markerWithTextOnSameLineIsBlockquote() {
        let output = html("> [!NOTE] text\n> další")
        #expect(output.contains("<blockquote"))
        #expect(!output.contains("markdown-alert"))
    }

    @Test func unknownKindIsBlockquote() {
        #expect(html("> [!FOO]\n> text").contains("<blockquote"))
    }

    @Test func nestedInListIsBlockquote() {
        #expect(!html("- > [!NOTE]\n  > text").contains("markdown-alert"))
    }

    @Test func multipleParagraphs() {
        let output = html("> [!TIP]\n> První\n>\n> Druhý")
        #expect(output.contains("markdown-alert-tip"))
        #expect(output.contains("První</p>"))
        #expect(output.contains("Druhý</p>"))
    }

    @Test func canBeDisabled() {
        #expect(html("> [!NOTE]\n> text", RenderOptions(alerts: false)).contains("<blockquote"))
    }
}

@Suite("Nadpisy a outline")
struct HeadingTests {
    @Test func anchorAndOutline() {
        let document = MarkdownRenderer.render("# Úvod\n\nText\n\n## Hello, World!\n\n## Hello, World!")
        #expect(document.html.contains("<a id=\"úvod\" class=\"anchor\" aria-hidden=\"true\" href=\"#úvod\"></a>Úvod"))
        #expect(document.outline.map(\.slug) == ["úvod", "hello-world", "hello-world-1"])
        #expect(document.outline.map(\.line) == [1, 5, 7])
        #expect(document.outline.map(\.level) == [1, 2, 2])
    }

    @Test func titleUsesTextContent() {
        let document = MarkdownRenderer.render("## Použij `mdv` a **CLI** ![obr](x.png)")
        #expect(document.outline.first?.title == "Použij mdv a CLI")
    }

    @Test func anchorsCanBeDisabled() {
        #expect(!html("# A", RenderOptions(headingAnchors: false)).contains("anchor"))
    }
}

@Suite("Slugger")
struct SluggerTests {
    @Test(arguments: [
        ("Příliš žluťoučký kůň", "příliš-žluťoučký-kůň"),
        ("Hello, World!", "hello-world"),
        ("API v2.0 (beta)", "api-v20-beta"),
        ("snake_case a kebab-case", "snake_case-a-kebab-case"),
        ("Emoji 🚀 raketa", "emoji--raketa"),
        ("  Mezery  ", "--mezery--"),
    ])
    func baseSlug(input: String, expected: String) {
        #expect(Slugger.baseSlug(input) == expected)
    }

    @Test func duplicates() {
        var slugger = Slugger()
        #expect(["a", "a", "a-1", "a"].map { slugger.slug(for: $0) } == ["a", "a-1", "a-1-1", "a-2"])
    }
}

@Suite("Front matter")
struct FrontMatterTests {
    private let source = "---\ntitle: Ukázka\ntags:\n  - a\n  - b\n---\n# Nadpis\n"

    @Test func keepsLineNumbers() {
        let document = MarkdownRenderer.render(source)
        #expect(document.html.contains("<h1 data-sourcepos=\"7:1-7:8\">"))
        #expect(document.outline.first?.line == 7)
    }

    @Test func parsesFields() throws {
        let frontMatter = try #require(MarkdownRenderer.render(source).frontMatter)
        #expect(frontMatter.lineCount == 6)
        #expect(frontMatter.fields == [
            FrontMatter.Field(key: "title", value: "Ukázka"),
            FrontMatter.Field(key: "tags", value: "- a\n- b"),
        ])
    }

    @Test func tableMode() {
        let output = html(source)
        #expect(output.contains("<table class=\"mdv-frontmatter\" data-sourcepos=\"1:1-6:3\">"))
        #expect(output.contains("<th>title</th><th>tags</th>"))
    }

    @Test func collapsedMode() {
        let output = html(source, RenderOptions(frontMatter: .collapsed))
        #expect(output.contains("<details class=\"mdv-frontmatter\""))
        #expect(output.contains("title: Ukázka"))
    }

    @Test func hiddenMode() {
        let output = html(source, RenderOptions(frontMatter: .hidden))
        #expect(!output.contains("mdv-frontmatter"))
        #expect(!output.contains("Ukázka"))
    }

    @Test func thematicBreakIsNotFrontMatter() {
        let document = MarkdownRenderer.render("---\nJen text\n---\n")
        #expect(document.frontMatter == nil)
        #expect(document.html.contains("<hr"))
    }

    @Test func crlfFrontMatter() {
        let document = MarkdownRenderer.render("---\r\ntitle: x\r\n---\r\n# Nadpis\r\n")
        #expect(document.frontMatter?.fields == [FrontMatter.Field(key: "title", value: "x")])
        #expect(document.outline.first?.line == 4)
    }

    @Test func unclosedIsNotFrontMatter() {
        #expect(MarkdownRenderer.render("---\ntitle: x\n\nText").frontMatter == nil)
    }
}

@Suite("Emoji zkratky")
struct EmojiTests {
    @Test func replacesKnownShortcodes() {
        #expect(html("Hotovo :tada: a :+1:").contains("Hotovo 🎉 a 👍"))
    }

    @Test func keepsUnknownAndTimes() {
        let output = html("V 10:30:45 :neexistuje: a:b:c")
        #expect(output.contains("V 10:30:45 :neexistuje: a:b:c"))
    }

    /// Hranice ověřené proti GitHub API.
    @Test func boundariesLikeGitHub() {
        let output = html("A (:tada:) B :tada:. D Hotovo:tada: E :tada:x G :tada:,:tada: H **:tada:** K :tada::tada:")
        #expect(output.contains("A (:tada:) B :tada:. D Hotovo:tada: E :tada:x G :tada:,:tada: H <strong>🎉</strong> K 🎉🎉"))
    }

    @Test func notInCode() {
        #expect(html("`:rocket:`").contains("<code>:rocket:</code>"))
    }

    @Test func slugIgnoresEmojiLikeGitHub() {
        #expect(MarkdownRenderer.render("# Hello :rocket:").outline.first?.slug == "hello-")
    }

    @Test func canBeDisabled() {
        #expect(html(":rocket:", RenderOptions(emoji: false)).contains(":rocket:"))
    }
}
