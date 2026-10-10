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

    /// Okno O aplikaci: standardní panel (název, verze, copyright) doplněný o autora a odkaz na repo.
    @objc func showAbout(_ sender: Any?) {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let text: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ]
        let credits = NSMutableAttributedString(string: "Autor: ElvisEK\n", attributes: text)
        var link = text
        link[.link] = URL(string: "https://github.com/elvisek2020/app-markdown-viewer")
        credits.append(NSAttributedString(string: "github.com/elvisek2020/app-markdown-viewer", attributes: link))
        var muted = text
        muted[.foregroundColor] = NSColor.secondaryLabelColor
        credits.append(NSAttributedString(
            string: "\n\nNativní Markdown viewer",
            attributes: muted
        ))
        // Verze RRRRMMDD.HHMM; prázdné číslo buildu skryje závorku za ní (je stejné jako verze).
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: Self.version,
            .version: "",
        ])
        NSApp.activate()
    }

    /// Verze aplikace ve formátu RRRRMMDD.HHMM (z Info.plist, dosazuje ji Makefile při buildu).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

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
