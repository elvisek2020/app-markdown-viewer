import FileWatch
import Observation
import SwiftUI

/// Stav postranního panelu pracovní složky.
@Observable
final class WorkspaceState {
    var nodes: [FolderNode] = []
    var recent: [FolderNode] = []
    var selectedPath: String?
    var isFollowing = false
    var fileCount = 0
    @ObservationIgnored var onSelect: (String) -> Void = { _ in }
}

/// Strom Markdown souborů složky a naposledy změněné soubory. Výběr zobrazí soubor v náhledu.
struct WorkspaceSidebar: View {
    let state: WorkspaceState
    let rootName: String

    var body: some View {
        if state.nodes.isEmpty {
            ContentUnavailableView("Žádné Markdown soubory", systemImage: "doc.text.magnifyingglass")
        } else {
            List(selection: Binding(
                get: { state.selectedPath },
                set: { tag in
                    // Řádky „Naposledy změněné“ mají tag s prefixem, aby se nebily se stromem.
                    guard let tag else { return }
                    state.onSelect(tag.hasPrefix("recent:") ? String(tag.dropFirst("recent:".count)) : tag)
                }
            )) {
                if !state.recent.isEmpty {
                    Section("Naposledy změněné") {
                        ForEach(state.recent) { node in
                            row(node, showFolder: true)
                                .tag("recent:" + node.id)
                        }
                    }
                }
                Section(rootName) {
                    OutlineGroup(state.nodes, children: \.children) { node in
                        row(node, showFolder: false)
                            .tag(node.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func row(_ node: FolderNode, showFolder: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                if showFolder {
                    Text(node.modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
        }
        .help(node.url.path)
    }
}
