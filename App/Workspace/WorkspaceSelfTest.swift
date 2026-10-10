#if DEBUG
import AppKit
import MarkdownCore

/// Self-test pracovní složky (`scripts/selftest-workspace.sh`): po načtení stromu zapne sledování,
/// vytvoří ve složce nový soubor (jen v /tmp) a ověří, že se na něj náhled sám přepnul a vykreslil ho.
enum WorkspaceSelfTest {
    static var reportPath: String? {
        UserDefaults.standard.string(forKey: "MDViewSelfTestWorkspaceReport")
    }

    @MainActor private static var report: [String: Any] = [:]
    @MainActor private static var stage = 0

    @MainActor
    static func treeUpdated(_ controller: WorkspaceWindowController, fileCount: Int) {
        guard reportPath != nil, report["fileCount"] == nil else { return }
        report["fileCount"] = fileCount
    }

    @MainActor
    static func selectionChanged(_ controller: WorkspaceWindowController, path: String, model: DocumentModel) {
        guard let reportPath else { return }
        let folder = controller.folder.path
        let relative = path.hasPrefix(folder + "/") ? String(path.dropFirst(folder.count + 1)) : path
        switch stage {
        case 0:
            stage = 1
            report["initial"] = relative
            controller.setFollowing(true)
            guard folder.hasPrefix("/tmp/") || folder.hasPrefix("/private/tmp/") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let output = URL(fileURLWithPath: folder).appendingPathComponent("agent/vystup.md")
                try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? "# Výstup agenta\n\nNový soubor.\n".write(to: output, atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                MainActor.assumeIsolated {
                    guard stage == 1 else { return }
                    report["followed"] = "timeout"
                    finish(reportPath)
                }
            }
        case 1:
            stage = 2
            report["followed"] = relative
            model.observeRender { document in
                MainActor.assumeIsolated {
                    guard report["followedTitle"] == nil else { return }
                    report["followedTitle"] = document.outline.first?.title ?? ""
                    finish(reportPath)
                }
            }
        default:
            break
        }
    }

    @MainActor
    private static func finish(_ path: String) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
#endif
