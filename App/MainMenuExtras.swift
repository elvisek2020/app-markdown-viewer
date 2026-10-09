import AppKit

/// Akce vieweru, které posílá hlavní menu do responder chainu
/// (okno → PreviewController → MarkdownDocument).
@objc protocol ViewerActions {
    func reloadDocument(_ sender: Any?)
    func toggleFollowTail(_ sender: Any?)
    func zoomInPreview(_ sender: Any?)
    func zoomOutPreview(_ sender: Any?)
    func actualSizePreview(_ sender: Any?)
    func revealDocumentInFinder(_ sender: Any?)
    func copyDocumentPath(_ sender: Any?)
}

/// Položky menu specifické pro MDView. Standardní menu je v MainMenu.xib.
enum MainMenuExtras {
    static func install() {
        guard let mainMenu = NSApp.mainMenu else { return }

        if let file = submenu(in: mainMenu, containing: #selector(NSDocumentController.openDocument(_:))) {
            let index = (file.items.firstIndex { $0.submenu != nil } ?? 1) + 1
            file.insertItem(.separator(), at: index)
            file.insertItem(item("Zobrazit ve Finderu", #selector(ViewerActions.revealDocumentInFinder(_:)), "r", [.command, .option]), at: index + 1)
            file.insertItem(item("Kopírovat cestu", #selector(ViewerActions.copyDocumentPath(_:)), "c", [.command, .option, .shift]), at: index + 2)
        }

        if let view = submenu(in: mainMenu, containing: #selector(NSWindow.toggleFullScreen(_:))) {
            let items = [
                item("Znovu načíst", #selector(ViewerActions.reloadDocument(_:)), "r", [.command]),
                item("Sledovat konec souboru", #selector(ViewerActions.toggleFollowTail(_:)), "", []),
                .separator(),
                item("Skutečná velikost", #selector(ViewerActions.actualSizePreview(_:)), "0", [.command]),
                item("Zvětšit", #selector(ViewerActions.zoomInPreview(_:)), "+", [.command]),
                item("Zmenšit", #selector(ViewerActions.zoomOutPreview(_:)), "-", [.command]),
                .separator(),
            ]
            for (offset, menuItem) in items.enumerated() {
                view.insertItem(menuItem, at: offset)
            }
        }
    }

    private static func submenu(in menu: NSMenu, containing action: Selector) -> NSMenu? {
        menu.items.compactMap(\.submenu).first { submenu in
            submenu.items.contains { $0.action == action }
        }
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }
}
