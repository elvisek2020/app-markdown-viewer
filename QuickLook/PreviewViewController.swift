import AppKit
import MarkdownCore
import OSLog
import QuickLookUI
import WebAssets
import WebKit

/// Quick Look náhled Markdownu (mezerník ve Finderu) se stejným rendererem a vzhledem jako MDView.
///
/// Oproti aplikaci: žádné síťové požadavky (obrázky z internetu blokuje app.js i pravidlo obsahu),
/// bez Mermaidu (3,5 MB knihovna by zdržela otevření; diagram zůstane jako kód) a bez hlídání souboru.
/// Diagnostika: existuje-li soubor `/tmp/mdview-quicklook-diagnostics`, zapíše rozšíření po každém
/// náhledu report do systémového logu (`log show --predicate 'subsystem == "cz.elvisek.mdview"'`).
/// Kontejner rozšíření je od macOS 14 zvenku nečitelný a zápis mimo něj sandbox nedovolí.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReady = false
    private var loadedLibraries: Set<WebAssets.Library> = []

    /// Pravidlo obsahu, které zablokuje veškeré http(s) požadavky – náhled cizího souboru nesmí nic odeslat.
    private static let blockNetworkRules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#

    override func loadView() {
        let configuration = PreviewSupport.makeConfiguration(messageHandler: QuickLookMessageHandler(self))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsLinkPreview = false
        self.webView = webView
        view = webView
        preferredContentSize = NSSize(width: 900, height: 1000)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let started = Date()
        Task {
            do {
                try await preparePreview(of: url, started: started)
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }

    private func preparePreview(of url: URL, started: Date) async throws {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let document = await Task.detached(priority: .userInitiated) {
            MarkdownRenderer.render(text)
        }.value

        _ = view
        if let rules = await Self.compiledRules() {
            webView.configuration.userContentController.add(rules)
        }
        webView.load(URLRequest(url: AssetSchemeHandler.templateURL))
        await waitUntilReady()

        loadedLibraries = await PreviewSupport.loadLibraries(
            for: document.features, into: webView, alreadyLoaded: loadedLibraries, includeMermaid: false
        )
        let payload: [String: Any] = [
            "html": document.html,
            "baseURL": PreviewSupport.baseURL(for: url),
            "remoteImages": false,
            "restoreLine": 0,
        ]
        _ = try await webView.callAsyncJavaScript(
            "return await mdv.update(payload)",
            arguments: ["payload": payload],
            in: nil,
            contentWorld: PreviewSupport.world
        )
        await writeDiagnostics(for: url, started: started, bytes: data.count)
    }

    private static func compiledRules() async -> WKContentRuleList? {
        try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "mdview-quicklook-block-network",
            encodedContentRuleList: blockNetworkRules
        )
    }

    // MARK: - Připravenost šablony

    private func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        guard body["type"] as? String == "ready" else { return }
        isReady = true
        readyWaiters.forEach { $0.resume() }
        readyWaiters.removeAll()
    }

    // MARK: - Navigace: jen šablona, odkazy se v náhledu neotevírají

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isTemplate = navigationAction.request.url == AssetSchemeHandler.templateURL
            && navigationAction.targetFrame?.isMainFrame == true
        decisionHandler(isTemplate ? .allow : .cancel)
    }

    // MARK: - Diagnostika

    private static let logger = Logger(subsystem: "cz.elvisek.mdview", category: "quicklook")
    private static let diagnosticsFlag = "/tmp/mdview-quicklook-diagnostics"

    private func writeDiagnostics(for url: URL, started: Date, bytes: Int) async {
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Self.logger.info("Náhled \(bytes, privacy: .public) B za \(elapsed, privacy: .public) ms")
        guard FileManager.default.fileExists(atPath: Self.diagnosticsFlag) else { return }
        let probe = """
        const content = document.getElementById("mdv-content");
        const trap = document.createElement("img");
        trap.setAttribute("onerror", "document.body.dataset.pwned = '1'");
        trap.src = "mdv-asset://app/neexistuje.png";
        content.append(trap);
        await new Promise((resolve) => setTimeout(resolve, 300));
        trap.remove();
        return JSON.stringify({
          blocks: content.children.length,
          katex: content.querySelectorAll(".katex").length,
          hljs: content.querySelectorAll("code.hljs").length,
          alerts: content.querySelectorAll(".markdown-alert-title svg").length,
          mermaidAsCode: content.querySelectorAll("pre > code.language-mermaid").length,
          images: content.querySelectorAll("img").length,
          imagesLoaded: [...content.querySelectorAll("img")].filter((img) => img.complete && img.naturalWidth > 0).length,
          blockedRemote: content.querySelectorAll(".mdv-blocked-image").length,
          pwned: document.body.dataset.pwned === "1",
          dark: matchMedia("(prefers-color-scheme: dark)").matches,
        });
        """
        // Krátký report – systémový log delší zprávy ořízne.
        var report: [String: Any] = ["file": url.lastPathComponent, "bytes": bytes, "renderMs": elapsed]
        if let json = try? await webView.callAsyncJavaScript(probe, arguments: [:], in: nil, contentWorld: PreviewSupport.world) as? String,
           let data = json.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) {
            report["probe"] = result
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            Self.logger.notice("MDVIEW-QL-REPORT \(json, privacy: .public)")
        }
    }
}

/// WKUserContentController drží handler silně – proxy přeruší cyklus.
private final class QuickLookMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PreviewViewController?

    init(_ target: PreviewViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        target?.handleMessage(body)
    }
}
