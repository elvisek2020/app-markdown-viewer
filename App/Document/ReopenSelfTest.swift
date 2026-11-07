#if DEBUG
import AppKit

/// Self-test znovuotevření (`scripts/selftest-reopen.sh`), dvě spuštění s vlastním klíčem v předvolbách:
/// fáze 1 počká na otevřené dokumenty a ukončí aplikaci (seznam se uloží), fáze 2 se spustí bez
/// souborů a zapíše, co se samo otevřelo (s limitem `-reopenLimit`) a jestli se neukázal panel
/// Otevřít; fáze 3 se spustí se souborem jako z Finderu – ten musí zůstat vpředu. Klíč smaže skript.
enum ReopenSelfTest {
    static let defaultsKey = "MDViewSelfTestLastDocuments"
    static var reportPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestReopen") }
    static var isActive: Bool { reportPath != nil }
    private static var phase: Int { UserDefaults.standard.integer(forKey: "MDViewSelfTestReopenPhase") }
    /// Fáze 1 čeká na všechny otevřené dokumenty, fáze 2 na tolik, kolik dovolí limit.
    private static var expected: Int {
        let opened = UserDefaults.standard.integer(forKey: "MDViewSelfTestReopenCount")
        let extra = UserDefaults.standard.integer(forKey: "MDViewSelfTestReopenExtra")
        return phase == 1 ? opened : min(opened, Preferences.reopenLimit) + extra
    }

    @MainActor
    static func run() {
        guard let reportPath else { return }
        Task {
            for _ in 0..<80 where NSDocumentController.shared.documents.count < expected {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if phase == 1 {
                NSApp.terminate(nil)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            // Vpředu je vybraný panel nejpřednějšího okna (nevybrané panely nejsou viditelné).
            let front = NSApp.orderedWindows.first { $0.isVisible && $0.windowController?.document != nil }
            let report: [String: Any] = [
                "reopened": NSDocumentController.shared.documents.compactMap { $0.fileURL?.lastPathComponent }.sorted(),
                "openPanelShown": NSApp.windows.contains { $0 is NSOpenPanel && $0.isVisible },
                "front": (front?.windowController?.document as? NSDocument)?.fileURL?.lastPathComponent ?? "",
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: reportPath))
            }
            NSDocumentController.shared.documents.forEach { $0.close() }
            exit(0)
        }
    }
}
#endif
