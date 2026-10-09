import Foundation

/// YAML front matter na začátku dokumentu (`---` … `---` nebo `...`).
public struct FrontMatter: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public let key: String
        public let value: String
    }

    /// YAML bez oddělovacích řádků.
    public let yaml: String
    /// Počet řádků včetně obou oddělovačů. Tyto řádky se před parsováním nahradí prázdnými,
    /// takže čísla řádků v `data-sourcepos` odpovídají původnímu souboru.
    public let lineCount: Int
    /// Klíče nejvyšší úrovně pro zobrazení v tabulce (jako GitHub). Složitější hodnoty zůstávají jako text.
    public let fields: [Field]
}

enum FrontMatterExtractor {
    /// Front matter musí mít aspoň jeden řádek `klíč: hodnota`, jinak jde nejspíš o vodorovnou čáru.
    static func extract(from source: String) -> (frontMatter: FrontMatter?, body: String) {
        guard source.hasPrefix("---") else { return (nil, source) }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, isDelimiter(first, allowDots: false) else { return (nil, source) }

        var closingIndex: Int?
        for index in lines.indices.dropFirst() where isDelimiter(lines[index], allowDots: true) {
            closingIndex = index
            break
        }
        guard let closingIndex else { return (nil, source) }

        let yamlLines = lines[1..<closingIndex].map { String($0.hasSuffix("\r") ? $0.dropLast() : $0) }
        let fields = parseFields(yamlLines)
        guard !fields.isEmpty else { return (nil, source) }

        let frontMatter = FrontMatter(
            yaml: yamlLines.joined(separator: "\n"),
            lineCount: closingIndex + 1,
            fields: fields
        )
        let blanks = Array(repeating: Substring(""), count: closingIndex + 1)
        let body = (blanks + lines[(closingIndex + 1)...]).joined(separator: "\n")
        return (frontMatter, body)
    }

    private static func isDelimiter(_ line: Substring, allowDots: Bool) -> Bool {
        let trimmed = line.trimmingTrailingWhitespace()
        return trimmed == "---" || (allowDots && trimmed == "...")
    }

    /// Jednoduchý parser klíčů nejvyšší úrovně. Odsazené řádky pod klíčem se připojí k jeho hodnotě.
    private static func parseFields(_ lines: [String]) -> [FrontMatter.Field] {
        var fields: [(key: String, value: [String])] = []
        for line in lines {
            if line.trimmingTrailingWhitespace().isEmpty || line.hasPrefix("#") { continue }
            let isIndented = line.first == " " || line.first == "\t" || line.hasPrefix("- ")
            if isIndented, !fields.isEmpty {
                fields[fields.count - 1].value.append(line.trimmingCharacters(in: .whitespaces))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let afterColon = line.index(after: colon)
            guard afterColon == line.endIndex || line[afterColon] == " " || line[afterColon] == "\t" else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains(" ") || key.first == "\"" || key.first == "'" else { continue }
            let value = String(line[afterColon...]).trimmingCharacters(in: .whitespaces)
            fields.append((unquote(key), value.isEmpty ? [] : [value]))
        }
        return fields.map { FrontMatter.Field(key: $0.key, value: unquote($0.value.joined(separator: "\n"))) }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }
}

extension StringProtocol {
    func trimmingTrailingWhitespace() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}
