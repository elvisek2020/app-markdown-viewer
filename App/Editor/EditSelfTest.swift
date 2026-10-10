#if DEBUG
import AppKit
import WebKit

/// Self-test režimu úprav (`scripts/selftest-edit.sh`, jen soubory v /tmp): psaní se hned ukáže
/// v náhledu a samo uloží bez reloadu editoru, změna od agenta bez neuložených úprav se tiše načte,
/// s neuloženými úpravami vznikne konflikt (banner, porovnání, obě volby), synchronizace posunu.
/// `-MDViewSelfTestEditSnapshot cesta.png` uloží snímek okna s bannerem konfliktu.
enum EditSelfTest {
    static var reportPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestEditReport") }
    static var snapshotPath: String? { UserDefaults.standard.string(forKey: "MDViewSelfTestEditSnapshot") }

    private final class Counter {
        var value = 0
    }

    @MainActor
    static func run() {
        guard let reportPath else { return }
        Task {
            var report: [String: Any] = [:]
            guard let window = await documentWindow(),
                  let preview = (window.windowController as? DocumentWindowController)?.preview else {
                finish(["error": "okno dokumentu se neotevřelo"], to: reportPath)
                return
            }
            let url = preview.model.url
            guard url.path.hasPrefix("/tmp/") || url.path.hasPrefix("/private/tmp/") else {
                finish(["error": "self-test zapisuje jen do /tmp"], to: reportPath)
                return
            }
            _ = await waitUntil { preview.hasContent }
            let reloads = Counter()
            preview.model.observeReload { _ in reloads.value += 1 }
            func disk() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
            func agentWrites(_ text: String) { try? text.write(to: url, atomically: true, encoding: .utf8) }
            func previewContains(_ text: String) async -> Bool {
                await preview.callString("return String(document.getElementById('mdv-content').textContent.includes(text))", ["text": text]) == "true"
            }

            // 1. Zapnutí režimu úprav
            preview.toggleEditMode(nil)
            guard let editor = preview.editor else {
                finish(["error": "editor se nevytvořil"], to: reportPath)
                return
            }
            report["editing"] = preview.isEditing
            report["editorFocused"] = window.firstResponder === editor.textView
            report["sourcePaneHidden"] = await preview.callString("return String(document.body.classList.contains('mdv-with-source'))") == "false"
            let modeControl = window.toolbar?.items.first { $0.itemIdentifier == ToolbarItems.mode }?.view as? NSSegmentedControl
            @MainActor func segments() -> [Bool] {
                guard let modeControl else { return [] }
                return [modeControl.isSelected(forSegment: 0), modeControl.isSelected(forSegment: 1)]
            }
            report["switchShowsEdit"] = segments() == [false, true]
            report["editTint"] = window.titlebarAppearsTransparent

            // 2. Synchronizace posunu editor → náhled a náhled → editor
            try? await Task.sleep(for: .milliseconds(300))
            editor.scroll(toLine: 100)
            editor.onScroll?(editor.topLine())
            try? await Task.sleep(for: .milliseconds(300))
            report["syncEditorLine"] = (editor.topLine() * 10).rounded() / 10
            report["syncPreviewLine"] = Double(await preview.callString("return String(mdv.previewLine())") ?? "") ?? -1
            preview.previewDidScroll(toLine: 150)
            report["syncBackEditorLine"] = (editor.topLine() * 10).rounded() / 10

            // 3. Psaní: náhled hned, uložení po chvíli, vlastní zápis editor nepřenačte
            let typed = "\n\nNapsáno v editoru.\n"
            type(typed, into: editor, at: (editor.text as NSString).length)
            report["previewLive"] = await waitUntil(timeout: 1) { await previewContains("Napsáno v editoru.") }
            report["notSavedImmediately"] = !disk().contains("Napsáno v editoru.")
            report["autosaved"] = await waitUntil(timeout: 3) { disk().contains("Napsáno v editoru.") }
            try? await Task.sleep(for: .milliseconds(800))
            report["ownWriteIgnored"] = reloads.value == 0 && container(preview).banner.isHidden && editor.text == disk()

            // ⌘S a ⌥⌘E z editoru dojdou do náhledu (ne do NSDocumentu); ⌘S uloží hned.
            report["commandsRouteToPreview"] = [#selector(PreviewController.saveDocument(_:)), #selector(PreviewController.toggleEditMode(_:))]
                .allSatisfy { target(of: $0, from: editor.textView) === preview }
            type("Uloženo přes ⌘S.\n", into: editor, at: (editor.text as NSString).length)
            // Stejný selektor jako položka menu Uložit, z editoru přes responder chain.
            editor.textView.tryToPerform(#selector(NSDocument.save(_:)), with: nil)
            report["saveCommand"] = disk().contains("Uloženo přes ⌘S.")

            // Zpět, schránka a uložení mají položky menu se zkratkou (jinak je NSTextView nedostane).
            func items(_ menu: NSMenu?) -> [NSMenuItem] {
                (menu?.items ?? []).flatMap { [$0] + items($0.submenu) }
            }
            let menuItems = items(NSApp.mainMenu)
            let missing = ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "saveDocument:"].filter { action in
                !menuItems.contains { $0.action == Selector(action) && !$0.keyEquivalent.isEmpty }
            }
            report["editMenu"] = missing.isEmpty ? true : missing.joined(separator: " ")
            // Zpět vrátí jen psaní od posledního uložení (uložení přeruší slučování psaní v NSTextView).
            try? await Task.sleep(for: .milliseconds(100))
            // Souvisle za text napsaný před uložením – bez přerušení by ho NSTextView sloučil.
            type("Tohle se vrátí.", into: editor, at: (editor.text as NSString).length)
            try? await Task.sleep(for: .milliseconds(100))
            report["undoGroupClosed"] = editor.textView.undoManager?.groupingLevel == 0
            editor.textView.undoManager?.undo()
            report["undo"] = editor.text == disk() && preview.model.text == disk()

            // 4. Agent zapíše bez neuložených úprav → tiché načtení, kurzor zůstane
            editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
            agentWrites(disk() + "\n## Od agenta\n\nZměna od agenta.\n")
            report["silentReload"] = await waitUntil { editor.text.contains("Změna od agenta.") }
            report["silentReloadNoBanner"] = container(preview).banner.isHidden
            report["caretKept"] = editor.textView.selectedRange().location == 5
            report["reloadPreview"] = await waitUntil(timeout: 1) { await previewContains("Změna od agenta.") }

            // 5. Konflikt: rozepsáno + agent zapíše → banner, soubor se nepřepíše
            type("\nMoje rozepsaná věta.\n", into: editor, at: (editor.text as NSString).length)
            agentWrites(disk() + "\nAgent mezitím připsal.\n")
            report["conflict"] = await waitUntil { preview.model.hasConflict }
            report["conflictBanner"] = container(preview).banner.isHidden ? "" : container(preview).banner.message
            try? await Task.sleep(for: .milliseconds(1500))
            report["conflictNoOverwrite"] = disk().contains("Agent mezitím připsal.") && !disk().contains("Moje rozepsaná věta.")
            report["conflictPreviewShowsMine"] = await previewContains("Moje rozepsaná věta.")
            if let snapshotPath { await snapshot(window, preview: preview, to: snapshotPath) }
            preview.compareVersions()
            report["diffSheet"] = window.attachedSheet != nil
            preview.diffSheet?.dismiss()
            container(preview).banner.perform(1)  // Ponechat moje úpravy
            report["keptMine"] = disk().contains("Moje rozepsaná věta.") && !disk().contains("Agent mezitím připsal.")
                && !preview.model.hasConflict && container(preview).banner.isHidden

            // 6. Druhý konflikt → Načíst verzi z disku
            try? await Task.sleep(for: .milliseconds(500))
            type("Druhá rozepsaná věta.", into: editor, at: 0)
            let agentText = "# Agent přepsal\n\nNový obsah od agenta.\n"
            agentWrites(agentText)
            report["conflict2"] = await waitUntil { preview.model.hasConflict }
            container(preview).banner.perform(0)  // Načíst verzi z disku
            report["tookDisk"] = editor.text == agentText && disk() == agentText && !preview.model.hasConflict
            report["tookDiskPreview"] = await waitUntil(timeout: 1) { await previewContains("Nový obsah od agenta.") }

            // 7. Vypnutí režimu úprav uloží rozepsané
            type("Poslední úprava.\n", into: editor, at: 0)
            preview.toggleEditMode(nil)
            report["finished"] = !preview.isEditing && preview.editor == nil && !container(preview).isEditorVisible
            report["savedOnFinish"] = disk().hasPrefix("Poslední úprava.\n# Agent přepsal")

            // 8. Přepínač Zdroj | Upravit: klik na druhý režim přepne rovnou, klik na zapnutý ho vypne.
            @MainActor func click(_ segment: Int) {
                guard let modeControl else { return }
                modeControl.setSelected(!modeControl.isSelected(forSegment: segment), forSegment: segment)
                modeControl.sendAction(modeControl.action, to: modeControl.target)
            }
            func sourceShown() async -> Bool {
                await preview.callString("return String(document.body.classList.contains('mdv-with-source'))") == "true"
            }
            click(1)
            report["clickEdit"] = preview.paneMode == .edit && segments() == [false, true] && window.titlebarAppearsTransparent
            click(0)
            let sourceAppeared = await waitUntil(timeout: 1) { await sourceShown() }
            report["clickSourceWhileEditing"] = preview.paneMode == .source && preview.editor == nil && segments() == [true, false]
                && !window.titlebarAppearsTransparent && sourceAppeared
            click(1)
            let sourceHidden = await waitUntil(timeout: 1) { !(await sourceShown()) }
            report["clickEditWhileSource"] = preview.paneMode == .edit && preview.editor != nil && segments() == [false, true]
                && sourceHidden
            click(1)
            report["clickEditOff"] = preview.paneMode == .preview && segments() == [false, false] && !window.titlebarAppearsTransparent
            finish(report, to: reportPath)
        }
    }

    /// Psaní jako z klávesnice (přes NSTextView, takže projde delegátem jako uživatelský vstup).
    @MainActor
    private static func type(_ text: String, into editor: MarkdownEditor, at location: Int) {
        editor.textView.setSelectedRange(NSRange(location: location, length: 0))
        editor.textView.insertText(text, replacementRange: NSRange(location: location, length: 0))
        // Skupinu zpět zavírá AppKit po zpracování každé události; self-test jinak žádné události nemá.
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Snímek celého okna (lišta, banner, editor) vykreslený aplikací; obsah WKWebView se do
    /// `cacheDisplay` nekreslí, proto se dokreslí z jeho vlastního snímku.
    @MainActor
    private static func snapshot(_ window: NSWindow, preview: PreviewController, to path: String) async {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let web = try? await preview.webView.takeSnapshot(configuration: WKSnapshotConfiguration()),
           let context = NSGraphicsContext(bitmapImageRep: rep) {
            var frame = preview.webView.convert(preview.webView.bounds, to: frameView)
            if frameView.isFlipped { frame.origin.y = frameView.bounds.height - frame.maxY }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            web.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// První objekt v responder chainu od `responder`, který akci obslouží.
    @MainActor
    private static func target(of action: Selector, from responder: NSResponder) -> NSResponder? {
        var current: NSResponder? = responder
        while let candidate = current {
            if candidate.responds(to: action) { return candidate }
            current = candidate.nextResponder
        }
        return nil
    }

    @MainActor
    private static func container(_ preview: PreviewController) -> PreviewContainerView {
        preview.container
    }

    @MainActor
    private static func waitUntil(timeout: Double = 3, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @MainActor
    private static func documentWindow() async -> NSWindow? {
        for _ in 0..<50 {
            if let window = NSApp.windows.first(where: { $0.windowController is DocumentWindowController && $0.isVisible }) {
                return window
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor
    private static func finish(_ report: [String: Any], to path: String) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
#endif
