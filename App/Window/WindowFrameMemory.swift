import AppKit

/// Pamatuje si pozici a velikost okna: ukládá ji při zavření, posunu a změně velikosti a nové
/// okno otevře tam, kde bylo naposledy zavřené či přesunuté okno stejného druhu.
///
/// Místo `windowFrameAutosaveName`: autosave name může patřit jen jednomu oknu, takže u více
/// otevřených dokumentů by se zavření ostatních oken neuložilo. Klíč v UserDefaults zůstává stejný
/// (`NSWindow Frame <název>`), takže dříve uložené pozice platí dál.
@MainActor
final class WindowFrameMemory: NSObject {
    private let name: String
    private weak var window: NSWindow?

    /// Okno zaregistruje a hned mu nastaví uložený rám (nová okna se posunou kaskádovitě).
    init(window: NSWindow, name: String) {
        self.name = name
        self.window = window
        super.init()
        if window.setFrameUsingName(name) {
            cascadeIfOverlapping(window)
        } else {
            window.center()
        }
        for notification in [NSWindow.willCloseNotification, NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: notification, object: window)
        }
    }

    @objc private func save() {
        // V celé obrazovce se rám neukládá – po návratu by okno bylo přes celou plochu.
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: name)
    }

    /// Další okno se stejným počátkem (otevřené z téhož uloženého rámu) posunout o kus doprava dolů.
    private func cascadeIfOverlapping(_ window: NSWindow) {
        let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.tabbingIdentifier == window.tabbingIdentifier }
        var frame = window.frame
        while others.contains(where: { abs($0.frame.minX - frame.minX) < 4 && abs($0.frame.maxY - frame.maxY) < 4 }) {
            frame.origin.x += 24
            frame.origin.y -= 24
        }
        if frame != window.frame { window.setFrame(frame, display: false) }
    }
}
