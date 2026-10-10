import AppKit
import SwiftUI

/// Okno Nastavení (⌘,). Hodnoty jdou rovnou do UserDefaults; otevřená okna reagují na změnu.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Nastavení"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.Key.appearance) private var appearance = Preferences.Appearance.system.rawValue
    @AppStorage(Preferences.Key.frontMatter) private var frontMatter = "table"
    @AppStorage(Preferences.Key.math) private var math = true
    @AppStorage(Preferences.Key.emoji) private var emoji = true
    @AppStorage(Preferences.Key.remoteImages) private var remoteImages = true
    @AppStorage(Preferences.Key.followTail) private var followTail = true
    @AppStorage(Preferences.Key.showSource) private var showSource = false
    @AppStorage(Preferences.Key.ignoreDiacritics) private var ignoreDiacritics = true

    var body: some View {
        Form {
            Section("Vzhled") {
                Picker("Vzhled", selection: $appearance) {
                    Text("Podle systému").tag(Preferences.Appearance.system.rawValue)
                    Text("Světlý").tag(Preferences.Appearance.light.rawValue)
                    Text("Tmavý").tag(Preferences.Appearance.dark.rawValue)
                }
                .pickerStyle(.segmented)
            }
            Section("Vykreslování") {
                Picker("Front matter", selection: $frontMatter) {
                    Text("Tabulka").tag("table")
                    Text("Sbalený YAML").tag("collapsed")
                    Text("Skrytý").tag("hidden")
                }
                Toggle("Matika (KaTeX)", isOn: $math)
                Toggle("Emoji zkratky (:rocket: → 🚀)", isOn: $emoji)
                Toggle("Načítat obrázky z internetu", isOn: $remoteImages)
            }
            Section("Chování") {
                Toggle("Sledovat konec souboru, když je náhled odscrollovaný dolů", isOn: $followTail)
                Toggle("Nová okna se zdrojovým panelem", isOn: $showSource)
                Toggle("Hledat bez ohledu na diakritiku", isOn: $ignoreDiacritics)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }
}
