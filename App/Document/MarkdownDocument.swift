import AppKit

/// Read-only dokument. NSDocument dodává Open/Open Recent, taby, obnovu oken, otevírání
/// z Finderu a `open -a` i proxy ikonu v titulku; obsah ale čte a hlídá `DocumentModel`
/// s vlastním watcherem (NSDocument by při externí změně revertoval po svém).
final class MarkdownDocument: NSDocument {
    private(set) var model: DocumentModel?
    private var restoredLine: Int?

    nonisolated override class var autosavesInPlace: Bool { false }

    /// Může běžet mimo hlavní vlákno – jen ověří, že jde soubor číst (chyby oprávnění, TCC).
    /// Obsah načte a dál hlídá `DocumentModel`, který vzniká v `makeWindowControllers`.
    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        try handle.close()
    }

    override func makeWindowControllers() {
        guard let fileURL else { return }
        let model = DocumentModel(url: fileURL)
        do {
            try model.start()
        } catch {
            presentError(error)
            DispatchQueue.main.async { self.close() }
            return
        }
        model.observeMove { [weak self] newURL in
            self?.fileURL = newURL
        }
        self.model = model
        let controller = DocumentWindowController(model: model)
        addWindowController(controller)
        if let restoredLine {
            controller.preview.restore(line: restoredLine)
        }
    }

    override func close() {
        model?.stop()
        super.close()
    }

    // MARK: - Viewer nic neukládá

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(save(_:)), #selector(saveAs(_:)), #selector(saveTo(_:)), #selector(duplicate(_:)),
             #selector(rename(_:)), #selector(move(_:)), #selector(revertToSaved(_:)),
             #selector(browseVersions(_:)), #selector(lock(_:)), #selector(unlock(_:)):
            return false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: - NSFilePresenter – koordinované zápisy jen „šťouchnou“ vlastní watcher

    nonisolated override func presentedItemDidChange() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.model?.checkNow() }
        }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.model?.checkNow() }
        }
    }

    /// Smazání souboru dokument nezavře – okno zůstane s posledním obsahem a bannerem.
    nonisolated override func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        completionHandler(nil)
    }

    // MARK: - Obnova pozice po relaunchi

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        if let line = windowControllers.compactMap({ ($0 as? DocumentWindowController)?.preview.topLine }).first {
            coder.encode(line, forKey: "topLine")
        }
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        let line = coder.decodeInteger(forKey: "topLine")
        guard line > 1 else { return }
        restoredLine = line
        for case let controller as DocumentWindowController in windowControllers {
            controller.preview.restore(line: line)
        }
    }
}
