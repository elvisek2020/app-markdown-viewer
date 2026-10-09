import Foundation

/// Bundlované web soubory náhledu (šablona, CSS, JS a vendorované knihovny).
public enum WebAssets {
    /// Kořen `web/` v resource bundlu balíčku.
    public static let root: URL = {
        guard let url = Bundle.module.url(forResource: "web", withExtension: nil) else {
            preconditionFailure("WebAssets: chybí adresář web v bundlu")
        }
        return url.standardizedFileURL
    }()

    /// Soubor podle relativní cesty (`vendor/katex/katex.min.css`). Cesty mimo `web/` vrací `nil`.
    public static func fileURL(for relativePath: String) -> URL? {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        return url
    }

    public static func text(_ relativePath: String) -> String {
        guard let url = fileURL(for: relativePath), let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("WebAssets: chybí \(relativePath)")
        }
        return text
    }

    /// JS knihovny, které se do náhledu vkládají líně podle obsahu dokumentu.
    public enum Library: String, CaseIterable, Sendable {
        case highlight = "vendor/highlight.js/highlight.min.js"
        case katex = "vendor/katex/katex.min.js"
        /// Kopírování vyrenderovaného vzorce vloží jeho TeX.
        case katexCopyTex = "vendor/katex/copy-tex.min.js"
        case mermaid = "vendor/mermaid/mermaid.min.js"
    }

    /// Skripty, které běží vždy (v tomto pořadí).
    public static let coreScripts = ["vendor/dompurify/purify.min.js", "app.js"]

    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "svg": "image/svg+xml"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        case "png": "image/png"
        default: "application/octet-stream"
        }
    }
}
