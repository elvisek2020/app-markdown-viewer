import AppKit

/// Jednoduchý editor Markdownu: `NSTextView` (TextKit 1 – přesné pozice řádků pro synchronizaci
/// s náhledem), neproporcionální písmo, bez automatických náhrad a kontroly pravopisu.
/// Vzniká až při zapnutí režimu úprav, takže start aplikace nezdržuje. Barvy, písmo a řádkování
/// má stejné jako zdrojový panel (`--mdv-source-*` v app.css), aby přepnutí zdroj ↔ úpravy nebylo znát.
final class MarkdownEditor: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView = NSTextView(usingTextLayoutManager: false)
    private let undo = UndoManager()
    private var lineStarts: [Int]?
    private var isScrollingProgrammatically = false

    /// Uživatel změnil text (ne `replaceText`).
    var onChange: ((String) -> Void)?
    /// Uživatel posunul editor nebo psaním odroloval – zlomkový první viditelný řádek.
    var onScroll: ((Double) -> Void)?

    var text: String { textView.string }

    init(text: String) {
        super.init()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.backgroundColor = Self.background
        textView.insertionPointColor = .controlAccentColor
        scrollView.backgroundColor = Self.background
        // Řádkování 1,6 jako zdrojový panel; posun účaří zarovná text doprostřed vyššího řádku.
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let lineHeight = (font.pointSize * 1.6).rounded()
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.foreground,
            .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2,
        ]
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = self

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    /// Barvy zdrojového panelu (app.css: --mdv-source-bg, --mdv-source-fg) podle vzhledu.
    private static let background = NSColor(name: "MDViewEditorBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x01 / 255, green: 0x04 / 255, blue: 0x09 / 255, alpha: 1)
            : NSColor(srgbRed: 0xF6 / 255, green: 0xF8 / 255, blue: 0xFA / 255, alpha: 1)
    }

    private static let foreground = NSColor(name: "MDViewEditorForeground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xE6 / 255, green: 0xED / 255, blue: 0xF3 / 255, alpha: 1)
            : NSColor(srgbRed: 0x1F / 255, green: 0x23 / 255, blue: 0x28 / 255, alpha: 1)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        lineStarts = nil
        onChange?(textView.string)
    }

    /// Vlastní historie zpět/znovu – po načtení verze z disku se zahodí.
    func undoManager(for view: NSTextView) -> UndoManager? {
        undo
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard !isScrollingProgrammatically else { return }
        onScroll?(topLine())
    }

    // MARK: - Načtení verze z disku

    /// Nahradí text (agent zapsal soubor) – mění jen změněný úsek, takže kurzor i pozice zůstanou.
    func replaceText(_ newText: String) {
        let old = textView.string as NSString
        let new = newText as NSString
        guard old != new, let storage = textView.textStorage else { return }
        let common = min(old.length, new.length)
        var prefix = 0
        while prefix < common, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < common - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        let changed = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        let delta = (replacement as NSString).length - changed.length

        func shifted(_ location: Int) -> Int {
            if location >= NSMaxRange(changed) { return location + delta }
            return min(location, prefix + (replacement as NSString).length)
        }
        let selection = textView.selectedRange()
        let anchor = topAnchor()

        storage.replaceCharacters(in: changed, with: NSAttributedString(string: replacement, attributes: textView.typingAttributes))
        lineStarts = nil
        undo.removeAllActions()

        let start = shifted(selection.location)
        let end = shifted(NSMaxRange(selection))
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        if let anchor { scroll(toCharacter: shifted(anchor.character), offset: anchor.offset) }
    }

    // MARK: - Pozice řádků (synchronizace s náhledem)

    /// Zlomkový první viditelný řádek zdroje (1 = začátek souboru).
    func topLine() -> Double {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 1 }
        let y = scrollView.contentView.bounds.minY - textView.textContainerOrigin.y
        let length = (textView.string as NSString).length
        guard y > 0, length > 0 else { return 1 }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let line = lineIndex(containing: layoutManager.characterIndexForGlyph(at: glyph))
        let rect = lineRect(line)
        let fraction = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
        return Double(line + 1) + Double(fraction)
    }

    /// Posune editor tak, aby zlomkový řádek `line` byl nahoře.
    func scroll(toLine line: Double) {
        let starts = lineStartOffsets()
        let index = min(starts.count - 1, max(0, Int(line) - 1))
        let rect = lineRect(index)
        let fraction = CGFloat(max(0, line - line.rounded(.down)))
        scroll(toY: rect.minY + fraction * rect.height)
    }

    private func scroll(toY y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        isScrollingProgrammatically = true
        clip.scroll(to: NSPoint(x: 0, y: min(maxY, max(0, y + textView.textContainerOrigin.y))))
        scrollView.reflectScrolledClipView(clip)
        isScrollingProgrammatically = false
    }

    /// Znak na horním okraji a odsazení jeho řádku – po náhradě textu se k němu editor vrátí.
    private func topAnchor() -> (character: Int, offset: CGFloat)? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              layoutManager.numberOfGlyphs > 0 else { return nil }
        let y = scrollView.contentView.bounds.minY - textView.textContainerOrigin.y
        guard y > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (layoutManager.characterIndexForGlyph(at: glyph), y - fragment.minY)
    }

    private func scroll(toCharacter character: Int, offset: CGFloat) {
        guard let layoutManager = textView.layoutManager, layoutManager.numberOfGlyphs > 0 else { return }
        let length = (textView.string as NSString).length
        let glyph = layoutManager.glyphIndexForCharacter(at: min(character, max(0, length - 1)))
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        scroll(toY: fragment.minY + offset)
    }

    /// Začátky řádků v UTF-16 (LF, CRLF i samotné CR – stejně jako čísla řádků v cmarku).
    private func lineStartOffsets() -> [Int] {
        if let lineStarts { return lineStarts }
        let units = Array(textView.string.utf16)
        var starts = [0]
        for index in units.indices {
            let unit = units[index]
            if unit == 10 || (unit == 13 && (index + 1 == units.count || units[index + 1] != 10)) {
                starts.append(index + 1)
            }
        }
        lineStarts = starts
        return starts
    }

    private func lineIndex(containing character: Int) -> Int {
        let starts = lineStartOffsets()
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= character { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Obdélník celého zdrojového řádku (i zalomeného na víc řádků editoru) v souřadnicích kontejneru.
    private func lineRect(_ index: Int) -> NSRect {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return .zero }
        let starts = lineStartOffsets()
        let length = (textView.string as NSString).length
        let start = starts[index]
        let end = index + 1 < starts.count ? starts[index + 1] : length
        layoutManager.ensureLayout(for: container)
        guard start < length, end > start else {
            // Prázdný poslední řádek za koncovým zalomením.
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 { return extra }
            return NSRect(x: 0, y: layoutManager.usedRect(for: container).maxY, width: 0, height: 0)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: end - start), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        let first = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        return first.union(last)
    }
}
