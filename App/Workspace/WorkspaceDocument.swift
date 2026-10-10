import AppKit

/// Pracovní složka (`mdv .`, Otevřít… se složkou, přetažení složky na ikonu): strom Markdown souborů
/// a náhled vybraného. Vybraný soubor jde upravovat stejně jako v okně dokumentu.
final class WorkspaceDocument: NSDocument {
    private var restoredSelection: String?
    private var restoredFollow: Bool?

    nonisolated override class var autosavesInPlace: Bool { false }

    /// Jen ověří, že jde složku číst; strom načte okno.
    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    override func makeWindowControllers() {
        guard let fileURL else { return }
        let controller = WorkspaceWindowController(folder: fileURL)
        addWindowController(controller)
        controller.restore(selection: restoredSelection, follow: restoredFollow)
    }

    /// Režim úprav vybraného souboru: před zavřením uložit, konflikt nechat rozhodnout.
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        MarkdownDocument.reply(to: delegate, selector: shouldCloseSelector, document: self, shouldClose: prepareToClose(), contextInfo: contextInfo)
    }

    func prepareToClose() -> Bool {
        (windowControllers.first as? WorkspaceWindowController)?.prepareToClose() ?? true
    }

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

    // Změny ve složce hlídá vlastní FolderWatcher.
    nonisolated override func presentedItemDidChange() {}

    nonisolated override func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        completionHandler(nil)
    }

    // MARK: - Obnova po relaunchi: vybraný soubor a režim sledování

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        if let controller = windowControllers.first as? WorkspaceWindowController {
            coder.encode(controller.selectedPath, forKey: "selectedPath")
            coder.encode(controller.isFollowing, forKey: "follow")
        }
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        restoredSelection = coder.decodeObject(of: NSString.self, forKey: "selectedPath") as String?
        restoredFollow = coder.containsValue(forKey: "follow") ? coder.decodeBool(forKey: "follow") : nil
        for case let controller as WorkspaceWindowController in windowControllers {
            controller.restore(selection: restoredSelection, follow: restoredFollow)
        }
    }
}

/// Document controller, který v Otevřít… dovolí vybrat i složku.
final class ViewerDocumentController: NSDocumentController {
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        openPanel.canChooseDirectories = true
        openPanel.message = "Vyber Markdown soubor, nebo složku jako pracovní prostor."
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
