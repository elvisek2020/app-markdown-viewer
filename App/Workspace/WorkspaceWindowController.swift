import AppKit
import FileWatch
import MarkdownCore
import SwiftUI

/// Okno pracovní složky: strom Markdown souborů | náhled vybraného souboru.
/// Režim „Sledovat změny ve složce“ přepne náhled na soubor, který agent právě zapsal nebo vytvořil.
final class WorkspaceWindowController: NSWindowController, NSToolbarDelegate, NSMenuItemValidation {
    let folder: URL
    private let state = WorkspaceState()
    private let split = NSSplitViewController()
    private let content = NSViewController()
    private var folderWatcher: FolderWatcher?
    private var preview: PreviewController?
    private var model: DocumentModel?
    private var searchItem: NSSearchToolbarItem?
    private var sourceButton: NSButton?
    private var editButton: NSButton?
    private var followButton: NSButton?
    private var frameMemory: WindowFrameMemory?
    private var scanGeneration = 0
    private var hasInitialSelection = false
    private var pendingSelection: String?

    var selectedPath: String? { state.selectedPath }
    var isFollowing: Bool { state.isFollowing }

    init(folder: URL) {
        // Jednotná podoba cest: strom, FSEvents (/private/var…) i obnova se převádějí přes
        // resolvingSymlinksInPath, které /private odstraní – jinak by výběr ve stromu nesouhlasil.
        self.folder = folder.resolvingSymlinksInPath()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MDViewDocument"
        window.minSize = NSSize(width: 560, height: 320)
        window.toolbarStyle = .unified
        super.init(window: window)

        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000))
        let sidebarHost = NSHostingController(rootView: WorkspaceSidebar(state: state, rootName: folder.lastPathComponent))
        sidebarHost.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 480
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        if !Self.isSelfTest { split.splitView.autosaveName = "MDViewWorkspaceSplit" }
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 1000))

        let toolbar = NSToolbar(identifier: "MDViewWorkspaceToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        shouldCascadeWindows = false
        if let name = ToolbarItems.frameName("Workspace") {
            frameMemory = WindowFrameMemory(window: window, name: name)
        }

        // Až po aktualizaci SwiftUI seznamu – přepnutí může v režimu úprav otevřít modální dotaz.
        state.onSelect = { [weak self] path in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.select(path: path) }
            }
        }
        rescan()
        let watcher = FolderWatcher(root: self.folder, extensions: LinkPolicy.markdownExtensions) { [weak self] change in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.folderChanged(change) }
            }
        }
        watcher.start()
        folderWatcher = watcher
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    override func close() {
        folderWatcher?.stop()
        folderWatcher = nil
        if let model, model.isEditing { model.save(force: true) }
        model?.stop()
        super.close()
    }

    /// `false` = uživatel zrušil (konflikt nebo chyba ukládání v režimu úprav).
    func prepareToClose() -> Bool {
        preview?.prepareToLeaveEditing(cancellable: true) ?? true
    }

    /// Obnova po relaunchi (z `WorkspaceDocument.restoreState`).
    func restore(selection: String?, follow: Bool?) {
        if let follow { setFollowing(follow) }
        guard let selection else { return }
        if FileManager.default.fileExists(atPath: selection) {
            if state.nodes.isEmpty { pendingSelection = selection } else { select(path: selection) }
        }
    }

    private static var isSelfTest: Bool {
        #if DEBUG
        SelfTest.isActive
        #else
        false
        #endif
    }

    // MARK: - Strom

    private func rescan() {
        scanGeneration += 1
        let generation = scanGeneration
        let folder = folder
        Task.detached(priority: .userInitiated) {
            let nodes = FolderIndex.scan(folder, extensions: LinkPolicy.markdownExtensions)
            await MainActor.run { self.apply(nodes, generation: generation) }
        }
    }

    private func apply(_ nodes: [FolderNode], generation: Int) {
        guard generation == scanGeneration else { return }
        state.nodes = nodes
        let files = FolderIndex.files(in: nodes)
        state.fileCount = files.count
        state.recent = Array(files.sorted { $0.modified > $1.modified }.prefix(6))
        if !hasInitialSelection {
            hasInitialSelection = true
            let restored = pendingSelection.flatMap { path in files.first { $0.url.path == path } }
            // README v kořeni, jinak naposledy změněný soubor.
            let readme = nodes.first { !$0.isDirectory && $0.name.lowercased().hasPrefix("readme.") }
            if let initial = restored ?? readme ?? state.recent.first {
                select(path: initial.url.path)
            }
        }
        #if DEBUG
        WorkspaceSelfTest.treeUpdated(self, fileCount: files.count)
        #endif
    }

    private func folderChanged(_ change: FolderWatcher.Change) {
        rescan()
        // V režimu úprav sledování nepřepíná – editor nesmí uživateli zmizet pod rukama.
        guard state.isFollowing, !change.paths.isEmpty, preview?.isEditing != true else { return }
        // Agent mohl zapsat víc souborů najednou – vybrat naposledy změněný, který existuje.
        let candidates = change.paths.compactMap { path -> (String, Date)? in
            let url = URL(fileURLWithPath: path)
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            // FSEvents hlásí /private/var…, strom /var… – sjednotit přes resolvingSymlinksInPath.
            return (url.resolvingSymlinksInPath().path, date)
        }
        if let newest = candidates.max(by: { $0.1 < $1.1 })?.0, newest != state.selectedPath {
            select(path: newest)
        }
    }

    // MARK: - Výběr a náhled

    private func select(path rawPath: String) {
        let path = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
        guard path != state.selectedPath || preview == nil else { return }
        let wasEditing = preview?.isEditing ?? false
        if let old = preview, wasEditing, !old.prepareToLeaveEditing(cancellable: true) {
            // Zrušeno – vrátit výběr ve stromu na upravovaný soubor.
            let current = state.selectedPath
            state.selectedPath = current
            return
        }
        let url = URL(fileURLWithPath: path)
        let newModel = DocumentModel(url: url)
        do {
            try newModel.start()
        } catch {
            NSSound.beep()
            return
        }
        model?.stop()
        model = newModel
        state.selectedPath = path

        let newPreview = PreviewController(model: newModel)
        newPreview.onSourceVisibilityChange = { [weak self] visible in self?.sourceButton?.state = visible ? .on : .off }
        newPreview.onEditModeChange = { [weak self] editing in
            self?.editButton?.state = editing ? .on : .off
            self?.sourceButton?.isEnabled = !editing
        }
        if let old = preview {
            if old.isSourceVisible { newPreview.setSourceVisible(true) }
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        content.addChild(newPreview)
        newPreview.view.frame = content.view.bounds
        newPreview.view.autoresizingMask = [.width, .height]
        content.view.addSubview(newPreview.view)
        preview = newPreview
        ToolbarItems.connect(searchItem, to: newPreview)
        sourceButton?.state = newPreview.isSourceVisible ? .on : .off
        window?.makeFirstResponder(newPreview.webView)
        // Režim úprav pokračuje i v dalším vybraném souboru.
        if wasEditing { newPreview.beginEditing() }

        window?.title = folder.lastPathComponent
        window?.subtitle = relativePath(of: url)
        document?.invalidateRestorableState()
        #if DEBUG
        WorkspaceSelfTest.selectionChanged(self, path: path, model: newModel)
        #endif
    }

    private func relativePath(of url: URL) -> String {
        let root = folder.path + "/"
        let path = url.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }

    // MARK: - Sledování změn

    @objc func toggleFollowFolderChanges(_ sender: Any?) {
        setFollowing(!state.isFollowing)
    }

    func setFollowing(_ following: Bool) {
        state.isFollowing = following
        followButton?.state = following ? .on : .off
        document?.invalidateRestorableState()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFollowFolderChanges(_:)) {
            menuItem.state = state.isFollowing ? .on : .off
        }
        return true
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, ToolbarItems.follow, .flexibleSpace, ToolbarItems.appearance, ToolbarItems.edit, ToolbarItems.source, ToolbarItems.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItems.follow:
            let (item, button) = ToolbarItems.toggle(
                ToolbarItems.follow, symbol: "dot.radiowaves.left.and.right", label: "Sledovat",
                toolTip: "Sledovat změny ve složce – náhled se přepne na soubor, který se právě změnil (⇧⌘L)",
                action: #selector(toggleFollowFolderChanges(_:)), isOn: state.isFollowing
            )
            followButton = button
            return item
        case ToolbarItems.source:
            let (item, button) = ToolbarItems.sourceToggle(isOn: preview?.isSourceVisible ?? false)
            sourceButton = button
            return item
        case ToolbarItems.appearance:
            return AppearanceController.shared.makeToolbarItem(itemIdentifier)
        case ToolbarItems.edit:
            let (item, button) = ToolbarItems.editToggle(isOn: preview?.isEditing ?? false)
            editButton = button
            return item
        case ToolbarItems.search:
            let item = ToolbarItems.searchItem()
            searchItem = item
            if let preview { ToolbarItems.connect(item, to: preview) }
            return item
        default:
            return nil
        }
    }
}
