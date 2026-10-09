import Foundation
import Testing
@testable import MarkdownCore

/// Golden testy proti GitHubu: `Fixtures/golden/*.md` se vykreslí naším rendererem a porovná
/// s výstupem GitHub API (`*.github.html`, režim gfm) po normalizaci na sémantickou kostru.
/// Kotvy nadpisů se porovnávají s `*.slugs.txt` (režim markdown, jako README na github.com).
/// Referenční výstupy obnoví `scripts/gh-golden.sh`.
@Suite("Golden testy proti GitHubu")
struct GoldenTests {
    static let directory = Bundle.module.url(forResource: "Fixtures/golden", withExtension: nil)!

    static let fixtures: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
    }()

    /// Rozdíly, které jsou záměrné nebo plynou z toho, že GitHub API vykresluje jako komentář.
    static let knownDifferences: [String: String] = [
        "25-math-display": "GitHub v $$ odstavci zpracuje markdown escapy (\\, → ,) a poškodí TeX; MDView TeX zachovává doslova.",
        "26-math-edge": "GitHub z escapovaných \\$x\\$ udělá matiku; MDView je bere jako obyčejné dolary (escape má platit).",
    ]

    @Test func enoughFixtures() {
        #expect(Self.fixtures.count >= 40)
    }

    @Test(arguments: fixtures)
    func matchesGitHub(fixture: String) throws {
        let source = try String(contentsOf: Self.directory.appendingPathComponent("\(fixture).md"), encoding: .utf8)
        let github = try String(contentsOf: Self.directory.appendingPathComponent("\(fixture).github.html"), encoding: .utf8)
        let ours = MarkdownRenderer.render(source).html
        let expected = HTMLCanonicalizer.canonical(github)
        let actual = HTMLCanonicalizer.canonical(ours)
        if let reason = Self.knownDifferences[fixture] {
            withKnownIssue(Comment(rawValue: reason)) {
                #expect(actual == expected)
            }
            return
        }
        #expect(actual == expected, Comment(rawValue: HTMLCanonicalizer.diff(expected: expected, actual: actual)))
    }

    @Test(arguments: fixtures)
    func slugsMatchGitHub(fixture: String) throws {
        let slugsURL = Self.directory.appendingPathComponent("\(fixture).slugs.txt")
        guard FileManager.default.fileExists(atPath: slugsURL.path) else { return }
        let source = try String(contentsOf: Self.directory.appendingPathComponent("\(fixture).md"), encoding: .utf8)
        let expected = try String(contentsOf: slugsURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(MarkdownRenderer.render(source).outline.map(\.slug) == expected)
    }
}

/// Převede HTML GitHubu i naše HTML na společnou kanonickou podobu.
enum HTMLCanonicalizer {
    static func canonical(_ html: String) -> String {
        var text = html
        // Speciální konstrukce → společné značky mdv-*.
        text = replace(#"<section[^>]*data-type="mermaid"[^>]*>.*?<pre lang="mermaid"[^>]*>(.*?)</pre>.*?</section>"#, in: text) {
            "<mdv-mermaid>\(trimmed($0[1]))</mdv-mermaid>"
        }
        // API vrací Mermaid nekonzistentně – někdy jen jako zvýrazněný kód.
        text = replace(#"<div class="highlight highlight-source-mermaid"[^>]*><pre[^>]*>(.*?)</pre></div>"#, in: text) {
            "<mdv-mermaid>\(trimmed($0[1]))</mdv-mermaid>"
        }
        text = replace(#"<pre[^>]*><code class="language-mermaid"[^>]*>(.*?)</code></pre>"#, in: text) {
            "<mdv-mermaid>\(trimmed($0[1]))</mdv-mermaid>"
        }
        text = replace(#"<math-renderer class="js-inline-math"[^>]*>\$(.*?)\$</math-renderer>"#, in: text) {
            "<mdv-math-inline>\(trimmed($0[1]))</mdv-math-inline>"
        }
        text = replace(#"<math-renderer class="js-display-math"[^>]*>\$\$(.*?)\$\$</math-renderer>"#, in: text) {
            "<mdv-math-display>\(trimmed($0[1]))</mdv-math-display>"
        }
        text = replace(#"<span class="math math-inline">(.*?)</span>"#, in: text) {
            "<mdv-math-inline>\(trimmed($0[1]))</mdv-math-inline>"
        }
        text = replace(#"<(?:span|div) class="math math-display"[^>]*>(.*?)</(?:span|div)>"#, in: text) {
            "<mdv-math-display>\(trimmed($0[1]))</mdv-math-display>"
        }
        text = replace(#"<div class="highlight highlight-[^"]*"[^>]*><pre[^>]*>(.*?)</pre></div>"#, in: text) {
            "<mdv-code>\(trimmed($0[1]))</mdv-code>"
        }
        text = replace(#"<pre[^>]*><code[^>]*>(.*?)</code></pre>"#, in: text) {
            "<mdv-code>\(trimmed($0[1]))</mdv-code>"
        }
        text = replace(#"<div class="markdown-alert markdown-alert-(\w+)"[^>]*><p class="markdown-alert-title"[^>]*>.*?</p>"#, in: text) {
            "<mdv-alert-\($0[1])>"
        }
        // Obal obrázku, který GitHub přidává, kotvy nadpisů, ikony a popisky pro čtečky.
        text = replace(#"<a target="_blank" rel="noopener noreferrer" href="[^"]*">(<img[^>]*>)</a>"#, in: text) { $0[1] }
        text = replace(#"<a id="[^"]*" class="anchor"[^>]*>.*?</a>"#, in: text) { _ in "" }
        text = replace(#"<h2 id="footnote-label"[^>]*>.*?</h2>"#, in: text) { _ in "" }
        text = replace(#"<svg.*?</svg>"#, in: text) { _ in "" }
        text = replace(#"<!--.*?-->"#, in: text) { _ in "" }

        var output = ""
        for token in tokens(text) {
            if token.hasPrefix("<") {
                output += canonicalTag(token)
            } else {
                output += decodeEntities(token)
            }
        }
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let blockTags = "p|li|ul|ol|blockquote|h[1-6]|table|thead|tbody|tr|th|td|section|div|details|summary|hr|mdv-[a-z-]+"
        output = output.replacingOccurrences(
            of: #"\s*(</?(?:\#(blockTags))(?: [^>]*)?>)\s*"#,
            with: "$1",
            options: .regularExpression
        )
        return output.trimmingCharacters(in: .whitespaces)
    }

    /// Čitelný rozdíl: rozdělí podle značek a ukáže první odlišné místo.
    static func diff(expected: String, actual: String) -> String {
        let split: (String) -> [String] = { $0.replacingOccurrences(of: "><", with: ">\n<").components(separatedBy: "\n") }
        let left = split(expected)
        let right = split(actual)
        let common = min(left.count, right.count)
        guard let index = (0..<common).first(where: { left[$0] != right[$0] }) ?? (left.count != right.count ? common : nil) else {
            return "shodné"
        }
        let from = max(0, index - 2)
        return """
        první rozdíl na řádku \(index)
        GitHub: \(left[from..<min(left.count, index + 3)].joined(separator: " ⏎ "))
        MDView: \(right[from..<min(right.count, index + 3)].joined(separator: " ⏎ "))
        """
    }

    // MARK: - Pomocné

    private static let keptAttributes: [String: Set<String>] = [
        "a": ["href"],
        "img": ["src", "alt", "title", "width", "height"],
        "th": ["align"],
        "td": ["align"],
        "input": ["type", "checked"],
        "ol": ["start"],
        "source": ["srcset", "media"],
    ]
    private static let droppedTags: Set<String> = ["span", "themed-picture", "g-emoji", "markdown-accessiblity-table"]
    private static let voidTags: Set<String> = ["hr", "img", "input", "source"]

    private static func tokens(_ html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"<[^>]*>|[^<]+"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { Range($0.range, in: html).map { String(html[$0]) } }
    }

    private static func canonicalTag(_ tag: String) -> String {
        guard let nameMatch = tag.range(of: #"^</?[a-zA-Z0-9-]+"#, options: .regularExpression) else { return "" }
        let isClosing = tag.hasPrefix("</")
        let name = tag[nameMatch].replacingOccurrences(of: "<", with: "").replacingOccurrences(of: "/", with: "").lowercased()
        if name == "br" { return " " }
        if droppedTags.contains(name) { return "" }
        if isClosing { return voidTags.contains(name) ? "" : "</\(name)>" }

        var attributes: [String] = []
        let allowed = keptAttributes[name] ?? []
        let attributeRegex = try! NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*"([^"]*)")?"#)
        let body = String(tag[nameMatch.upperBound...])
        for match in attributeRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let keyRange = Range(match.range(at: 1), in: body) else { continue }
            let key = body[keyRange].lowercased()
            guard allowed.contains(key) else { continue }
            var value = Range(match.range(at: 2), in: body).map { String(body[$0]) } ?? ""
            if key == "checked" { value = "" }
            if key == "src" { value = decodeCamo(value) }
            if key == "href" {
                value = value.replacingOccurrences(of: "#user-content-", with: "#")
                value = value.replacingOccurrences(of: #"-[0-9a-f]{32}$"#, with: "", options: .regularExpression)
            }
            attributes.append(value.isEmpty ? key : "\(key)=\"\(decodeEntities(value))\"")
        }
        attributes.sort()
        return "<\(([name] + attributes).joined(separator: " "))>"
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&nbsp;": "\u{A0}", "&copy;": "©"]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        result = replace(#"&#(x?)([0-9a-fA-F]+);"#, in: result) { groups in
            let value = groups[1].isEmpty ? UInt32(groups[2], radix: 10) : UInt32(groups[2], radix: 16)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? groups[0]
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// GitHub posílá externí obrázky přes proxy camo; poslední část cesty je hex původní URL.
    private static func decodeCamo(_ url: String) -> String {
        guard url.hasPrefix("https://camo.githubusercontent.com/"),
              let hex = url.split(separator: "/").last, hex.count.isMultiple(of: 2) else { return url }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return url }
            bytes.append(byte)
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            result += text[last..<range.lowerBound]
            result += transform(groups)
            last = range.upperBound
        }
        return result + text[last...]
    }
}
