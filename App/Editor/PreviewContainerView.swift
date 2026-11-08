import AppKit

/// Obsah okna vedle osnovy: banner úprav nahoře, pod ním split editor | náhled.
/// Bez režimu úprav je ve splitu jen náhled; textové soubory mají editor přes celou šířku.
final class PreviewContainerView: NSView, NSSplitViewDelegate {
    let banner = EditBanner()
    let split = NSSplitView()
    private var editorView: NSView?
    private let previewView: NSView
    private var pendingRatio: Double?

    /// Uživatel posunul dělič – podíl šířky editoru.
    var onDividerMoved: ((Double) -> Void)?

    init(preview: NSView) {
        previewView = preview
        super.init(frame: preview.frame)
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.addArrangedSubview(preview)
        addSubview(split)
        addSubview(banner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    /// Tisk do PDF běží na vlákně na pozadí a AppKit se ptá i předků webview (`visibleRect`) –
    /// izolované getter by Swift 6 za běhu shodil.
    nonisolated override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let bannerHeight = banner.isHidden ? 0 : EditBanner.height
        banner.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bannerHeight)
        split.frame = NSRect(x: 0, y: bannerHeight, width: bounds.width, height: max(0, bounds.height - bannerHeight))
        if let ratio = pendingRatio, split.bounds.width > 0 {
            split.adjustSubviews()
            split.setPosition((split.bounds.width - split.dividerThickness) * ratio, ofDividerAt: 0)
            pendingRatio = nil
        }
    }

    var isEditorVisible: Bool { editorView != nil }

    /// `fullWidth`: editor sám, náhled zůstane skrytý (dál se aktualizuje, po konci úprav je hned hotový).
    func showEditor(_ view: NSView, ratio: Double, fullWidth: Bool = false) {
        editorView = view
        split.insertArrangedSubview(view, at: 0)
        if fullWidth {
            previewView.isHidden = true
            split.adjustSubviews()
        } else {
            pendingRatio = min(0.75, max(0.25, ratio))
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func hideEditor() {
        editorView?.removeFromSuperview()
        editorView = nil
        pendingRatio = nil
        previewView.isHidden = false
        split.adjustSubviews()
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 220)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 260)
    }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        previewView.isHidden
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // Index děliče je v userInfo jen při tažení děličem, ne při změně velikosti okna.
        guard notification.userInfo?["NSSplitViewDividerIndex"] != nil, pendingRatio == nil,
              let editorView, split.bounds.width > 0 else { return }
        onDividerMoved?(editorView.frame.width / split.bounds.width)
    }
}
