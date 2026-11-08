import AppKit
import MarkdownCore

/// Otevření souborů přetažených z Finderu do okna: Markdown, prosté texty a složky (pracovní složka).
/// Náhled i editor jsou cíle tažení samy o sobě (WKWebView by soubor načetl, editor vložil jeho cestu),
/// proto soubory zachytávají dřív; `nil` znamená, že nejde o soubory a tažení patří jim.
enum FileDrop {
    private static func fileURLs(in info: any NSDraggingInfo) -> [URL]? {
        // Tažení uvnitř aplikace (obrázek nebo text z náhledu) nejsou soubory z Finderu.
        guard info.draggingSource == nil else { return nil }
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        guard let urls = objects as? [URL], !urls.isEmpty else { return nil }
        return urls
    }

    private static func isOpenable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        if values.isDirectory == true { return values.isPackage != true }
        let name = url.pathExtension.lowercased()
        return LinkPolicy.markdownExtensions.contains(name) || PlainText.extensions.contains(name)
    }

    static func isFileDrag(_ info: any NSDraggingInfo) -> Bool {
        fileURLs(in: info) != nil
    }

    /// `.copy`, když je co otevřít; prázdná operace u nepodporovaných souborů (zákaz).
    static func operation(for info: any NSDraggingInfo) -> NSDragOperation? {
        fileURLs(in: info).map { $0.contains(where: isOpenable) ? .copy : [] }
    }

    @discardableResult
    static func perform(_ info: any NSDraggingInfo) -> Bool? {
        guard let urls = fileURLs(in: info) else { return nil }
        let openable = urls.filter(isOpenable)
        guard !openable.isEmpty else { return false }
        #if DEBUG
        if !SelfTest.isActive { NSApp.activate() }
        #else
        NSApp.activate()
        #endif
        for url in openable {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        return true
    }
}

/// Okno, do kterého jde přetáhnout soubor kamkoli (lišta, osnova, strom složky).
final class FileDropWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        registerForDraggedTypes([.fileURL])
    }

    @objc func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        FileDrop.operation(for: sender) ?? []
    }

    @objc func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        FileDrop.operation(for: sender) ?? []
    }

    @objc func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        FileDrop.perform(sender) ?? false
    }
}
