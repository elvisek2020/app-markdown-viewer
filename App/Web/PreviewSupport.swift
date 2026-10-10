import Foundation
import MarkdownCore
import WebAssets
import WebKit

/// Společný základ náhledu pro aplikaci i Quick Look rozšíření: konfigurace WKWebView
/// (vypnutý JS dokumentu, izolovaný content world, scheme handlery), načítání knihoven a payload.
enum PreviewSupport {
    static let world = WKContentWorld.world(name: "mdview")

    static func makeConfiguration(messageHandler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // Tisk a PDF i s pozadím (bloky kódu, záhlaví tabulek).
        configuration.preferences.shouldPrintBackgrounds = true
        configuration.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: AssetSchemeHandler.scheme)
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LinkPolicy.fileScheme)

        let userContent = configuration.userContentController
        userContent.add(messageHandler, contentWorld: world, name: "mdv")
        for path in WebAssets.coreScripts {
            userContent.addUserScript(WKUserScript(
                source: WebAssets.text(path),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: world
            ))
        }
        return configuration
    }

    /// Knihovny podle obsahu dokumentu; vkládají se jen jednou na stránku.
    /// Vrací množinu načtených knihoven včetně dříve načtených (`alreadyLoaded`).
    static func loadLibraries(
        for features: DocumentFeatures,
        into webView: WKWebView,
        alreadyLoaded: Set<WebAssets.Library>,
        includeMermaid: Bool = true
    ) async -> Set<WebAssets.Library> {
        var loaded = alreadyLoaded
        var needed: [WebAssets.Library] = []
        if features.contains(.code) { needed.append(.highlight) }
        if features.contains(.math) { needed += [.katex, .katexCopyTex] }
        if includeMermaid, features.contains(.mermaid) { needed.append(.mermaid) }
        for library in needed where !loaded.contains(library) {
            // evaluateJavaScript (ne callAsyncJavaScript): top-level `var` musí skončit v globálním objektu worldu.
            let source = WebAssets.text(library.rawValue) + "\n;true"
            let success: Bool = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(source, in: nil, in: world) { result in
                    if case .failure(let error) = result {
                        NSLog("MDView: knihovna \(library.rawValue) se nenačetla: \(error)")
                    }
                    continuation.resume(returning: (try? result.get()) != nil)
                }
            }
            if success { loaded.insert(library) }
        }
        return loaded
    }

    /// `mdv-file://` adresář dokumentu – základ pro relativní obrázky a odkazy.
    static func baseURL(for fileURL: URL) -> String {
        var base = LinkPolicy.previewURL(forFile: fileURL.deletingLastPathComponent()).absoluteString
        if !base.hasSuffix("/") { base += "/" }
        return base
    }
}
