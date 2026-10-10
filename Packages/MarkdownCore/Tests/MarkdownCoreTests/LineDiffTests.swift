import Testing
@testable import MarkdownCore

@Suite("Řádkový rozdíl")
struct LineDiffTests {
    @Test func identicalTextsHaveNoHunks() {
        #expect(LineDiff.hunks(from: "a\nb\n", to: "a\nb\n").isEmpty)
    }

    @Test func changedLineIsRemovedThenAdded() {
        let lines = LineDiff.lines(from: "a\nb\nc", to: "a\nB\nc")
        #expect(lines.map(\.kind) == [.same, .removed, .added, .same])
        #expect(lines[1] == LineDiff.Line(kind: .removed, text: "b", oldLine: 2, newLine: nil))
        #expect(lines[2] == LineDiff.Line(kind: .added, text: "B", oldLine: nil, newLine: 2))
        #expect(lines[3].oldLine == 3 && lines[3].newLine == 3)
    }

    @Test func crlfAndLfCompareEqual() {
        #expect(LineDiff.hunks(from: "a\r\nb\r\n", to: "a\nb\n").isEmpty)
    }

    @Test func hunksKeepContextAndSplitDistantChanges() {
        let old = (1...20).map { "řádek \($0)" }.joined(separator: "\n")
        var lines = old.components(separatedBy: "\n")
        lines[1] = "změna 2"
        lines[17] = "změna 18"
        let hunks = LineDiff.hunks(from: old, to: lines.joined(separator: "\n"), context: 2)
        #expect(hunks.count == 2)
        #expect(hunks[0].header == "@@ -1,4 +1,4 @@")
        #expect(hunks[0].lines.first?.text == "řádek 1")
        #expect(hunks[1].header == "@@ -16,5 +16,5 @@")
        #expect(hunks[1].lines.last?.text == "řádek 20")
    }

    @Test func nearbyChangesMergeIntoOneHunk() {
        let old = (1...10).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "3", with: "x").replacingOccurrences(of: "6", with: "y")
        #expect(LineDiff.hunks(from: old, to: new, context: 1).count == 1)
    }

    @Test func appendedLines() {
        let lines = LineDiff.lines(from: "a", to: "a\nb\nc")
        #expect(lines.map(\.kind) == [.same, .added, .added])
        #expect(lines.last?.newLine == 3)
    }
}
