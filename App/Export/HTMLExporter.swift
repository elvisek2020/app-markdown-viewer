import Foundation
import MarkdownCore
import UniformTypeIdentifiers
import WebAssets

/// Samostatný HTML soubor z vyrenderovaného náhledu: bez JavaScriptu, styly GitHubu pro světlý
/// i tmavý vzhled, fonty KaTeXu a lokální obrázky jako data URI, takže funguje offline kdekoli.
enum HTMLExporter {
    /// Větší lokální obrázky se nevkládají (soubor by byl obří); zůstane odkaz na původní soubor.
    private static let maximumInlineImageSize = 20 * 1024 * 1024

    static func document(contentHTML: String, title: String) -> String {
        let body = inlineLocalFiles(contentHTML)
        let usesMath = body.contains("class=\"katex")
        return """
        <!doctype html>
        <html lang="cs">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta name="generator" content="MDView">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet(includeMath: usesMath))
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>

        """
    }

    // MARK: - Styly

    static func stylesheet(includeMath: Bool) -> String {
        var parts = [
            WebAssets.text("vendor/github-markdown-css/github-markdown.css"),
            "@media (prefers-color-scheme: light) {\n\(WebAssets.text("vendor/highlight.js/github.min.css"))\n}",
            "@media (prefers-color-scheme: dark) {\n\(WebAssets.text("vendor/highlight.js/github-dark.min.css"))\n}",
        ]
        if includeMath {
            parts.append(katexStylesheet())
        }
        parts.append(appStylesheet())
        parts.append("""
        body { margin: 0; }
        .markdown-body { box-sizing: border-box; max-width: 980px; margin: 0 auto; padding: 32px 48px 64px; }
        @media (max-width: 767px) { .markdown-body { padding: 16px; } }
        """)
        return parts.joined(separator: "\n")
    }

    /// KaTeX s fonty jako data URI (jen woff2 – podporují ho všechny současné prohlížeče).
    private static func katexStylesheet() -> String {
        var css = WebAssets.text("vendor/katex/katex.min.css")
        css = css.replacingOccurrences(
            of: #",url\(fonts/[^)]+\.woff\) format\("woff"\),url\(fonts/[^)]+\.ttf\) format\("truetype"\)"#,
            with: "",
            options: .regularExpression
        )
        let regex = try! NSRegularExpression(pattern: #"url\(fonts/([^)]+\.woff2)\)"#)
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).reversed() {
            guard let range = Range(match.range, in: css), let nameRange = Range(match.range(at: 1), in: css),
                  let url = WebAssets.fileURL(for: "vendor/katex/fonts/\(css[nameRange])"),
                  let data = try? Data(contentsOf: url) else { continue }
            css.replaceSubrange(range, with: "url(data:font/woff2;base64,\(data.base64EncodedString()))")
        }
        return css
    }

    private static func appStylesheet() -> String {
        WebAssets.text("app.css")
    }

    // MARK: - Lokální soubory

    /// `src="mdv-file://…"` → data URI, `href="mdv-file://…"` → `file://` (odkazy mimo náhled).
    static func inlineLocalFiles(_ html: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"(src|href|poster)="(mdv-file://[^"]+)""#)
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: result),
                  let attributeRange = Range(match.range(at: 1), in: result),
                  let valueRange = Range(match.range(at: 2), in: result),
                  let previewURL = URL(string: String(result[valueRange])) else { continue }
            let attribute = String(result[attributeRange])
            let fileURL = URL(fileURLWithPath: previewURL.path)
            let replacement: String
            if attribute != "href",
               let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumInlineImageSize,
               let data = try? Data(contentsOf: fileURL) {
                let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                replacement = "\(attribute)=\"data:\(mime);base64,\(data.base64EncodedString())\""
            } else {
                replacement = "\(attribute)=\"\(fileURL.absoluteString)\""
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
