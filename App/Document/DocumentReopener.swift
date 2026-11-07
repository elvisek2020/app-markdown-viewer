import AppKit

/// Naposledy otevřené soubory a pracovní složky: uloží se při ukončení aplikace a při dalším
/// spuštění se znovu otevřou (Nastavení → Při spuštění otevřít naposledy otevřené soubory).
/// Nezávisí na systémové obnově oken, kterou macOS při běžném ukončení vypíná
/// (Nastavení systému → Plocha a Dock → Zavírat okna při ukončení aplikace).
enum DocumentReopener {
    /// Znovuotevření proběhne jednou za spuštění: při startu bez souborů (místo panelu Otevřít),
    /// jinak po dokončení spuštění (soubory z `mdv` nebo Finderu se otevřou navíc).
    private static var didReopen = false
    private static var pending = 0
    /// Právě běží vlastní `openDocument` znovuotevření (ne Finder, `mdv` ani Otevřít…).
    private(set) static var isOpeningOwn = false
    /// Soubor otevřený z Finderu nebo `mdv` při spuštění – po znovuotevření ostatních má zůstat vpředu.
    private static weak var explicitDocument: NSDocument?

    /// Volá `ViewerDocumentController` u dokumentů, které neotevřel tenhle typ.
    static func noteExplicitOpen(_ document: NSDocument) {
        explicitDocument = document
        // Dorazil až po znovuotevření – pořadí oken může ještě změnit pozdě zobrazené okno složky.
        if didReopen, pending == 0 { bringExplicitToFront() }
    }

    /// Vybere panel se souborem z Finderu a dá jeho okno dopředu – až v dalším průchodu run loopu,
    /// kdy jsou všechna znovuotevřená okna zobrazená (okno složky se může ukázat později).
    private static func bringExplicitToFront() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let document = explicitDocument, let window = document.windowControllers.first?.window else { return }
                window.tabGroup?.selectedWindow = window
                document.showWindows()
            }
        }
    }

    /// Klíč seznamu v předvolbách. Self-testy sdílejí předvolby s nainstalovanou aplikací,
    /// proto seznam nečtou ani nezapisují (kromě testu znovuotevření s vlastním klíčem).
    private static var key: String? {
        #if DEBUG
        if ReopenSelfTest.isActive { return ReopenSelfTest.defaultsKey }
        if SelfTest.isActive { return nil }
        #endif
        return Preferences.Key.lastDocuments
    }

    /// Volá se před ukončením aplikace – dokumenty jsou ještě otevřené (v pořadí otevření).
    /// Ukládá se až nejvyšší nabízený počet, aby se zvýšení limitu projevilo hned.
    static func save() {
        guard let key else { return }
        let paths = NSDocumentController.shared.documents.compactMap { $0.fileURL?.path }
            .suffix(Preferences.reopenLimits.max() ?? 30)
        // Pole, ne ArraySlice – ten UserDefaults jako seznam neuloží.
        UserDefaults.standard.set(Array(paths), forKey: key)
    }

    /// Otevře naposledy otevřené soubory, které ještě existují. Vrací, jestli se něco otevírá.
    @discardableResult
    static func reopen() -> Bool {
        guard !didReopen, let key, Preferences.reopenLastDocuments else { return false }
        didReopen = true
        let urls = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .suffix(Preferences.reopenLimit)
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return false }
        pending = urls.count
        for url in urls {
            isOpeningOwn = true
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
                pending -= 1
                // Soubor z Finderu se otevřel dřív a znovuotevřené okna/panely ho překryly.
                if pending == 0 { bringExplicitToFront() }
            }
            isOpeningOwn = false
        }
        return true
    }
}
