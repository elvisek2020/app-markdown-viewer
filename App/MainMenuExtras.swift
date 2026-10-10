import AppKit

/// Akce vieweru, které posílá hlavní menu a nástrojová lišta do responder chainu
/// (náhled → PreviewController → okno → MarkdownDocument → AppDelegate).
@objc protocol ViewerActions {
    func reloadDocument(_ sender: Any?)
    func toggleSourcePane(_ sender: Any?)
    func toggleFollowTail(_ sender: Any?)
    func zoomInPreview(_ sender: Any?)
    func zoomOutPreview(_ sender: Any?)
    func actualSizePreview(_ sender: Any?)
    func revealDocumentInFinder(_ sender: Any?)
    func copyDocumentPath(_ sender: Any?)
    func findInDocument(_ sender: Any?)
    func findNextMatch(_ sender: Any?)
    func findPreviousMatch(_ sender: Any?)
    func useSelectionForFind(_ sender: Any?)
    func exportHTMLDocument(_ sender: Any?)
    func exportPDFDocument(_ sender: Any?)
    func jumpToLastChange(_ sender: Any?)
}

/// Položky menu specifické pro MDView. Standardní menu je v MainMenu.xib.
enum MainMenuExtras {
    static func install() {
        guard let mainMenu = NSApp.mainMenu else { return }

        if let appMenu = mainMenu.items.first?.submenu {
            // O aplikaci MDView: vlastní panel s autorem (standardní akce by ukázala jen copyright).
            appMenu.items.first { $0.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) }?
                .action = #selector(AppDelegate.showAbout(_:))
            let settings = item("Nastavení…", #selector(AppDelegate.showSettings(_:)), ",", [.command])
            appMenu.insertItem(.separator(), at: 1)
            appMenu.insertItem(settings, at: 2)
        }

        if let file = submenu(in: mainMenu, containing: #selector(NSDocumentController.openDocument(_:))) {
            let index = (file.items.firstIndex { $0.submenu != nil } ?? 1) + 1
            let items: [NSMenuItem] = [
                .separator(),
                item("Zobrazit ve Finderu", #selector(ViewerActions.revealDocumentInFinder(_:)), "r", [.command, .option]),
                item("Kopírovat cestu", #selector(ViewerActions.copyDocumentPath(_:)), "c", [.command, .option, .shift]),
                .separator(),
                item("Exportovat jako HTML…", #selector(ViewerActions.exportHTMLDocument(_:)), "e", [.command, .shift]),
                item("Exportovat jako PDF…", #selector(ViewerActions.exportPDFDocument(_:)), "e", [.command, .option, .shift]),
            ]
            for (offset, menuItem) in items.enumerated() {
                file.insertItem(menuItem, at: index + offset)
            }
        }

        if let view = submenu(in: mainMenu, containing: #selector(NSWindow.toggleFullScreen(_:))) {
            let items: [NSMenuItem] = [
                item("Zobrazit osnovu", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
                item("Zobrazit zdroj", #selector(ViewerActions.toggleSourcePane(_:)), "u", [.command, .option]),
                item("Sledovat změny ve složce", #selector(WorkspaceWindowController.toggleFollowFolderChanges(_:)), "l", [.command, .shift]),
                .separator(),
                item("Znovu načíst", #selector(ViewerActions.reloadDocument(_:)), "r", [.command]),
                item("Přejít na poslední změnu", #selector(ViewerActions.jumpToLastChange(_:)), "j", [.command]),
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
            let appearance = NSMenuItem(title: "Vzhled", action: nil, keyEquivalent: "")
            appearance.submenu = AppearanceController.shared.makeMenu()
            view.insertItem(appearance, at: items.count)
            view.insertItem(.separator(), at: items.count + 1)
        }

        // Úpravy → Hledat: standardní performFindPanelAction: by zachytil WKWebView; vlastní akce
        // vedou na hledání v nástrojové liště.
        let findActions: [Int: Selector] = [
            1: #selector(ViewerActions.findInDocument(_:)),
            2: #selector(ViewerActions.findNextMatch(_:)),
            3: #selector(ViewerActions.findPreviousMatch(_:)),
            7: #selector(ViewerActions.useSelectionForFind(_:)),
        ]
        for menuItem in allItems(in: mainMenu) where menuItem.action == #selector(NSResponder.performTextFinderAction(_:))
            || menuItem.action == #selector(NSTextView.performFindPanelAction(_:)) {
            if let action = findActions[menuItem.tag] { menuItem.action = action }
        }
    }

    private static func submenu(in menu: NSMenu, containing action: Selector) -> NSMenu? {
        menu.items.compactMap(\.submenu).first { submenu in
            submenu.items.contains { $0.action == action }
        }
    }

    private static func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }
}
