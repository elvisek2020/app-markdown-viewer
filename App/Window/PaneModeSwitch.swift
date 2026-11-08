import AppKit

/// Přepínač Zdroj | Upravit v nástrojové liště. Zapnutý je nejvýš jeden režim: klik na druhý
/// přepne rovnou, klik na zapnutý ho vypne a zůstane jen náhled. V režimu úprav lehce zabarví lištu.
/// Textový soubor má jen Upravit, log jen Zdroj.
final class PaneModeSwitch: NSObject {
    private enum Segment {
        case source, edit

        var image: NSImage {
            switch self {
            case .source: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Zdroj")!
            case .edit: NSImage(systemSymbolName: "pencil", accessibilityDescription: "Upravit")!
            }
        }

        var toolTip: String {
            switch self {
            case .source: "Zobrazit zdroj vedle náhledu (⌥⌘U)"
            case .edit: "Režim úprav – změny se ukládají automaticky (⌥⌘E)"
            }
        }
    }

    let item: NSToolbarItem
    private let control: NSSegmentedControl
    private weak var preview: PreviewController?
    private weak var window: NSWindow?
    private var segments: [Segment] = []

    init(window: NSWindow?) {
        self.window = window
        control = NSSegmentedControl(images: [], trackingMode: .selectAny, target: nil, action: nil)
        item = NSToolbarItem(itemIdentifier: ToolbarItems.mode)
        item.view = control
        item.label = "Zdroj a úpravy"
        super.init()
        control.target = self
        control.action = #selector(changed(_:))
        configure([.source, .edit])
    }

    private func configure(_ segments: [Segment]) {
        guard segments != self.segments else { return }
        self.segments = segments
        control.segmentCount = segments.count
        for (index, segment) in segments.enumerated() {
            control.setImage(segment.image, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(segment.toolTip, forSegment: index)
        }
    }

    private func isSelected(_ segment: Segment) -> Bool {
        segments.firstIndex(of: segment).map(control.isSelected(forSegment:)) ?? false
    }

    private func setSelected(_ selected: Bool, _ segment: Segment) {
        if let index = segments.firstIndex(of: segment) { control.setSelected(selected, forSegment: index) }
    }

    /// Napojí přepínač na náhled (pracovní složka ho mění s vybraným souborem).
    func attach(_ preview: PreviewController) {
        self.preview = preview
        var available: [Segment] = []
        if preview.allowsSource { available.append(.source) }
        if preview.allowsEditing { available.append(.edit) }
        configure(available)
        preview.onPaneModeChange = { [weak self] mode in self?.update(mode) }
        update(preview.paneMode)
    }

    /// Stav pro self-test: (zdroj, úpravy).
    var selection: (source: Bool, edit: Bool) {
        (isSelected(.source), isSelected(.edit))
    }

    private func update(_ mode: PreviewController.PaneMode) {
        setSelected(mode == .source, .source)
        setSelected(mode == .edit, .edit)
        applyTint(editing: mode == .edit)
    }

    @objc private func changed(_ sender: NSSegmentedControl) {
        guard let preview else { return }
        let source = isSelected(.source)
        let edit = isSelected(.edit)
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
