import AppKit
import MarkdownCore
import WebAssets
import WebKit

/// Náhled ve WKWebView. JavaScript dokumentu je vypnutý (`allowsContentJavaScript = false`);
/// app.js a knihovny běží jako user scripty v izolovaném content worldu „mdview“.
/// Šablona se načte jednou, další rendery se do ní posílají přes `mdv.update` bez reloadu.
/// Hledání je v `PreviewController+Find.swift`, export a tisk v `PreviewController+Export.swift`.
final class PreviewController: NSViewController, ViewerActions, NSMenuItemValidation {
    static let world = PreviewSupport.world

    let model: DocumentModel
    private(set) var webView: PreviewWebView!
    private var isReady = false
    private var isUpdating = false
    private var hasContent = false
    private var pending: RenderedDocument?
    private var loadedLibraries: Set<WebAssets.Library> = []
    private var restoreLine: Int?
    private var lastRemoteImages = Preferences.remoteImages
    /// Další render vyvolala změna nastavení nebo zdrojového panelu, ne zápis souboru – bez zvýraznění.
    private var suppressHighlightOnce = false

    /// Zdrojový panel vedle náhledu (stav okna).
    private(set) var isSourceVisible = Preferences.showSourceByDefault

    /// První viditelný řádek zdroje (hlásí app.js při scrollu) – ukládá se pro obnovu okna.
    private(set) var topLine = 1

    /// Volá se při změně `topLine` (zvýraznění v osnově) a viditelnosti zdroje (tlačítko v liště).
    var onTopLineChange: ((Int) -> Void)?
    var onSourceVisibilityChange: ((Bool) -> Void)?

    /// Vyhledávací pole v nástrojové liště okna (nastavuje DocumentWindowController).
    weak var searchField: NSSearchField?
    var searchItem: NSSearchToolbarItem?

    init(model: DocumentModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    override func loadView() {
        let configuration = PreviewSupport.makeConfiguration(messageHandler: WeakMessageHandler(self))
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 920, height: 1000), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.pageZoom = Preferences.zoom(for: model.url)
        #if DEBUG
        webView.isInspectable = true
        #endif
        self.webView = webView
        view = webView

        model.options = Preferences.renderOptions(includeSource: isSourceVisible)
        model.observeRender { [weak self] document in self?.show(document) }
        model.observeFileState { [weak self] _ in self?.sendStatus() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
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

    /// Skok na řádek zdroje (osnova).
    func scroll(toLine line: Int) {
        Task { try? await call("mdv.scrollToLine(line)", ["line": line]) }
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
            loadedLibraries = await PreviewSupport.loadLibraries(for: document.features, into: webView, alreadyLoaded: loadedLibraries)
            var payload: [String: Any] = [
                "html": document.html,
                "baseURL": PreviewSupport.baseURL(for: model.url),
                "restoreLine": hasContent ? 0 : (restoreLine ?? 0),
                "remoteImages": Preferences.remoteImages,
                "highlightChanges": Preferences.highlightChanges && !suppressHighlightOnce,
            ]
            suppressHighlightOnce = false
            if isSourceVisible, let source = document.sourceHTML {
                payload["sourceHTML"] = source
            }
            do {
                try await call("return await mdv.update(payload)", ["payload": payload])
                hasContent = true
                restoreLine = nil
                #if DEBUG
                SelfTest.didUpdate(preview: self, fileURL: model.url)
                SelfTest.recordStatus(webView: webView, world: Self.world)
                #endif
            } catch {
                NSLog("MDView: mdv.update selhal: \(error)")
            }
            isUpdating = false
            flush()
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

    private func sendSourceState() {
        guard isReady else { return }
        let options: [String: Any] = ["visible": isSourceVisible, "width": Preferences.sourceWidth]
        Task { try? await call("mdv.setSource(options)", ["options": options]) }
    }

    /// Výsledek JS se zahazuje – `Any` není Sendable a nikde ho nepotřebujeme.
    func call(_ body: String, _ arguments: [String: Any] = [:]) async throws {
        _ = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.world)
    }

    /// Volání JS, které vrací řetězec (JSON nebo text).
    func callString(_ body: String, _ arguments: [String: Any] = [:]) async -> String? {
        try? await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.world) as? String
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            isReady = true
            hasContent = false
            if pending == nil { pending = model.rendered }
            Task { try? await call("mdv.setFollowTail(value)", ["value": Preferences.followTail]) }
            sendSourceState()
            sendStatus()
            flush()
        case "link":
            if let href = body["href"] as? String, let url = URL(string: href) {
                LinkOpener.open(url, from: view.window)
            }
        case "scroll":
            if let line = body["line"] as? Int, line != topLine {
                topLine = line
                onTopLineChange?(line)
                view.window?.windowController?.document?.invalidateRestorableState()
            }
        case "sourceWidth":
            if let width = body["value"] as? Double {
                UserDefaults.standard.set(width, forKey: Preferences.Key.sourceWidth)
            }
        case "error":
            NSLog("MDView JS: \(body["message"] ?? "")")
        default:
            break
        }
    }

    private func preferencesChanged() {
        let options = Preferences.renderOptions(includeSource: isSourceVisible)
        if options != model.options {
            suppressHighlightOnce = true
            model.options = options
        }
        if Preferences.remoteImages != lastRemoteImages {
            lastRemoteImages = Preferences.remoteImages
            suppressHighlightOnce = true
            if let rendered = model.rendered { show(rendered) }
        }
        guard isReady else { return }
        Task { try? await call("mdv.setFollowTail(value)", ["value": Preferences.followTail]) }
    }

    // MARK: - Zdrojový panel

    func setSourceVisible(_ visible: Bool) {
        guard visible != isSourceVisible else { return }
        isSourceVisible = visible
        // Zdroj se renderuje jen se zapnutým panelem – změna voleb spustí nový render.
        suppressHighlightOnce = true
        model.options = Preferences.renderOptions(includeSource: visible)
        sendSourceState()
        onSourceVisibilityChange?(visible)
    }

    // MARK: - ViewerActions

    @objc func reloadDocument(_ sender: Any?) {
        model.reload()
    }

    @objc func jumpToLastChange(_ sender: Any?) {
        Task {
            if await callString("return String(mdv.jumpToLastChange())") != "true" { NSSound.beep() }
        }
    }

    @objc func toggleSourcePane(_ sender: Any?) {
        setSourceVisible(!isSourceVisible)
    }

    @objc func toggleFollowTail(_ sender: Any?) {
        UserDefaults.standard.set(!Preferences.followTail, forKey: Preferences.Key.followTail)
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
        Preferences.setZoom(clamped, for: model.url)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFollowTail(_:)):
            menuItem.state = Preferences.followTail ? .on : .off
        case #selector(toggleSourcePane(_:)):
            menuItem.state = isSourceVisible ? .on : .off
        default:
            break
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
