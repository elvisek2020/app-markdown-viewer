import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // První vytvořená instance se stane NSDocumentController.shared (Otevřít… pak umí i složky).
        _ = ViewerDocumentController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        Preferences.applyAppearance()
        MainMenuExtras.install()
        // Vzhled se mění jen se změnou samotné předvolby – UserDefaults hlásí i automatické
        // ukládání rámů oken a podobně, a to nesmí přepsat dočasný vzhled (tisk, self-test).
        Self.appliedAppearance = Preferences.appearance
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard Preferences.appearance != Self.appliedAppearance else { return }
                Self.appliedAppearance = Preferences.appearance
                Preferences.applyAppearance()
            }
        }
        #if DEBUG
        SelfTest.configureApplication()
        WindowFrameSelfTest.run()
        #endif
    }

    private static var appliedAppearance = Preferences.Appearance.system

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(sender)
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
