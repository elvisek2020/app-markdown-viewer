import FileWatch
import Foundation
import MarkdownCore

/// Obsah jednoho souboru: hlídá ho přes `FileWatcher` a renderuje na pozadí.
/// Starší rendery, které doběhnou pozdě, se zahodí (generation counter).
///
/// V režimu úprav renderuje text editoru a sám ho ukládá (sekundu po posledním psaní).
/// Stav disku ↔ editor drží `EditSync`: vlastní zápisy se ignorují, změna od agenta
/// bez neuložených úprav se tiše načte, s neuloženými úpravami vznikne konflikt.
final class DocumentModel {
    enum FileState: Equatable {
        case present
        case deleted
    }

    /// Co vyvolalo render – náhled zvýrazňuje jen změny souboru, ne psaní v editoru.
    enum RenderReason {
        case file, edit, options
    }

    private(set) var url: URL
    private(set) var rendered: RenderedDocument?
    private(set) var renderReason = RenderReason.file
    private(set) var fileState: FileState = .present

    private var renderObservers: [(RenderedDocument) -> Void] = []
    private var fileStateObservers: [(FileState) -> Void] = []
    private var moveObservers: [(URL) -> Void] = []
    private var reloadObservers: [(String) -> Void] = []
    private var editStateObservers: [() -> Void] = []
    private var saveObservers: [() -> Void] = []

    /// Odběr renderů (náhled, osnova); nový odběratel hned dostane poslední render.
    func observeRender(_ observer: @escaping (RenderedDocument) -> Void) {
        renderObservers.append(observer)
        if let rendered { observer(rendered) }
    }

    func observeFileState(_ observer: @escaping (FileState) -> Void) {
        fileStateObservers.append(observer)
    }

    func observeMove(_ observer: @escaping (URL) -> Void) {
        moveObservers.append(observer)
    }

    /// Nový obsah z disku, který se v režimu úprav načetl do editoru (agent zapsal, úpravy byly uložené).
    func observeReload(_ observer: @escaping (String) -> Void) {
        reloadObservers.append(observer)
    }

    /// Změna konfliktu nebo chyby ukládání (banner nad editorem).
    func observeEditState(_ observer: @escaping () -> Void) {
        editStateObservers.append(observer)
    }

    /// Úpravy byly zapsány na disk.
    func observeSave(_ observer: @escaping () -> Void) {
        saveObservers.append(observer)
    }

    var options = Preferences.renderOptions(includeSource: false) {
        didSet {
            if options != oldValue { render(sync.text, reason: .options) }
        }
    }

    /// Zobrazovaný text: v režimu úprav obsah editoru, jinak poslední obsah souboru.
    var text: String { sync.text }

    private var watcher: FileWatcher?
    private var sync = EditSync(text: "")
    private var generation = 0
    private var renderTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// Prodleva automatického uložení po posledním psaní.
    static let autosaveDelay: Duration = .seconds(1)

    init(url: URL) {
        self.url = url
    }

    func start() throws {
        let watcher = FileWatcher(url: url) { [weak self] event in
            // Watcher volá na své frontě; pořadí událostí musí zůstat zachované.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        let snapshot = try watcher.start()
        self.watcher = watcher
        sync = EditSync(text: snapshot.text)
        render(snapshot.text, reason: .file)
    }

    func stop() {
        renderTask?.cancel()
        saveTask?.cancel()
        watcher?.stop()
        watcher = nil
    }

    func checkNow() {
        watcher?.checkNow()
    }

    /// Ruční reload (⌘R) – přečte soubor znovu, i kdyby se podle watcheru nezměnil.
    func reload() {
        guard let data = try? Data(contentsOf: url) else {
            watcher?.checkNow()
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        if sync.isEditing {
            diskDidChange(text)
        } else {
            sync = EditSync(text: text)
            render(text, reason: .file)
        }
    }

    private func handle(_ event: FileWatchEvent) {
        switch event {
        case .updated(let snapshot):
            setFileState(.present)
            diskDidChange(snapshot.text)
        case .deleted:
            setFileState(.deleted)
        case .moved(_, let newURL):
            url = newURL
            moveObservers.forEach { $0(newURL) }
        }
    }

    private func setFileState(_ state: FileState) {
        guard state != fileState else { return }
        fileState = state
        fileStateObservers.forEach { $0(state) }
    }

    private func diskDidChange(_ text: String) {
        let wasConflict = sync.hasConflict
        switch sync.diskDidChange(text) {
        case .ignored:
            break
        case .reloaded(let text):
            if sync.isEditing { reloadObservers.forEach { $0(text) } }
            render(text, reason: .file)
        case .conflict:
            // Náhled dál ukazuje rozepsaný text; rozhodne uživatel v banneru.
            saveTask?.cancel()
        }
        if sync.hasConflict != wasConflict { notifyEditState() }
    }

    private func render(_ text: String, reason: RenderReason) {
        renderTask?.cancel()
        generation += 1
        let generation = generation
        let options = options
        Task.detached(priority: .userInitiated) {
            let document = MarkdownRenderer.render(text, options: options)
            await MainActor.run {
                guard generation == self.generation else { return }
                self.rendered = document
                self.renderReason = reason
                self.renderObservers.forEach { $0(document) }
            }
        }
    }

    // MARK: - Režim úprav

    var isEditing: Bool { sync.isEditing }
    var hasConflict: Bool { sync.hasConflict }
    var hasUnsavedChanges: Bool { sync.hasUnsavedChanges }
    /// Poslední známý obsah souboru (porovnání při konfliktu).
    var diskText: String { sync.disk }
    /// Chyba posledního ukládání; při úspěšném uložení zmizí.
    private(set) var saveError: String?

    /// Zapne režim úprav a vrátí text pro editor.
    func beginEditing() -> String {
        sync.beginEditing()
    }

    /// Text z editoru: náhled se překreslí hned, uloží se po chvíli klidu.
    func edit(_ text: String) {
        guard sync.isEditing, text != sync.buffer else { return }
        sync.edit(text)
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }
            self.render(self.sync.text, reason: .edit)
        }
        scheduleSave()
    }

    /// Vypne režim úprav. Neuložené úpravy se uloží; nevyřešený konflikt má volající rozhodnout předem.
    func endEditing() {
        guard sync.isEditing else { return }
        save(force: true)
        saveTask?.cancel()
        let changed = sync.buffer != sync.disk
        sync.endEditing()
        if saveError != nil { saveError = nil }
        if changed { render(sync.text, reason: .file) }
        notifyEditState()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard sync.pendingSave != nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Uloží neuložené úpravy. Před zápisem znovu přečte soubor: agent ho mohl změnit těsně předtím
    /// a watcher to ještě nestihl ohlásit – pak vznikne konflikt místo přepsání.
    /// Automatické ukládání čeká, dokud je soubor smazaný; `force` (konec úprav, zavření) ho vytvoří znovu.
    @discardableResult
    func save(force: Bool = false) -> Bool {
        saveTask?.cancel()
        guard sync.isEditing else { return true }
        guard sync.pendingSave != nil else { return !sync.hasConflict }
        if fileState == .deleted, !force { return false }
        if let data = try? Data(contentsOf: url) {
            diskDidChange(String(decoding: data, as: UTF8.self))
        }
        guard let text = sync.pendingSave else { return !sync.hasConflict }
        do {
            // Atomicky (dočasný soubor + přejmenování) a přes symlink na skutečný soubor.
            try Data(text.utf8).write(to: url.resolvingSymlinksInPath(), options: .atomic)
        } catch {
            saveError = error.localizedDescription
            notifyEditState()
            return false
        }
        sync.didSave(text)
        saveObservers.forEach { $0() }
        if saveError != nil {
            saveError = nil
            notifyEditState()
        }
        watcher?.checkNow()
        return true
    }

    /// Konflikt: platí verze z disku, úpravy v editoru se zahodí.
    func resolveConflictTakingDisk() {
        sync.resolveTakingDisk()
        reloadObservers.forEach { $0(sync.disk) }
        render(sync.disk, reason: .file)
        notifyEditState()
    }

    /// Konflikt: platí moje úpravy – hned se uloží přes verzi na disku.
    func resolveConflictKeepingMine() {
        sync.resolveKeepingMine()
        save(force: true)
        notifyEditState()
    }

    private func notifyEditState() {
        editStateObservers.forEach { $0() }
    }
}
