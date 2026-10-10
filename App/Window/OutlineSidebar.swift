import MarkdownCore
import Observation
import SwiftUI

/// Stav osnovy jednoho okna: nadpisy z posledního renderu a první viditelný řádek náhledu.
@Observable
final class OutlineState {
    var items: [OutlineItem] = []
    var currentLine = 1
    @ObservationIgnored var onSelect: (OutlineItem) -> Void = { _ in }

    /// Aktuální sekce = poslední nadpis nad prvním viditelným řádkem.
    var currentID: OutlineItem.ID? {
        items.last { $0.line <= currentLine }?.id ?? items.first?.id
    }
}

/// Osnova dokumentu v postranním panelu. Klik skočí na nadpis, při scrollu se zvýrazňuje aktuální sekce.
struct OutlineSidebar: View {
    let state: OutlineState

    private var minimumLevel: Int {
        state.items.map(\.level).min() ?? 1
    }

    var body: some View {
        if state.items.isEmpty {
            ContentUnavailableView("Bez nadpisů", systemImage: "list.bullet.indent")
        } else {
            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { state.currentID },
                    set: { id in
                        if let item = state.items.first(where: { $0.id == id }) { state.onSelect(item) }
                    }
                )) {
                    ForEach(state.items) { item in
                        Text(item.title.isEmpty ? "(bez názvu)" : item.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(item.level == minimumLevel ? .body.weight(.semibold) : .body)
                            .padding(.leading, CGFloat(item.level - minimumLevel) * 12)
                            .help(item.title)
                            .tag(item.id)
                            .id(item.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: state.currentID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }
}
