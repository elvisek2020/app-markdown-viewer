import FileWatch
import Foundation
import MarkdownCore

/// Obsah jednoho souboru: hlídá ho přes `FileWatcher` a renderuje na pozadí.
/// Starší rendery, které doběhnou pozdě, se zahodí (generation counter).
final class DocumentModel {
    enum FileState: Equatable {
        case present
        case deleted
    }

    private(set) var url: URL
    private(set) var rendered: RenderedDocument?
    private(set) var fileState: FileState = .present

    private var renderObservers: [(RenderedDocument) -> Void] = []
    private var fileStateObservers: [(FileState) -> Void] = []
    private var moveObservers: [(URL) -> Void] = []

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

    var options = Preferences.renderOptions(includeSource: false) {
        didSet {
            if options != oldValue { render(lastText) }
        }
    }

    /// Text posledního načtení souboru.
    var text: String { lastText }

    private var watcher: FileWatcher?
    private var lastText = ""
    private var generation = 0

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
        render(snapshot.text)
    }

    func stop() {
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
        render(String(decoding: data, as: UTF8.self))
    }

    private func handle(_ event: FileWatchEvent) {
        switch event {
        case .updated(let snapshot):
            setFileState(.present)
            render(snapshot.text)
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

    private func render(_ text: String) {
        lastText = text
        generation += 1
        let generation = generation
        let options = options
        Task.detached(priority: .userInitiated) {
            let document = MarkdownRenderer.render(text, options: options)
            await MainActor.run {
                guard generation == self.generation else { return }
                self.rendered = document
                self.renderObservers.forEach { $0(document) }
            }
        }
    }
}
