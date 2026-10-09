import AppKit

final class DocumentWindowController: NSWindowController {
    let preview: PreviewController

    init(model: DocumentModel) {
        preview = PreviewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MDViewDocument"
        window.minSize = NSSize(width: 360, height: 240)
        window.contentViewController = preview
        window.setContentSize(NSSize(width: 920, height: 1000))
        super.init(window: window)
        shouldCascadeWindows = true
        windowFrameAutosaveName = "MDViewDocument"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }
}
