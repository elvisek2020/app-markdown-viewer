import AppKit

/// Hledání v náhledu: pole v nástrojové liště → `mdv.find` (CSS Custom Highlight API).
/// Enter = další výsledek, ⇧Enter = předchozí, Esc = zrušit. Počet výsledků ukazuje náhled.
/// Editor přes celé okno náhled zakrývá, proto se hledá přímo v něm.
extension PreviewController: NSSearchFieldDelegate {
    /// Editor, ve kterém se má hledat místo v náhledu.
    private var findEditor: MarkdownEditor? { editsFullWindow ? editor : nil }

    @objc func findInDocument(_ sender: Any?) {
        searchItem?.beginSearchInteraction()
    }

    @objc func findNextMatch(_ sender: Any?) {
        findStep(1)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        findStep(-1)
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        if let findEditor {
            let text = (findEditor.text as NSString).substring(with: findEditor.textView.selectedRange())
            guard !text.isEmpty else { return }
            searchField?.stringValue = text
            startFind(text)
            return
        }
        Task {
            guard let text = await callString("return mdv.selectionText()"), !text.isEmpty else { return }
            searchField?.stringValue = text
            await runFind(text)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        startFind(searchField?.stringValue ?? "")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            findStep(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            searchField?.stringValue = ""
            startFind("")
            view.window?.makeFirstResponder(findEditor?.textView ?? webView)
            return true
        default:
            return false
        }
    }

    /// Spustí hledání a vrátí počet výsledků (používá i self-test).
    @discardableResult
    func runFind(_ query: String) async -> Int {
        let options: [String: Any] = ["ignoreDiacritics": Preferences.ignoreDiacritics, "matchCase": false]
        let json = await callString(
            "return JSON.stringify(mdv.find(query, options))",
            ["query": query, "options": options]
        )
        guard let data = json?.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return result["count"] as? Int ?? 0
    }

    private func startFind(_ query: String) {
        if let findEditor {
            findEditor.find(query, ignoreDiacritics: Preferences.ignoreDiacritics)
            return
        }
        Task { await runFind(query) }
    }

    private func findStep(_ delta: Int) {
        if let findEditor {
            findEditor.findStep(delta)
            return
        }
        Task { try? await call("mdv.findStep(delta)", ["delta": delta]) }
    }
}
