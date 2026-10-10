import AppKit
import UniformTypeIdentifiers
import WebKit

/// Export do HTML a PDF a tisk. Tisk i PDF jsou vždy ve světlém tématu a se všemi diagramy.
extension PreviewController {
    private var documentName: String {
        model.url.deletingPathExtension().lastPathComponent
    }

    @objc func exportHTMLDocument(_ sender: Any?) {
        askForDestination(type: .html, extension: "html") { url in
            try await self.exportHTML(to: url)
        }
    }

    @objc func exportPDFDocument(_ sender: Any?) {
        askForDestination(type: .pdf, extension: "pdf") { url in
            try await self.exportPDF(to: url)
        }
    }

    @objc func printDocument(_ sender: Any?) {
        Task { _ = await runPrintOperation(saveTo: nil) }
    }

    /// Samostatný HTML soubor: bez skriptů, styly, fonty KaTeXu i lokální obrázky jsou vložené.
    func exportHTML(to url: URL) async throws {
        guard let json = await callString("return JSON.stringify(await mdv.exportContent())"),
              let data = json.data(using: .utf8),
              let content = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let html = content["html"] else {
            throw CocoaError(.fileWriteUnknown)
        }
        let title = content["title"].flatMap { $0.isEmpty ? nil : $0 } ?? documentName
        try HTMLExporter.document(contentHTML: html, title: title).write(to: url, atomically: true, encoding: .utf8)
    }

    func exportPDF(to url: URL) async throws {
        guard await runPrintOperation(saveTo: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func askForDestination(type: UTType, extension fileExtension: String, export: @escaping (URL) async throws -> Void) {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "\(documentName).\(fileExtension)"
        panel.directoryURL = model.url.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    try await export(url)
                } catch {
                    self.presentError(error)
                }
            }
        }
    }

    /// Tisk nebo uložení do PDF přes `WKWebView.printOperation`. Musí běžet přes `runModal`
    /// (synchronní `run()` dává u WKWebView prázdné stránky) a s nastaveným rámcem view.
    func runPrintOperation(saveTo url: URL?) async -> Bool {
        guard let window = view.window else { return false }
        let originalAppearance = webView.appearance
        webView.appearance = NSAppearance(named: .aqua)
        // Změna vzhledu přerenderuje Mermaid do světlého tématu; počkat na frontu diagramů.
        try? await Task.sleep(for: .milliseconds(300))
        try? await call("await mdv.flushDiagrams(); mdv.preparePrint()")

        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        if let url {
            info.jobDisposition = .save
            info.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
        }

        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.showsPrintPanel = url == nil
        operation.showsProgressPanel = url == nil
        operation.jobTitle = documentName

        let success = await withCheckedContinuation { continuation in
            let completion = PrintCompletion { continuation.resume(returning: $0) }
            operation.runModal(
                for: window,
                delegate: completion,
                didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
        try? await call("mdv.finishPrint()")
        webView.appearance = originalAppearance
        return success
    }
}

/// Cíl callbacku `runModal(for:delegate:didRun:)`; drží se, dokud tisk neskončí.
final class PrintCompletion: NSObject {
    private static var running: Set<PrintCompletion> = []
    private let handler: (Bool) -> Void

    init(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
        super.init()
        Self.running.insert(self)
    }

    /// AppKit volá z vlákna, na kterém tisk běžel – při ukládání do PDF bez panelu je to vlákno na pozadí.
    @objc nonisolated func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handler(success)
                Self.running.remove(self)
            }
        }
    }
}
