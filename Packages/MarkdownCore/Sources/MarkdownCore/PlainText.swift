import Foundation

/// Prosté textové soubory (.txt, .cfg, .log): zobrazují se doslova, bez interpretace Markdownu.
public enum PlainText {
    /// Poznámky a konfigurace: otevírají se v editoru přes celé okno.
    public static let editableExtensions: Set<String> = ["txt", "text", "cfg"]
    /// Logy připisuje jiný proces, proto jsou jen ke čtení.
    public static let readOnlyExtensions: Set<String> = ["log"]
    public static var extensions: Set<String> { editableExtensions.union(readOnlyExtensions) }
    /// Log často nemá prázdné řádky; delší souvislý text se dělí, aby se při připsání na konec
    /// nepřekreslovalo všechno a synchronizace se zdrojem měla po čem jít.
    private static let maxBlockLines = 100

    public static func isPlainText(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func isEditableText(_ url: URL) -> Bool {
        editableExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isReadOnly(_ url: URL) -> Bool {
        readOnlyExtensions.contains(url.pathExtension.lowercased())
    }

    /// Text souboru a jeho kódování (stejným se pak ukládá). Textové soubory bývají i ve starších
    /// kódováních: UTF-8 → UTF-16 s BOM → Windows-1250 → Latin-1, které přečte cokoli.
    public static func decode(_ data: Data) -> (text: String, encoding: String.Encoding) {
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, .utf16)
        }
        if let text = String(data: data, encoding: .windowsCP1250) { return (text, .windowsCP1250) }
        return (String(decoding: data.map(UInt16.init), as: UTF16.self), .isoLatin1)
    }

    /// Bloky oddělené prázdnými řádky, každý s `data-sourcepos` – funguje tak překreslování
    /// jen změněných bloků i synchronizace se zdrojem a editorem jako u Markdownu.
    public static func render(_ source: String, options: RenderOptions = RenderOptions()) -> RenderedDocument {
        let text = source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source
        let lines = text.markdownLines().map(String.init)
        var html = ""
        var block: [String] = []
        var firstLine = 1

        func flush(continued: Bool = false) {
            guard let last = block.last else { return }
            let classes = continued ? "mdv-plain mdv-plain-continued" : "mdv-plain"
            let sourcepos = "\(firstLine):1-\(firstLine + block.count - 1):\(max(last.utf8.count, 1))"
            html += "<pre class=\"\(classes)\" data-sourcepos=\"\(sourcepos)\">\(block.map(HTMLEscaping.escape).joined(separator: "\n"))</pre>\n"
            block = []
        }
        for (index, line) in lines.enumerated() {
            if line.allSatisfy(\.isWhitespace) {
                flush()
            } else {
                if block.count == maxBlockLines { flush(continued: true) }
                if block.isEmpty { firstLine = index + 1 }
                block.append(line)
            }
        }
        flush()

        return RenderedDocument(
            html: html,
            outline: [],
            frontMatter: nil,
            features: [],
            wordCount: text.split(whereSeparator: \.isWhitespace).count,
            sourceHTML: options.includeSource ? SourceHighlighter.plainHTML(for: text) : nil
        )
    }
}
