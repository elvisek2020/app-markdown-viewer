import AppKit

/// Přepínač Zdroj | Upravit v nástrojové liště. Zapnutý je nejvýš jeden režim: klik na druhý
/// přepne rovnou, klik na zapnutý ho vypne a zůstane jen náhled. V režimu úprav lehce zabarví lištu.
final class PaneModeSwitch: NSObject {
    private enum Segment: Int {
        case source, edit
    }

    let item: NSToolbarItem
    private let control: NSSegmentedControl
    private weak var preview: PreviewController?
    private weak var window: NSWindow?

    init(window: NSWindow?) {
        self.window = window
        let images = [
            NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Zdroj")!,
            NSImage(systemSymbolName: "pencil", accessibilityDescription: "Upravit")!,
        ]
        control = NSSegmentedControl(images: images, trackingMode: .selectAny, target: nil, action: nil)
        control.setToolTip("Zobrazit zdroj vedle náhledu (⌥⌘U)", forSegment: Segment.source.rawValue)
        control.setToolTip("Režim úprav – změny se ukládají automaticky (⌥⌘E)", forSegment: Segment.edit.rawValue)
        item = NSToolbarItem(itemIdentifier: ToolbarItems.mode)
        item.view = control
        item.label = "Zdroj a úpravy"
        super.init()
        control.target = self
        control.action = #selector(changed(_:))
    }

    /// Napojí přepínač na náhled (pracovní složka ho mění s vybraným souborem).
    func attach(_ preview: PreviewController) {
        self.preview = preview
        preview.onPaneModeChange = { [weak self] mode in self?.update(mode) }
        update(preview.paneMode)
    }

    /// Stav pro self-test: (zdroj, úpravy).
    var selection: (source: Bool, edit: Bool) {
        (control.isSelected(forSegment: Segment.source.rawValue), control.isSelected(forSegment: Segment.edit.rawValue))
    }

    private func update(_ mode: PreviewController.PaneMode) {
        control.setSelected(mode == .source, forSegment: Segment.source.rawValue)
        control.setSelected(mode == .edit, forSegment: Segment.edit.rawValue)
        applyTint(editing: mode == .edit)
    }

    @objc private func changed(_ sender: NSSegmentedControl) {
        guard let preview else { return }
        let source = sender.isSelected(forSegment: Segment.source.rawValue)
        let edit = sender.isSelected(forSegment: Segment.edit.rawValue)
        let target: PreviewController.PaneMode = switch (source, edit) {
        case (true, true): preview.paneMode == .source ? .edit : .source
        case (true, false): .source
        case (false, true): .edit
        case (false, false): .preview
        }
        preview.setPaneMode(target)
        // Uživatel mohl přechod zrušit (konflikt při ukončení úprav) – přepínač ukáže skutečný stav.
        update(preview.paneMode)
    }

    // MARK: - Zabarvení lišty v režimu úprav

    /// Pozadí okna lehce zabarvené akcentní barvou; s průhledným titulkem prosvítá lištou.
    static let editTint = NSColor(name: "MDViewEditTint") { appearance in
        var color = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            color = NSColor.windowBackgroundColor.blended(withFraction: dark ? 0.2 : 0.12, of: .controlAccentColor) ?? color
        }
        return color
    }

    private func applyTint(editing: Bool) {
        guard let window, window.titlebarAppearsTransparent != editing else { return }
        window.titlebarAppearsTransparent = editing
        window.backgroundColor = editing ? Self.editTint : .windowBackgroundColor
    }
}
