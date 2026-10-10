import AppKit

/// Položky nástrojové lišty společné pro okno dokumentu i pracovní složky.
enum ToolbarItems {
    static let source = NSToolbarItem.Identifier("cz.elvisek.mdview.source")
    static let search = NSToolbarItem.Identifier("cz.elvisek.mdview.search")
    static let follow = NSToolbarItem.Identifier("cz.elvisek.mdview.follow")

    /// Přepínací tlačítko s SF Symbolem; akce jde do responder chainu.
    static func toggle(
        _ identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        toolTip: String,
        action: Selector,
        isOn: Bool
    ) -> (NSToolbarItem, NSButton) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
        let button = NSButton(image: image, target: nil, action: action)
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .toolbar
        button.state = isOn ? .on : .off
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = label
        item.toolTip = toolTip
        return (item, button)
    }

    static func sourceToggle(isOn: Bool) -> (NSToolbarItem, NSButton) {
        toggle(source, symbol: "chevron.left.forwardslash.chevron.right", label: "Zdroj",
               toolTip: "Zobrazit zdroj vedle náhledu (⌥⌘U)", action: #selector(ViewerActions.toggleSourcePane(_:)), isOn: isOn)
    }

    static func searchItem() -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: search)
        item.searchField.placeholderString = "Hledat v dokumentu"
        item.searchField.sendsWholeSearchString = false
        item.label = "Hledat"
        return item
    }

    /// Napojí vyhledávací pole na náhled (při výměně dokumentu v pracovní složce znovu).
    static func connect(_ item: NSSearchToolbarItem?, to preview: PreviewController) {
        guard let item else { return }
        item.searchField.delegate = preview
        preview.searchField = item.searchField
        preview.searchItem = item
    }
}
