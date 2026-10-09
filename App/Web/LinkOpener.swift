import AppKit
import MarkdownCore

/// Provede rozhodnutí `LinkPolicy`. Nikdy nespouští soubory – lokální ne-Markdown jen ukáže ve Finderu.
enum LinkOpener {
    static func open(_ url: URL, from window: NSWindow?) {
        switch LinkPolicy.action(for: url) {
        case .openMarkdown(let fileURL):
            NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        case .openExternal(let externalURL):
            NSWorkspace.shared.open(externalURL)
        case .revealInFinder(let fileURL):
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        case .confirmExternal(let externalURL):
            confirm(externalURL, window: window)
        case .ignore:
            NSSound.beep()
        }
    }

    private static func confirm(_ url: URL, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Otevřít odkaz v jiné aplikaci?"
        alert.informativeText = url.absoluteString
        alert.addButton(withTitle: "Otevřít")
        alert.addButton(withTitle: "Zrušit")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
}
