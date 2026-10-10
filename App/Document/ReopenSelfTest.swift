#if DEBUG
import AppKit

/// Self-test znovuotevření (`scripts/selftest-reopen.sh`), dvě spuštění s vlastním klíčem v předvolbách:
/// fáze 1 počká na otevřené dokumenty a ukončí aplikaci (seznam se uloží), fáze 2 se spustí bez
/// souborů a zapíše, co se samo otevřelo a jestli se neukázal panel Otevřít. Pak klíč smaže.
enum ReopenSelfTest {
    static let defaultsKey = "MDViewSelfTestLastDocuments"
    static var reportPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestReopen") }
    static var isActive: Bool { reportPath != nil }
    private static var phase: Int { UserDefaults.standard.integer(forKey: "MDViewSelfTestReopenPhase") }
    private static var expected: Int { UserDefaults.standard.integer(forKey: "MDViewSelfTestReopenCount") }

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
            let report: [String: Any] = [
                "reopened": NSDocumentController.shared.documents.compactMap { $0.fileURL?.lastPathComponent }.sorted(),
                "openPanelShown": NSApp.windows.contains { $0 is NSOpenPanel && $0.isVisible },
            ]
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: reportPath))
            }
            NSDocumentController.shared.documents.forEach { $0.close() }
            exit(0)
        }
    }
}
#endif
