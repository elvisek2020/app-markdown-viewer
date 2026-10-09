import AppKit
import MarkdownCore
import WebAssets
import WebKit

/// Náhled ve WKWebView. JavaScript dokumentu je vypnutý (`allowsContentJavaScript = false`);
/// app.js a knihovny běží jako user scripty v izolovaném content worldu „mdview“.
/// Šablona se načte jednou, další rendery se do ní posílají přes `mdv.update` bez reloadu.
final class PreviewController: NSViewController, ViewerActions, NSMenuItemValidation {
    static let world = WKContentWorld.world(name: "mdview")

    private let model: DocumentModel
    private var webView: PreviewWebView!
    private var isReady = false
    private var isUpdating = false
    private var hasContent = false
    private var pending: RenderedDocument?
    private var loadedLibraries: Set<WebAssets.Library> = []
    private var restoreLine: Int?

    /// První viditelný řádek zdroje (hlásí app.js při scrollu) – ukládá se pro obnovu okna.
    private(set) var topLine = 1

    init(model: DocumentModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: AssetSchemeHandler.scheme)
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LinkPolicy.fileScheme)

        let userContent = configuration.userContentController
        userContent.add(WeakMessageHandler(self), contentWorld: Self.world, name: "mdv")
        for path in WebAssets.coreScripts {
            userContent.addUserScript(WKUserScript(
                source: WebAssets.text(path),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: Self.world
            ))
        }

        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 920, height: 1000), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.pageZoom = UserDefaults.standard.double(forKey: PreferenceKey.pageZoom)
        #if DEBUG
        webView.isInspectable = true
        #endif
        self.webView = webView
        view = webView

        model.onRender = { [weak self] document in self?.show(document) }
        model.onFileState = { [weak self] _ in self?.sendStatus() }
        loadTemplate()
    }

    /// Obnova pozice po relaunchi (z `MarkdownDocument.restoreState`).
    func restore(line: Int) {
        if hasContent {
            Task { try? await call("mdv.scrollToLine(line)", ["line": line]) }
        } else {
            restoreLine = line
        }
    }

    // MARK: - Přenos obsahu do webu

    private func loadTemplate() {
        isReady = false
        loadedLibraries = []
        webView.load(URLRequest(url: AssetSchemeHandler.templateURL))
    }

    private func show(_ document: RenderedDocument) {
        pending = document
        flush()
    }

    /// Posílá vždy jen nejnovější render; během běžící aktualizace se další jen uloží.
    private func flush() {
        guard isReady, !isUpdating, let document = pending else { return }
        pending = nil
        isUpdating = true
        Task {
            await loadLibraries(for: document.features)
            let directory = model.url.deletingLastPathComponent()
            var baseURL = LinkPolicy.previewURL(forFile: directory).absoluteString
            if !baseURL.hasSuffix("/") { baseURL += "/" }
            let payload: [String: Any] = [
                "html": document.html,
                "baseURL": baseURL,
                "restoreLine": hasContent ? 0 : (restoreLine ?? 0),
            ]
            do {
                try await call("return await mdv.update(payload)", ["payload": payload])
                hasContent = true
                restoreLine = nil
                #if DEBUG
                SelfTest.didUpdate(webView: webView, fileURL: model.url, world: Self.world)
                SelfTest.recordStatus(webView: webView, world: Self.world)
                #endif
            } catch {
                NSLog("MDView: mdv.update selhal: \(error)")
            }
            isUpdating = false
            flush()
        }
    }

    /// Velké knihovny se vkládají až podle obsahu dokumentu (Mermaid má 3,5 MB).
    private func loadLibraries(for features: DocumentFeatures) async {
        var needed: [WebAssets.Library] = []
        if features.contains(.code) { needed.append(.highlight) }
        if features.contains(.math) { needed.append(.katex) }
        if features.contains(.mermaid) { needed.append(.mermaid) }
        for library in needed where !loadedLibraries.contains(library) {
            // evaluateJavaScript (ne callAsyncJavaScript): top-level `var` musí skončit v globálním objektu worldu.
            let source = WebAssets.text(library.rawValue) + "\n;true"
            let loaded: Bool = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(source, in: nil, in: Self.world) { result in
                    if case .failure(let error) = result {
                        NSLog("MDView: knihovna \(library.rawValue) se nenačetla: \(error)")
                        #if DEBUG
                        SelfTest.report["libraryError.\(library)"] = "\(error)"
                        #endif
                    }
                    continuation.resume(returning: (try? result.get()) != nil)
                }
            }
            if loaded { loadedLibraries.insert(library) }
        }
    }

    private func sendStatus() {
        guard isReady else { return }
        let message = model.fileState == .deleted
            ? "Soubor byl smazán nebo přesunut. Zobrazuji poslední verzi a čekám, až se znovu objeví."
            : ""
        Task {
            try? await call("mdv.setStatus({ message })", ["message": message])
            #if DEBUG
            SelfTest.recordStatus(webView: webView, world: Self.world)
            #endif
        }
    }

    /// Výsledek JS se zahazuje – `Any` není Sendable a nikde ho nepotřebujeme.
    private func call(_ body: String, _ arguments: [String: Any]) async throws {
        _ = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.world)
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            isReady = true
            hasContent = false
            if pending == nil { pending = model.rendered }
            Task { try? await call("mdv.setFollowTail(value)", ["value": UserDefaults.standard.bool(forKey: PreferenceKey.followTail)]) }
            sendStatus()
            flush()
        case "link":
            if let href = body["href"] as? String, let url = URL(string: href) {
                LinkOpener.open(url, from: view.window)
            }
        case "scroll":
            if let line = body["line"] as? Int, line != topLine {
                topLine = line
                view.window?.windowController?.document?.invalidateRestorableState()
            }
        case "error":
            NSLog("MDView JS: \(body["message"] ?? "")")
        default:
            break
        }
    }

    // MARK: - ViewerActions

    @objc func reloadDocument(_ sender: Any?) {
        model.reload()
    }

    @objc func toggleFollowTail(_ sender: Any?) {
        let value = !UserDefaults.standard.bool(forKey: PreferenceKey.followTail)
        UserDefaults.standard.set(value, forKey: PreferenceKey.followTail)
        Task { try? await call("mdv.setFollowTail(value)", ["value": value]) }
    }

    @objc func zoomInPreview(_ sender: Any?) { setZoom(webView.pageZoom + 0.1) }
    @objc func zoomOutPreview(_ sender: Any?) { setZoom(webView.pageZoom - 0.1) }
    @objc func actualSizePreview(_ sender: Any?) { setZoom(1) }

    @objc func revealDocumentInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([model.url])
    }

    @objc func copyDocumentPath(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.url.path, forType: .string)
    }

    private func setZoom(_ zoom: Double) {
        let clamped = min(3, max(0.5, (zoom * 10).rounded() / 10))
        webView.pageZoom = clamped
        UserDefaults.standard.set(clamped, forKey: PreferenceKey.pageZoom)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFollowTail(_:)) {
            menuItem.state = UserDefaults.standard.bool(forKey: PreferenceKey.followTail) ? .on : .off
        }
        return true
    }
}

// MARK: - Navigace: povolená je jen šablona, vše ostatní jde přes LinkPolicy

extension PreviewController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url == AssetSchemeHandler.templateURL, navigationAction.targetFrame?.isMainFrame == true {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // Klik na odkaz běžně zachytí app.js; sem dojde např. přetažení souboru do okna.
        LinkOpener.open(url, from: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("MDView: WebContent proces skončil, načítám šablonu znovu")
        isUpdating = false
        pending = model.rendered
        loadTemplate()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            LinkOpener.open(url, from: webView.window)
        }
        return nil
    }
}

/// WKUserContentController drží handler silně – proxy přeruší cyklus.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PreviewController?

    init(_ target: PreviewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        target?.handleMessage(body)
    }
}

/// WKWebView bez položek kontextového menu, které by otevíraly nová okna nebo stahovaly.
final class PreviewWebView: WKWebView {
    private static let removedItems: Set<String> = [
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierDownloadMedia",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        "WKMenuItemIdentifierReload",
        "WKMenuItemIdentifierGoBack",
        "WKMenuItemIdentifierGoForward",
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items.removeAll { item in
            item.identifier.map { Self.removedItems.contains($0.rawValue) } ?? false
        }
        super.willOpenMenu(menu, with: event)
    }
}
