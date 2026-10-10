import AppKit

/// Přepínač vzhledu (podle systému / světlý / tmavý) pro nástrojovou lištu a menu Zobrazení.
/// Hodnota se ukládá do předvoleb, takže platí i pro okno Nastavení.
@MainActor
final class AppearanceController: NSObject, NSMenuItemValidation {
    static let shared = AppearanceController()

    private static let titles: [(Preferences.Appearance, String)] = [
        (.system, "Podle systému"),
        (.light, "Světlý"),
        (.dark, "Tmavý"),
    ]

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Vzhled")
        for (appearance, title) in Self.titles {
            let item = NSMenuItem(title: title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            item.image = NSImage(systemSymbolName: Self.symbol(for: appearance), accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }

    @objc func selectAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: Preferences.Key.appearance)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = (menuItem.representedObject as? String) == Preferences.appearance.rawValue ? .on : .off
        return true
    }

    static func symbol(for appearance: Preferences.Appearance) -> String {
        switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// Položka lišty s nabídkou; ikona ukazuje aktuální volbu a mění se s ní.
    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.menu = makeMenu()
        item.label = "Vzhled"
        item.toolTip = "Vzhled: podle systému, světlý nebo tmavý"
        item.showsIndicator = true
        updateImage(of: item)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak item] _ in
            MainActor.assumeIsolated {
                if let item { AppearanceController.shared.updateImage(of: item) }
            }
        }
        return item
    }

    private func updateImage(of item: NSMenuToolbarItem) {
        item.image = NSImage(systemSymbolName: Self.symbol(for: Preferences.appearance), accessibilityDescription: "Vzhled")
    }
}
