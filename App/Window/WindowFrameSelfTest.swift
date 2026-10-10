#if DEBUG
import AppKit

/// Self-test paměti okna (`scripts/selftest-window.sh`): přesune okno na zadaný rám a zavře ho,
/// otevře další dokument (musí dostat stejný rám) a třetí (otevře se jako panel v témže okně).
/// Ukládá pod vlastním klíčem `NSWindow Frame MDViewSelfTestDocument`, který na konci smaže.
enum WindowFrameSelfTest {
    static var reportPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestWindowFrame") }
    static var isActive: Bool { reportPath != nil }
    private static var files: [String] { UserDefaults.standard.stringArray(forKey: "MDViewSelfTestFiles") ?? [] }
    private static let defaultsKey = "NSWindow Frame MDViewSelfTestDocument"

    @MainActor
    static func run() {
        guard let reportPath, files.count >= 2 else { return }
        Task {
            var report: [String: Any] = [:]
            guard let first = await documentWindow(after: 0) else {
                finish(["error": "první okno se neotevřelo"], to: reportPath)
                return
            }
            let visible = first.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let target = NSRect(x: visible.minX + 140, y: visible.minY + 120, width: 840, height: 640)
            first.setFrame(target, display: true)
            (first.windowController?.document as? NSDocument)?.close()
            report["target"] = NSStringFromRect(target)
            report["saved"] = UserDefaults.standard.string(forKey: defaultsKey) ?? ""

            let second = await open(files[0])
            report["reopened"] = second.map { NSStringFromRect($0.frame) } ?? "nic"
            let third = await open(files[1])
            report["thirdFrame"] = third.map { NSStringFromRect($0.frame) } ?? "nic"
            report["thirdTabbedWithSecond"] = third?.tabbedWindows?.contains { $0 === second } ?? false
            finish(report, to: reportPath)
        }
    }

    @MainActor
    private static func open(_ path: String) async -> NSWindow? {
        let count = NSApp.windows.filter { $0.windowController is DocumentWindowController && $0.isVisible }.count
        NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
        return await documentWindow(after: count)
    }

    /// Čeká, až bude otevřeno víc oken dokumentů než `count`, a vrátí nejnovější.
    @MainActor
    private static func documentWindow(after count: Int) async -> NSWindow? {
        for _ in 0..<50 {
            let windows = NSApp.windows.filter { $0.windowController is DocumentWindowController && $0.isVisible }
            if windows.count > count { return windows.max { $0.windowNumber < $1.windowNumber } }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor
    private static func finish(_ report: [String: Any], to path: String) {
        // Nejdřív zavřít okna (uloží rám), teprve pak klíč smazat – jinak by ho ukončení uložilo znovu.
        NSDocumentController.shared.documents.forEach { $0.close() }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
#endif
