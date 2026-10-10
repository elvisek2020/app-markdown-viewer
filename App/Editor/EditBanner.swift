import AppKit

/// Pruh nad editorem a náhledem: konflikt se změnou na disku nebo chyba ukládání.
final class EditBanner: NSBox {
    static let height: CGFloat = 38

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var handlers: [() -> Void] = []

    /// Text zprávy (self-test).
    var message: String { label.stringValue }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Self.height))
        boxType = .custom
        borderWidth = 0
        cornerRadius = 0
        contentViewMargins = .zero
        fillColor = NSColor.systemYellow.withAlphaComponent(0.18)
        isHidden = true

        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .systemOrange
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    func show(symbol: String, message: String, actions: [(String, () -> Void)]) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        label.stringValue = message
        label.toolTip = message
        handlers = actions.map(\.1)
        stack.setViews([icon, label], in: .leading)
        let buttons = actions.enumerated().map { index, action in
            let button = NSButton(title: action.0, target: self, action: #selector(buttonPressed(_:)))
            button.tag = index
            button.bezelStyle = .push
            button.controlSize = .small
            return button
        }
        stack.setViews(buttons, in: .trailing)
        isHidden = false
    }

    func hide() {
        isHidden = true
        handlers = []
    }

    /// Vyvolá akci tlačítka podle pořadí (self-test).
    func perform(_ index: Int) {
        guard handlers.indices.contains(index) else { return }
        handlers[index]()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        perform(sender.tag)
    }
}
