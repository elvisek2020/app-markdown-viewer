/// Řádkový rozdíl dvou textů (porovnání verze na disku s úpravami v editoru).
public enum LineDiff {
    public struct Line: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case same, removed, added
        }

        public let kind: Kind
        public let text: String
        /// Číslo řádku (od 1) ve starém, resp. novém textu.
        public let oldLine: Int?
        public let newLine: Int?
    }

    /// Souvislý úsek změn s okolním kontextem.
    public struct Hunk: Sendable, Equatable {
        public let lines: [Line]

        /// Hlavička ve stylu unified diffu: `@@ -start,count +start,count @@`.
        public var header: String {
            let old = lines.filter { $0.kind != .added }
            let new = lines.filter { $0.kind != .removed }
            func range(_ lines: [Line], _ number: (Line) -> Int?) -> String {
                let start = lines.first.flatMap(number) ?? 0
                return "\(start),\(lines.count)"
            }
            return "@@ -\(range(old, \.oldLine)) +\(range(new, \.newLine)) @@"
        }
    }

    /// Všechny řádky obou textů v pořadí unified diffu (odebrané před přidanými).
    public static func lines(from old: String, to new: String) -> [Line] {
        let oldLines = old.markdownLines().map(String.init)
        let newLines = new.markdownLines().map(String.init)
        let difference = newLines.difference(from: oldLines)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        // Řádky mimo odebrané (starý text) a mimo přidané (nový text) si odpovídají v pořadí.
        var result: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removed.contains(oldIndex) {
                result.append(Line(kind: .removed, text: oldLines[oldIndex], oldLine: oldIndex + 1, newLine: nil))
                oldIndex += 1
            } else if newIndex < newLines.count, inserted.contains(newIndex) {
                result.append(Line(kind: .added, text: newLines[newIndex], oldLine: nil, newLine: newIndex + 1))
                newIndex += 1
            } else {
                result.append(Line(kind: .same, text: oldLines[oldIndex], oldLine: oldIndex + 1, newLine: newIndex + 1))
                oldIndex += 1
                newIndex += 1
            }
        }
        return result
    }

    /// Změny seskupené do úseků s `context` řádky kontextu; stejné texty nemají žádný úsek.
    public static func hunks(from old: String, to new: String, context: Int = 3) -> [Hunk] {
        let all = lines(from: old, to: new)
        let changed = all.indices.filter { all[$0].kind != .same }
        guard let first = changed.first else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var current = max(0, first - context)...min(all.count - 1, first + context)
        for index in changed.dropFirst() {
            let range = max(0, index - context)...min(all.count - 1, index + context)
            if range.lowerBound <= current.upperBound + 1 {
                current = current.lowerBound...range.upperBound
            } else {
                ranges.append(current)
                current = range
            }
        }
        ranges.append(current)
        return ranges.map { Hunk(lines: Array(all[$0])) }
    }
}
