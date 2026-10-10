import AppKit
import SwiftUI

/// Okno dokumentu: osnova (SwiftUI) | náhled se zdrojem, nástrojová lišta s osnovou, zdrojem a hledáním.
final class DocumentWindowController: NSWindowController, NSToolbarDelegate {
    let preview: PreviewController
    private let outline = OutlineState()
    private let split = NSSplitViewController()
    private var sourceButton: NSButton?
    private var editButton: NSButton?
    private var frameMemory: WindowFrameMemory?

    init(model: DocumentModel) {
        preview = PreviewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MDViewDocument"
        window.minSize = NSSize(width: 480, height: 300)
        window.toolbarStyle = .unified
        super.init(window: window)

        let outlineHost = NSHostingController(rootView: OutlineSidebar(state: outline))
        // Velikost okna neřídí obsah osnovy – jinak by okno bez uloženého rámu sjelo na výšku seznamu.
        outlineHost.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: outlineHost)
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 420
        sidebar.canCollapse = true
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: preview))
        if !Self.isSelfTest { split.splitView.autosaveName = "MDViewDocumentSplit" }
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 1000))

        let toolbar = NSToolbar(identifier: "MDViewDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        shouldCascadeWindows = false
        if let name = ToolbarItems.frameName("Document") {
            frameMemory = WindowFrameMemory(window: window, name: name)
        }

        outline.onSelect = { [weak preview] item in preview?.scroll(toLine: item.line) }
        preview.onTopLineChange = { [weak outline] line in outline?.currentLine = line }
        preview.onSourceVisibilityChange = { [weak self] visible in self?.sourceButton?.state = visible ? .on : .off }
        preview.onEditModeChange = { [weak self] editing in
            self?.editButton?.state = editing ? .on : .off
            self?.sourceButton?.isEnabled = !editing
        }
        model.observeRender { [weak outline] document in outline?.items = document.outline }
        model.observeMove { [weak self] url in self?.updateSubtitle(url) }
        updateSubtitle(model.url)
    }

    private static var isSelfTest: Bool {
        #if DEBUG
        SelfTest.isActive
        #else
        false
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    /// Podtitulek okna = složka dokumentu (~/…).
    private func updateSubtitle(_ url: URL) {
        window?.subtitle = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, ToolbarItems.appearance, ToolbarItems.edit, ToolbarItems.source, ToolbarItems.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItems.source:
            let (item, button) = ToolbarItems.sourceToggle(isOn: preview.isSourceVisible)
            sourceButton = button
            return item
        case ToolbarItems.edit:
            let (item, button) = ToolbarItems.editToggle(isOn: preview.isEditing)
            editButton = button
            return item
        case ToolbarItems.search:
            let item = ToolbarItems.searchItem()
            ToolbarItems.connect(item, to: preview)
            return item
        case ToolbarItems.appearance:
            return AppearanceController.shared.makeToolbarItem(itemIdentifier)
        default:
            return nil
        }
    }
}
