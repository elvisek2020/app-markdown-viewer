import AppKit
import Security
import Updates

/// Aktualizace z GitHub Releases: MDView → Zkontrolovat aktualizace…, tlačítko v Nastavení
/// a automatická kontrola jednou denně při spuštění (vypnutelná v Nastavení).
///
/// Stáhne `MDView.zip` (stejný balíček jako install.sh), ověří, že je podepsaný stejnou identitou
/// jako běžící aplikace (designated requirement), pak spustí krátký skript, který po ukončení MDView
/// aplikaci vymění a znovu spustí. Stažení z aplikace karanténu nenastavuje, takže nenotarizovaná
/// aplikace projde bez dotazu Gatekeeperu.
final class UpdateController: NSObject, NSMenuItemValidation {
    static let shared = UpdateController()

    private static let repository = "elvisek2020/app-markdown-viewer"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var isBusy = false
    private var progressWindow: NSWindow?

    enum UpdateError: LocalizedError {
        case noRelease, http(Int), invalidPackage, invalidSignature, notWritable(String), tool(String)

        var errorDescription: String? {
            switch self {
            case .noRelease: "Na GitHubu zatím není žádné vydání."
            case .http(let code): "GitHub odpověděl chybou \(code)."
            case .invalidPackage: "Stažený balíček neobsahuje MDView.app."
            case .invalidSignature: "Stažená aplikace není podepsaná stejně jako nainstalovaná – neinstaluji ji."
            case .notWritable(let path): "Do \(path) nejde zapisovat. Aktualizuj přes install.sh v Terminálu."
            case .tool(let name): "Rozbalení aktualizace selhalo (\(name))."
            }
        }
    }

    private var apiURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "MDViewUpdateAPI"), let url = URL(string: override) { return url }
        #endif
        return URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
    }

    private static var isSelfTest: Bool {
        #if DEBUG
        SelfTest.isActive
        #else
        false
        #endif
    }

    // MARK: - Spouštění kontroly

    /// Menu MDView a tlačítko v Nastavení.
    @objc func checkForUpdates(_ sender: Any?) {
        Task { await check(interactive: true) }
    }

    /// Při spuštění: nejvýš jednou za den, jen se zapnutou volbou; výsledek hlásí jen novou verzi.
    func checkAutomatically() {
        guard !Self.isSelfTest, Preferences.autoCheckUpdates else { return }
        if let last = Preferences.lastUpdateCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await check(interactive: false)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        !isBusy
    }

    private func check(interactive: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let release = try await fetchLatest()
            if !Self.isSelfTest { UserDefaults.standard.set(Date(), forKey: Preferences.Key.lastUpdateCheck) }
            let current = ReleaseVersion(AppDelegate.version)
            guard let current, release.version > current else {
                if interactive {
                    inform("Máš nejnovější verzi", "MDView \(AppDelegate.version) je aktuální.")
                }
                return
            }
            if !interactive, Preferences.skippedUpdateVersion == release.version.description { return }
            switch ask(release, current: current, offerSkip: !interactive) {
            case .alertFirstButtonReturn:
                try await install(release)
            case .alertThirdButtonReturn:
                UserDefaults.standard.set(release.version.description, forKey: Preferences.Key.skippedUpdateVersion)
            default:
                break
            }
        } catch {
            hideProgress()
            if interactive {
                inform("Aktualizace se nepovedla", error.localizedDescription, style: .warning)
            } else {
                NSLog("MDView: automatická kontrola aktualizací selhala: \(error)")
            }
        }
    }

    // MARK: - GitHub

    func fetchLatest() async throws -> Release {
        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MDView/\(AppDelegate.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 404 ? UpdateError.noRelease : UpdateError.http(http.statusCode)
        }
        return try Release.parse(data)
    }

    /// Stáhne a rozbalí balíček a ověří podpis. Vrací cestu k nové MDView.app (v dočasné složce).
    func downloadAndVerify(_ zipURL: URL) async throws -> URL {
        let (download, response) = try await URLSession.shared.download(from: zipURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MDViewUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(Release.assetName)
        try FileManager.default.moveItem(at: download, to: zip)
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent("MDView.app")
        guard FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else {
            throw UpdateError.invalidPackage
        }
        try verifySignature(of: app)
        return app
    }

    /// Nová aplikace musí splnit designated requirement běžící aplikace (stejná identita podpisu
    /// i bundle ID) a projít přísným ověřením včetně vnořeného rozšíření.
    private func verifySignature(of app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            throw UpdateError.invalidSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess else {
            throw UpdateError.invalidSignature
        }
    }

    // MARK: - Instalace

    private func install(_ release: Release) async throws {
        showProgress("Stahuji MDView \(release.version)…")
        let app = try await downloadAndVerify(release.zipURL)
        hideProgress()
        try startInstaller(newApp: app, target: Bundle.main.bundleURL, relaunch: true)
        // Ukončení uloží rozepsané úpravy i seznam otevřených souborů; skript počká a aplikaci vymění.
        NSApp.terminate(nil)
    }

    /// Spustí skript, který počká na ukončení MDView, vymění `target` za `newApp` a případně
    /// aplikaci zaregistruje a znovu spustí. Když se MDView do minuty neukončí, skript skončí bez změn.
    func startInstaller(newApp: URL, target: URL, relaunch: Bool) throws {
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }
        let work = newApp.deletingLastPathComponent()
        let script = work.appendingPathComponent("install.sh")
        try Self.installerScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, target.path, work.path, relaunch ? "1" : "0"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static let installerScript = """
    #!/bin/sh
    # Výměna MDView po ukončení: <pid> <nová .app> <cílová .app> <pracovní složka> <znovu spustit 1/0>
    PID=$1 NEW=$2 TARGET=$3 WORK=$4 RELAUNCH=$5
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    i=0
    while kill -0 "$PID" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -gt 600 ] && { rm -rf "$WORK"; exit 1; }
        sleep 0.1
    done
    ditto "$NEW" "$TARGET.mdview-new" || { rm -rf "$TARGET.mdview-new" "$WORK"; exit 1; }
    # Staré rozšíření odregistrovat – jinak zůstane v pluginkitu dvakrát (stejná cesta, jiné UUID).
    [ "$RELAUNCH" = 1 ] && pluginkit -r "$TARGET/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null
    if [ -e "$TARGET" ]; then mv "$TARGET" "$TARGET.mdview-old" || { rm -rf "$TARGET.mdview-new" "$WORK"; exit 1; }; fi
    if ! mv "$TARGET.mdview-new" "$TARGET"; then
        mv "$TARGET.mdview-old" "$TARGET"
        rm -rf "$WORK"
        exit 1
    fi
    rm -rf "$TARGET.mdview-old"
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    touch "$TARGET"
    if [ "$RELAUNCH" = 1 ]; then
        "$LSREGISTER" -f "$TARGET"
        pluginkit -a "$TARGET/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null
        pluginkit -e use -i cz.elvisek.mdview.quicklook 2>/dev/null
        qlmanage -r >/dev/null 2>&1
        open "$TARGET"
    fi
    rm -rf "$WORK"
    """

    private func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent) }
    }

    // MARK: - UI

    private func ask(_ release: Release, current: ReleaseVersion, offerSkip: Bool) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Je dostupná nová verze MDView"
        alert.informativeText = """
        Verze \(release.version) (nainstalovaná \(current)). Aktualizace se stáhne z GitHubu, MDView se ukončí, \
        nahradí a znovu spustí. Rozepsané úpravy se před ukončením uloží.
        """
        alert.addButton(withTitle: "Nainstalovat a restartovat")
        alert.addButton(withTitle: "Později")
        if offerSkip { alert.addButton(withTitle: "Přeskočit tuto verzi") }
        NSApp.activate()
        return alert.runModal()
    }

    private func inform(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    private func showProgress(_ text: String) {
        let label = NSTextField(labelWithString: text)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let stack = NSStackView(views: [spinner, label])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 24)
        let window = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Aktualizace MDView"
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        progressWindow = window
    }

    private func hideProgress() {
        progressWindow?.close()
        progressWindow = nil
    }
}
