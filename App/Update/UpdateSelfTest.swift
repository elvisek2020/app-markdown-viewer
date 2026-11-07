#if DEBUG
import AppKit
import Updates

/// Self-test aktualizace (`scripts/selftest-update.sh`) bez GitHubu: API i balíčky jsou soubory
/// v /tmp (`-MDViewUpdateAPI file://…`). Ověří zjištění nové verze, stažení a ověření podpisu,
/// odmítnutí podvrženého balíčku a spustí výměnu – jen do cílové kopie v /tmp, bez restartu.
enum UpdateSelfTest {
    static var reportPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestUpdate") }
    static var isActive: Bool { reportPath != nil }

    /// Snímek okna Nastavení (tlačítko u verze, volba automatické kontroly).
    @MainActor
    private static func snapshotSettings(to path: String) async {
        let controller = SettingsWindowController.shared
        controller.showWindow(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard let view = controller.window?.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        controller.window?.close()
    }

    @MainActor
    static func run() {
        guard let reportPath, let target = UserDefaults.standard.string(forKey: "MDViewSelfTestUpdateTarget"),
              target.hasPrefix("/tmp/") || target.hasPrefix("/private/tmp/") else { return }
        Task {
            var report: [String: Any] = [:]
            let updater = UpdateController.shared
            // MDView → O aplikaci, hned pod ním Zkontrolovat aktualizace…
            let appMenu = NSApp.mainMenu?.items.first?.submenu
            report["menuItem"] = appMenu?.items.dropFirst().first?.action == #selector(UpdateController.checkForUpdates(_:))
            if let path = UserDefaults.standard.string(forKey: "MDViewSelfTestSettingsSnapshot") {
                await snapshotSettings(to: path)
            }
            do {
                let release = try await updater.fetchLatest()
                report["version"] = release.version.description
                report["newer"] = ReleaseVersion(AppDelegate.version).map { release.version > $0 } ?? false
                let app = try await updater.downloadAndVerify(release.zipURL)
                report["verified"] = true
                if let tampered = UserDefaults.standard.string(forKey: "MDViewSelfTestUpdateTampered").flatMap(URL.init(string:)) {
                    do {
                        _ = try await updater.downloadAndVerify(tampered)
                        report["tamperedRejected"] = false
                    } catch UpdateController.UpdateError.invalidSignature {
                        report["tamperedRejected"] = true
                    } catch {
                        report["tamperedRejected"] = "\(error)"
                    }
                }
                try updater.startInstaller(newApp: app, target: URL(fileURLWithPath: target), relaunch: false)
                report["installerStarted"] = true
            } catch {
                report["error"] = "\(error)"
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: reportPath))
            }
            // Skript výměny čeká na ukončení aplikace.
            NSApp.terminate(nil)
        }
    }
}
#endif
