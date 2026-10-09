import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.followTail: true,
            PreferenceKey.pageZoom: 1.0,
        ])
        MainMenuExtras.install()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    /// Viewer nemá prázdný dokument – místo něj (spuštění bez souboru, klik na Dock) ukáže Open panel.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

enum PreferenceKey {
    static let followTail = "followTail"
    static let pageZoom = "pageZoom"
}
