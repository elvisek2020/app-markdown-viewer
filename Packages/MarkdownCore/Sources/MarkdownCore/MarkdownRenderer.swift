import CMarkMath
import cmark_gfm
import cmark_gfm_extensions
import Foundation

public struct RenderOptions: Sendable, Equatable {
    public enum FrontMatterMode: String, Sendable, CaseIterable {
        /// Tabulka klíč–hodnota jako na GitHubu.
        case table
        /// Sbalitelný blok s YAML.
        case collapsed
        /// Front matter se nezobrazí.
        case hidden
    }

    public var frontMatter: FrontMatterMode
    public var math: Bool
    public var alerts: Bool
    public var headingAnchors: Bool

    public init(
        frontMatter: FrontMatterMode = .table,
        math: Bool = true,
        alerts: Bool = true,
        headingAnchors: Bool = true
    ) {
        self.frontMatter = frontMatter
        self.math = math
        self.alerts = alerts
        self.headingAnchors = headingAnchors
    }
}

public struct OutlineItem: Sendable, Equatable, Identifiable {
    public let level: Int
    public let title: String
    public let slug: String
    /// Řádek nadpisu v původním souboru (1-based), navigace jde přes `data-sourcepos`.
    public let line: Int

    public var id: String { slug }
}

public struct DocumentFeatures: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let math = DocumentFeatures(rawValue: 1 << 0)
    public static let mermaid = DocumentFeatures(rawValue: 1 << 1)
    public static let code = DocumentFeatures(rawValue: 1 << 2)
}

public struct RenderedDocument: Sendable, Equatable {
    /// HTML fragment obsahu (bez `<html>`/`<body>`), bloky nesou `data-sourcepos`.
    public let html: String
    public let outline: [OutlineItem]
    public let frontMatter: FrontMatter?
    /// Co dokument obsahuje – podle toho web vrstva líně načte KaTeX, Mermaid nebo highlight.js.
    public let features: DocumentFeatures
    public let wordCount: Int
}

/// Markdown → HTML kompatibilní s GitHubem: cmark-gfm (GFM + footnotes) + matika,
/// GitHub alerts, kotvy nadpisů a front matter. Bezstavové a bezpečné pro volání z více vláken.
public enum MarkdownRenderer {
    private static let coreExtensions = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    private static let registered: Bool = {
        cmark_gfm_core_extensions_ensure_registered()
        return true
    }()

    public static func render(_ source: String, options: RenderOptions = RenderOptions()) -> RenderedDocument {
        precondition(registered)

        let withoutBOM = source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source
        let (frontMatter, body) = FrontMatterExtractor.extract(from: withoutBOM)

        let cmarkOptions = CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES | CMARK_OPT_UNSAFE
        guard let parser = cmark_parser_new(cmarkOptions) else {
            preconditionFailure("cmark_parser_new selhal")
        }
        defer { cmark_parser_free(parser) }

        for name in coreExtensions {
            if let extensionPointer = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, extensionPointer)
            }
        }
        if options.math {
            cmark_parser_attach_syntax_extension(parser, cmark_math_extension())
        }

        var utf8 = Array(body.utf8)
        utf8.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                cmark_parser_feed(parser, $0, buffer.count)
            }
        }
        guard let document = cmark_parser_finish(parser) else {
            preconditionFailure("cmark_parser_finish selhal")
        }
        defer { cmark_node_free(document) }

        var transformer = ASTTransformer(options: options)
        transformer.run(on: document)

        var html = ""
        if let frontMatter {
            html += FrontMatterHTML.render(frontMatter, mode: options.frontMatter)
        }
        if let rendered = cmark_render_html(document, cmarkOptions, cmark_parser_get_syntax_extensions(parser)) {
            html += String(cString: rendered)
            free(rendered)
        }

        return RenderedDocument(
            html: html,
            outline: transformer.outline,
            frontMatter: frontMatter,
            features: transformer.features,
            wordCount: transformer.wordCount
        )
    }
}

/// Úpravy AST po parsování: alerts, kotvy nadpisů, ```math bloky, sběr outline a statistik.
private struct ASTTransformer {
    let options: RenderOptions
    var outline: [OutlineItem] = []
    var features: DocumentFeatures = []
    var wordCount = 0
    private var slugger = Slugger()

    init(options: RenderOptions) {
        self.options = options
    }

    mutating func run(on document: CMarkNode) {
        // Nejdřív posbírat, pak měnit – úpravy stromu během průchodu nejsou bezpečné.
        let nodes = document.descendants
        for node in nodes {
            switch node.type {
            case CMARK_NODE_HEADING:
                processHeading(node)
            case CMARK_NODE_CODE_BLOCK:
                processCodeBlock(node)
            case CMARK_NODE_TEXT:
                wordCount += Self.countWords(node.literal ?? "")
            case CMARK_NODE_CODE where cmark_math_node_is_math(node) != 0:
                features.insert(.math)
            default:
                break
            }
        }
        if options.alerts {
            for node in document.children where node.type == CMARK_NODE_BLOCK_QUOTE {
                AlertTransformer.transform(node)
            }
        }
    }

    private mutating func processHeading(_ heading: CMarkNode) {
        let title = Self.plainText(of: heading).trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = slugger.slug(for: title)
        outline.append(OutlineItem(level: heading.headingLevel, title: title, slug: slug, line: heading.startLine))
        guard options.headingAnchors else { return }
        let escaped = HTMLEscaping.escape(slug)
        let anchor = makeCustomInline(
            onEnter: "<a id=\"\(escaped)\" class=\"anchor\" aria-hidden=\"true\" href=\"#\(escaped)\"></a>",
            onExit: ""
        )
        cmark_node_prepend_child(heading, anchor)
    }

    private mutating func processCodeBlock(_ block: CMarkNode) {
        let language = block.fenceInfo.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        switch language {
        case "mermaid":
            features.insert(.mermaid)
        case "math" where options.math:
            features.insert(.math)
            let tex = HTMLEscaping.escape(block.literal ?? "")
            let replacement = makeCustomBlock(
                onEnter: "<div class=\"math math-display\" data-sourcepos=\"\(block.sourcepos)\">\(tex)</div>",
                onExit: ""
            )
            cmark_node_insert_before(block, replacement)
            cmark_node_free(block)
        default:
            features.insert(.code)
        }
    }

    /// Text nadpisu tak, jak by ho vrátil `textContent` (bez HTML značek a obrázků).
    static func plainText(of node: CMarkNode) -> String {
        var result = ""
        for child in node.children {
            switch child.type {
            case CMARK_NODE_TEXT, CMARK_NODE_CODE:
                result += child.literal ?? ""
            case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
                result += " "
            case CMARK_NODE_IMAGE, CMARK_NODE_HTML_INLINE:
                break
            default:
                result += plainText(of: child)
            }
        }
        return result
    }

    static func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// GitHub alerts: top-level blockquote, jehož první řádek je jen `[!NOTE]`, `[!TIP]`,
/// `[!IMPORTANT]`, `[!WARNING]` nebo `[!CAUTION]` (velikost písmen nehraje roli).
enum AlertKind: String, CaseIterable, Sendable {
    case note, tip, important, warning, caution

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Název octiconu, který kreslí CSS (`mdv-octicon-…`).
    var icon: String {
        switch self {
        case .note: "info"
        case .tip: "light-bulb"
        case .important: "report"
        case .warning: "alert"
        case .caution: "stop"
        }
    }

    init?(marker: String) {
        let trimmed = marker.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]") else { return nil }
        let name = trimmed.dropFirst(2).dropLast().lowercased()
        self.init(rawValue: name)
    }
}

private enum AlertTransformer {
    static func transform(_ blockquote: CMarkNode) {
        guard let paragraph = blockquote.firstChild, paragraph.type == CMARK_NODE_PARAGRAPH else { return }

        // Značka může být rozdělená do více textových uzlů („[“, „!NOTE“, „]“).
        var marker = ""
        var markerNodes: [CMarkNode] = []
        var cursor = paragraph.firstChild
        while let node = cursor, node.type == CMARK_NODE_TEXT {
            marker += node.literal ?? ""
            markerNodes.append(node)
            cursor = node.next
        }
        if let breakNode = cursor, breakNode.type != CMARK_NODE_SOFTBREAK, breakNode.type != CMARK_NODE_LINEBREAK {
            return
        }
        guard let kind = AlertKind(marker: marker) else { return }

        markerNodes.forEach { cmark_node_free($0) }
        if let breakNode = cursor { cmark_node_free(breakNode) }
        if paragraph.firstChild == nil { cmark_node_free(paragraph) }

        let alert = makeCustomBlock(
            onEnter: """
            <div class="markdown-alert markdown-alert-\(kind.rawValue)" data-sourcepos="\(blockquote.sourcepos)">\
            <p class="markdown-alert-title"><span class="mdv-octicon mdv-octicon-\(kind.icon)" aria-hidden="true"></span>\(kind.title)</p>
            """,
            onExit: "</div>"
        )
        while let child = blockquote.firstChild {
            cmark_node_append_child(alert, child)
        }
        cmark_node_insert_before(blockquote, alert)
        cmark_node_free(blockquote)
    }
}

private enum FrontMatterHTML {
    static func render(_ frontMatter: FrontMatter, mode: RenderOptions.FrontMatterMode) -> String {
        let sourcepos = "1:1-\(frontMatter.lineCount):3"
        switch mode {
        case .hidden:
            return ""
        case .table:
            let headers = frontMatter.fields.map { "<th>\(HTMLEscaping.escape($0.key))</th>" }.joined()
            let values = frontMatter.fields.map { "<td>\(HTMLEscaping.escape($0.value))</td>" }.joined()
            return """
            <table class="mdv-frontmatter" data-sourcepos="\(sourcepos)">\
            <thead><tr>\(headers)</tr></thead><tbody><tr>\(values)</tr></tbody></table>

            """
        case .collapsed:
            return """
            <details class="mdv-frontmatter" data-sourcepos="\(sourcepos)"><summary>Front matter</summary>\
            <pre><code class="language-yaml">\(HTMLEscaping.escape(frontMatter.yaml))</code></pre></details>

            """
        }
    }
}
