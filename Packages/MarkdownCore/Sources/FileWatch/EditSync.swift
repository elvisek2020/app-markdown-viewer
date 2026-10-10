/// Stav textu dokumentu mezi diskem a editorem (režim úprav).
///
/// - `disk` – poslední známý obsah souboru (načtený watcherem nebo naposledy uložený),
/// - `base` – verze, ze které vychází text editoru (poslední načtená nebo uložená),
/// - `buffer` – text editoru; `nil`, když režim úprav neběží.
///
/// Změna na disku bez neuložených úprav se do editoru tiše načte; s neuloženými úpravami
/// vznikne konflikt, který rozhodne uživatel. Vlastní zápisy se poznají podle obsahu:
/// watcher je hlásí se zpožděním, takže se pamatuje i několik posledních uložených verzí.
public struct EditSync: Sendable, Equatable {
    public private(set) var disk: String
    public private(set) var base: String
    public private(set) var buffer: String?
    private var ownWrites: [String] = []
    private static let ownWritesLimit = 4

    public init(text: String) {
        disk = text
        base = text
    }

    public enum DiskChange: Sendable, Equatable {
        /// Vlastní zápis nebo obsah, který už editor (náhled) má.
        case ignored
        /// Nový obsah se má zobrazit (a v režimu úprav načíst do editoru).
        case reloaded(String)
        /// Soubor se změnil a editor má neuložené úpravy.
        case conflict
    }

    public var isEditing: Bool { buffer != nil }

    /// Text pro náhled: rozepsaný v editoru, jinak obsah disku.
    public var text: String { buffer ?? disk }

    public var hasUnsavedChanges: Bool { buffer.map { $0 != base } ?? false }

    /// Disk se změnil od verze, ze které editor vychází – rozhodne uživatel.
    public var hasConflict: Bool { isEditing && disk != base }

    /// Text k uložení; `nil`, když není co ukládat nebo trvá konflikt.
    public var pendingSave: String? {
        guard hasUnsavedChanges, !hasConflict else { return nil }
        return buffer
    }

    /// Zapne režim úprav a vrátí text pro editor.
    public mutating func beginEditing() -> String {
        if buffer == nil {
            base = disk
            buffer = disk
        }
        return disk
    }

    /// Vypne režim úprav. Neuložené úpravy (a nevyřešený konflikt) zahodí – volající je má nejdřív uložit.
    public mutating func endEditing() {
        buffer = nil
        base = disk
    }

    public mutating func edit(_ text: String) {
        guard buffer != nil else { return }
        buffer = text
    }

    /// Text byl zapsán na disk.
    public mutating func didSave(_ text: String) {
        disk = text
        base = text
        ownWrites.append(text)
        if ownWrites.count > Self.ownWritesLimit { ownWrites.removeFirst() }
    }

    /// Watcher (nebo kontrola před uložením) přečetl ze souboru `text`.
    public mutating func diskDidChange(_ text: String) -> DiskChange {
        if text == disk {
            // Watcher dohnal poslední zápis – starší vlastní verze už nepřijdou.
            ownWrites.removeAll()
            return .ignored
        }
        if ownWrites.contains(text) { return .ignored }
        disk = text
        guard let buffer else {
            base = text
            return .reloaded(text)
        }
        if buffer == text {
            base = text
            return .ignored
        }
        if buffer == base {
            base = text
            self.buffer = text
            return .reloaded(text)
        }
        return .conflict
    }

    /// Vyřešení konfliktu: platí verze z disku.
    public mutating func resolveTakingDisk() {
        base = disk
        if buffer != nil { buffer = disk }
    }

    /// Vyřešení konfliktu: platí moje úpravy (uloží se přes `pendingSave`).
    public mutating func resolveKeepingMine() {
        base = disk
    }
}
