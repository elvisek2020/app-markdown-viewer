import AppKit
import MarkdownCore

/// Porovnání verze na disku s úpravami v editoru (konflikt). Řádky „−“ jsou jen na disku,
/// „+“ jen v editoru.
final class DiffSheet: NSWindowController {
    enum Choice {
        case takeDisk, keepMine, cancel
    }

    private let completion: (Choice) -> Void

    init(disk: String, mine: String, fileName: String, completion: @escaping (Choice) -> Void) {
        self.completion = completion
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 520, height: 320)
        super.init(window: window)

        let title = NSTextField(labelWithString: "Soubor „\(fileName)“ se změnil na disku")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let legend = NSTextField(labelWithString: "− jen ve verzi na disku    + jen v tvých úpravách")
        legend.textColor = .secondaryLabelColor

        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.render(LineDiff.hunks(from: disk, to: mine)))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView

        let takeDisk = NSButton(title: "Načíst verzi z disku", target: self, action: #selector(takeDisk(_:)))
        let keepMine = NSButton(title: "Ponechat moje úpravy", target: self, action: #selector(keepMine(_:)))
        keepMine.keyEquivalent = "\r"
        let cancel = NSButton(title: "Zavřít", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, NSView(), takeDisk, keepMine])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, legend, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    private static func render(_ hunks: [LineDiff.Hunk]) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()
        guard !hunks.isEmpty else {
            return NSAttributedString(string: "Žádné rozdíly.", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        }
        for hunk in hunks {
            result.append(NSAttributedString(string: hunk.header + "\n", attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            for line in hunk.lines {
                let (marker, background): (String, NSColor?) = switch line.kind {
                case .same: (" ", nil)
                case .removed: ("−", NSColor.systemRed.withAlphaComponent(0.16))
                case .added: ("+", NSColor.systemGreen.withAlphaComponent(0.16))
                }
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
                if let background { attributes[.backgroundColor] = background }
                result.append(NSAttributedString(string: "\(marker) \(line.text)\n", attributes: attributes))
            }
            result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        return result
    }

    func present(over parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func finish(_ choice: Choice) {
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        completion(choice)
    }

    /// Zavře porovnání bez volby (self-test).
    func dismiss() { finish(.cancel) }

    @objc private func takeDisk(_ sender: Any?) { finish(.takeDisk) }
    @objc private func keepMine(_ sender: Any?) { finish(.keepMine) }
    @objc private func cancel(_ sender: Any?) { finish(.cancel) }
}
