import Foundation

/// Zvýraznění Markdown zdroje pro read-only panel vedle náhledu.
///
/// Každý řádek je `<div class="src-line" data-line="N">` – podle `data-line` a `data-sourcepos`
/// v náhledu se synchronizuje scroll. Zvýraznění je řádkové (s jednoduchým stavem pro front matter
/// a fenced bloky kódu); nemá být parser, jen čitelný přehled.
public enum SourceHighlighter {
    public static func html(for source: String) -> String {
        let text = source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source
        var lines = text.markdownLines().map(String.init)
        if lines.count > 1, lines.last == "" { lines.removeLast() }

        let frontMatterLines = FrontMatterExtractor.extract(from: text).frontMatter?.lineCount ?? 0
        var fence: (marker: Character, length: Int)?
        var output = ""
        output.reserveCapacity(text.utf8.count * 2)

        for (index, line) in lines.enumerated() {
            let number = index + 1
            let (cssClass, body): (String, String)
            if number <= frontMatterLines {
                (cssClass, body) = ("src-frontmatter", escape(line))
            } else if let open = fence {
                if isFence(line, closing: open) {
                    fence = nil
                    (cssClass, body) = ("src-fence", escape(line))
                } else {
                    (cssClass, body) = ("src-code", escape(line))
                }
            } else if let opening = fenceOpening(line) {
                fence = opening
                (cssClass, body) = ("src-fence", escape(line))
            } else {
                (cssClass, body) = highlightBlock(line)
            }
            output += "<div class=\"src-line \(cssClass)\" data-line=\"\(number)\">\(body)</div>"
        }
        return output
    }

    // MARK: - Bloky

    private static func highlightBlock(_ line: String) -> (String, String) {
        let trimmed = line.drop { $0 == " " }
        let indent = line.count - trimmed.count
        if indent <= 3, let level = headingLevel(trimmed) {
            return ("src-heading src-h\(level)", escape(line))
        }
        if indent <= 3, isThematicBreak(trimmed) {
            return ("src-hr", escape(line))
        }
        if line.hasPrefix("    ") || line.hasPrefix("\t") {
            return ("src-indented", escape(line))
        }

        var prefix = ""
        var rest = Substring(line)
        // Citace (i vnořené) a značky seznamů na začátku řádku.
        if let match = rest.prefixMatch(of: /\s*(?:>\s?)+/) {
            prefix += span("src-quote", String(match.output))
            rest = rest[match.range.upperBound...]
        }
        if let match = rest.prefixMatch(of: /\s*(?:[-*+]|\d{1,9}[.)])\s+/) {
            prefix += span("src-list", String(match.output))
            rest = rest[match.range.upperBound...]
            if let task = rest.prefixMatch(of: /\[[ xX]\]\s/) {
                prefix += span("src-task", String(task.output))
                rest = rest[task.range.upperBound...]
            }
        }
        let cssClass = rest.trimmingCharacters(in: .whitespaces).hasPrefix("|") ? "src-table" : "src-text"
        return (cssClass, prefix + highlightInline(String(rest)))
    }

    private static func headingLevel(_ text: Substring) -> Int? {
        let hashes = text.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let after = text.dropFirst(hashes)
        return after.isEmpty || after.first == " " || after.first == "\t" ? hashes : nil
    }

    private static func isThematicBreak(_ text: Substring) -> Bool {
        let characters = text.filter { !$0.isWhitespace }
        guard characters.count >= 3, let first = characters.first, "-*_".contains(first) else { return false }
        return characters.allSatisfy { $0 == first }
    }

    private static func fenceOpening(_ line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        // Info string backtickového fence nesmí obsahovat backtick.
        if marker == "`", trimmed.dropFirst(length).contains("`") { return nil }
        return (marker, length)
    }

    private static func isFence(_ line: String, closing open: (marker: Character, length: Int)) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3 else { return false }
        let length = trimmed.prefix { $0 == open.marker }.count
        return length >= open.length && trimmed.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    // MARK: - Inline

    private static let inlinePattern = try! NSRegularExpression(pattern: [
        #"(?<code>(`+)(?:(?!\2).)+?\2)"#,
        #"(?<math>\$\$[^$]+\$\$|\$[^\s$][^$]*?\$)"#,
        #"(?<link>!?\[[^\]\n]*\]\([^)\n]*\)|!?\[[^\]\n]*\]\[[^\]\n]*\])"#,
        #"(?<autolink><(?:https?|mailto):[^>\s]+>)"#,
        #"(?<strong>\*\*[^*\n]+\*\*|__[^_\n]+__)"#,
        #"(?<emphasis>\*[^*\s][^*\n]*\*|(?<![\w])_[^_\s][^_\n]*_(?![\w]))"#,
        #"(?<strike>~~[^~\n]+~~)"#,
        #"(?<html></?[a-zA-Z][^>\n]*>)"#,
        #"(?<emoji>:[a-z0-9_+-]+:)"#,
    ].joined(separator: "|"))

    private static let inlineGroups = ["code", "math", "link", "autolink", "strong", "emphasis", "strike", "html", "emoji"]

    private static func highlightInline(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var cursor = text.startIndex
        for match in inlinePattern.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let group = inlineGroups.first { match.range(withName: $0).location != NSNotFound } ?? "text"
            result += escape(text[cursor..<matchRange.lowerBound])
            result += span("src-\(group)", String(text[matchRange]))
            cursor = matchRange.upperBound
        }
        return result + escape(text[cursor...])
    }

    // MARK: - Pomocné

    private static func span(_ cssClass: String, _ text: String) -> String {
        "<span class=\"\(cssClass)\">\(escape(text))</span>"
    }

    private static func escape<S: StringProtocol>(_ text: S) -> String {
        HTMLEscaping.escape(String(text))
    }
}
