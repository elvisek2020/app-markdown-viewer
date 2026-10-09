import Foundation
import UniformTypeIdentifiers
import WebAssets
import WebKit

/// `mdv-asset://app/…` – šablona, CSS, fonty a ikony z bundlu.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdv-asset"
    static let templateURL = URL(string: "mdv-asset://app/template.html")!

    /// JS z dokumentu neběží už díky allowsContentJavaScript = false; CSP je druhá pojistka
    /// a zároveň omezuje, odkud se smí načítat obrázky, fonty a styly.
    private static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'none'",
        "style-src mdv-asset: 'unsafe-inline'",
        "font-src mdv-asset:",
        "img-src mdv-asset: mdv-file: https: data:",
        "media-src mdv-file: https:",
        "base-uri 'none'",
        "form-action 'none'",
    ].joined(separator: "; ")

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "app",
              let fileURL = WebAssets.fileURL(for: String(url.path.dropFirst())),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        var headers = [
            "Content-Type": WebAssets.mimeType(for: fileURL),
            "Content-Length": String(data.count),
        ]
        if url == Self.templateURL {
            headers["Content-Security-Policy"] = Self.contentSecurityPolicy
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// `mdv-file:///abs/cesta` – lokální obrázky a média dokumentu. Jiné typy souborů nevydá.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let allowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "heif", "bmp", "ico", "tif", "tiff",
        "mp4", "m4v", "mov", "webm", "mp3", "m4a", "wav", "ogg",
    ]

    private var tasks: [ObjectIdentifier: any WKURLSchemeTask] = [:]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, Self.allowedExtensions.contains(url.pathExtension.lowercased()) else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let id = ObjectIdentifier(task)
        tasks[id] = task
        let path = url.path
        // Čtení mimo hlavní vlákno – soubor může ležet na síťovém svazku.
        Task.detached(priority: .userInitiated) {
            let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            await MainActor.run {
                self.finish(id: id, url: url, data: data)
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        tasks[ObjectIdentifier(task)] = nil
    }

    private func finish(id: ObjectIdentifier, url: URL, data: Data?) {
        // Úloha mohla být mezitím zastavena – volat ji pak nesmíme.
        guard let task = tasks.removeValue(forKey: id) else { return }
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-store"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }
}
