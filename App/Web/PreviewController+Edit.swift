import AppKit

/// Režim úprav: editor vlevo, náhled vpravo, ukládání automaticky (`DocumentModel`).
/// Když agent změní soubor a v editoru jsou neuložené úpravy, banner nabídne načíst verzi
/// z disku, ponechat moje úpravy, nebo obě verze porovnat.
extension PreviewController {
    var isEditing: Bool { editor != nil }

    @objc func toggleEditMode(_ sender: Any?) {
        setPaneMode(isEditing ? .preview : .edit)
    }

    /// Přepne, co je vedle náhledu. Vrací `false`, když uživatel ukončení úprav zrušil (konflikt).
    @discardableResult
    func setPaneMode(_ mode: PaneMode) -> Bool {
        guard mode != paneMode else { return true }
        switch mode {
        case .edit:
            setSourceVisible(false)
            beginEditing()
        case .source, .preview:
            guard finishEditing() else { return false }
            setSourceVisible(mode == .source)
        }
        return true
    }

    /// ⌘S v režimu úprav: uložit hned, nečekat na automatické uložení. PreviewController je
    /// v responder chainu před dokumentem, takže NSDocument se k ukládání nedostane.
    /// (Swiftí `NSDocument.save(_:)` je v Objective-C `saveDocument:`.)
    @objc func saveDocument(_ sender: Any?) {
        guard editor != nil else { return }
        model.save(force: true)
    }

    func beginEditing() {
        guard editor == nil else { return }
        let editor = MarkdownEditor(text: model.beginEditing())
        editor.onChange = { [weak self] text in self?.editorDidChange(text) }
        editor.onScroll = { [weak self] line in self?.editorDidScroll(toLine: line) }
        self.editor = editor
        editorLeads = false
        container.showEditor(editor.scrollView, ratio: Preferences.editorWidth)
        applySourceState()
        view.window?.makeFirstResponder(editor.textView)
        Task {
            try? await call("mdv.setEditing(true)")
            // Editor začne na stejném místě, jaké ukazoval náhled.
            if let value = await callString("return String(mdv.previewLine())"), let line = Double(value) {
                self.editor?.scroll(toLine: line)
            }
        }
        updateEditBanner()
        onPaneModeChange?(paneMode)
    }

    /// Vypne režim úprav (uloží; konflikt nebo chybu ukládání nechá rozhodnout uživatele).
    /// Vrací `false`, když uživatel zrušil.
    @discardableResult
    func finishEditing() -> Bool {
        guard editor != nil else { return true }
        guard prepareToLeaveEditing(cancellable: true) else { return false }
        model.endEditing()
        diffSheet?.close()
        diffSheet = nil
        container.hideEditor()
        editor = nil
        editorLeads = false
        applySourceState()
        view.window?.makeFirstResponder(webView)
        Task { try? await call("mdv.setEditing(false)") }
        updateEditBanner()
        onPaneModeChange?(paneMode)
        return true
    }

    /// Před zavřením okna, přepnutím souboru nebo koncem úprav: uloží rozepsané změny.
    /// Konflikt s verzí na disku nebo chybu zápisu nechá rozhodnout uživatele (modální dotaz).
    /// Vrací `false`, když uživatel zrušil (jen s `cancellable`).
    func prepareToLeaveEditing(cancellable: Bool) -> Bool {
        guard editor != nil else { return true }
        while model.hasConflict {
            let alert = NSAlert()
            alert.messageText = "Soubor „\(model.url.lastPathComponent)“ se mezitím změnil na disku."
            alert.informativeText = "Tvoje úpravy nejsou uložené. Můžeš je uložit přes verzi na disku, nebo je zahodit a ponechat verzi z disku."
            alert.addButton(withTitle: "Uložit moje úpravy")
            alert.addButton(withTitle: "Zahodit moje úpravy")
            if cancellable { alert.addButton(withTitle: "Zrušit") }
            switch alert.runModal() {
            case .alertFirstButtonReturn: model.resolveConflictKeepingMine()
            case .alertSecondButtonReturn: model.resolveConflictTakingDisk()
            default: return false
            }
        }
        if !model.save(force: true), model.hasUnsavedChanges {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Úpravy souboru „\(model.url.lastPathComponent)“ se nepodařilo uložit."
            alert.informativeText = model.saveError ?? ""
            alert.addButton(withTitle: "Zahodit úpravy")
            if cancellable { alert.addButton(withTitle: "Zrušit") }
            if alert.runModal() != .alertFirstButtonReturn { return false }
        }
        return true
    }

    // MARK: - Konflikt

    func updateEditBanner() {
        let banner = container.banner
        if isEditing, model.hasConflict {
            banner.show(
                symbol: "exclamationmark.triangle.fill",
                message: "Soubor se změnil na disku a máš neuložené úpravy.",
                actions: [
                    ("Načíst verzi z disku", { [weak self] in self?.takeDiskVersion() }),
                    ("Ponechat moje úpravy", { [weak self] in self?.keepMyVersion() }),
                    ("Porovnat…", { [weak self] in self?.compareVersions() }),
                ]
            )
        } else if isEditing, let error = model.saveError {
            banner.show(
                symbol: "xmark.octagon.fill",
                message: "Uložení selhalo: \(error)",
                actions: [("Zkusit znovu", { [weak self] in self?.model.save(force: true) })]
            )
        } else {
            banner.hide()
        }
        container.needsLayout = true
    }

    func takeDiskVersion() {
        diffSheet = nil
        model.resolveConflictTakingDisk()
    }

    func keepMyVersion() {
        diffSheet = nil
        model.resolveConflictKeepingMine()
    }

    func compareVersions() {
        guard let editor, let window = view.window, diffSheet == nil else { return }
        let sheet = DiffSheet(disk: model.diskText, mine: editor.text, fileName: model.url.lastPathComponent) { [weak self] choice in
            guard let self else { return }
            self.diffSheet = nil
            switch choice {
            case .takeDisk: self.takeDiskVersion()
            case .keepMine: self.keepMyVersion()
            case .cancel: break
            }
        }
        diffSheet = sheet
        sheet.present(over: window)
    }

    // MARK: - Psaní a synchronizace posunu

    private func editorDidChange(_ text: String) {
        model.edit(text)
        // Psaní vrací vedení editoru – náhled ukáže místo, kde se píše.
        if !editorLeads, let editor {
            editorDidScroll(toLine: editor.topLine())
        }
    }

    private func editorDidScroll(toLine line: Double) {
        editorLeads = true
        pendingSyncLine = line
        guard !isSyncingPreview else { return }
        // Do webu jde vždy jen poslední pozice; scroll události chodí rychleji než odpovědi.
        isSyncingPreview = true
        Task {
            while let line = pendingSyncLine {
                pendingSyncLine = nil
                try? await call("mdv.syncToLine(line)", ["line": line])
            }
            isSyncingPreview = false
        }
    }

    /// Uživatel posouvá náhled (app.js hlásí jen posuny, které nezpůsobil editor).
    func previewDidScroll(toLine line: Double) {
        guard let editor else { return }
        editorLeads = false
        editor.scroll(toLine: line)
    }
}
