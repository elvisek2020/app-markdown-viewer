import AppKit

/// Naposledy otevřené soubory a pracovní složky: uloží se při ukončení aplikace a při dalším
/// spuštění se znovu otevřou (Nastavení → Při spuštění otevřít naposledy otevřené soubory).
/// Nezávisí na systémové obnově oken, kterou macOS při běžném ukončení vypíná
/// (Nastavení systému → Plocha a Dock → Zavírat okna při ukončení aplikace).
enum DocumentReopener {
    /// Znovuotevření proběhne jednou za spuštění: při startu bez souborů (místo panelu Otevřít),
    /// jinak po dokončení spuštění (soubory z `mdv` nebo Finderu se otevřou navíc).
    private static var didReopen = false

    /// Klíč seznamu v předvolbách. Self-testy sdílejí předvolby s nainstalovanou aplikací,
    /// proto seznam nečtou ani nezapisují (kromě testu znovuotevření s vlastním klíčem).
    private static var key: String? {
        #if DEBUG
        if ReopenSelfTest.isActive { return ReopenSelfTest.defaultsKey }
        if SelfTest.isActive { return nil }
        #endif
        return Preferences.Key.lastDocuments
    }

    /// Volá se před ukončením aplikace – dokumenty jsou ještě otevřené.
    static func save() {
        guard let key else { return }
        let paths = NSDocumentController.shared.documents.compactMap { $0.fileURL?.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    /// Otevře naposledy otevřené soubory, které ještě existují. Vrací, jestli se něco otevírá.
    @discardableResult
    static func reopen() -> Bool {
        guard !didReopen, let key, Preferences.reopenLastDocuments else { return false }
        didReopen = true
        let urls = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return false }
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        return true
    }
}
