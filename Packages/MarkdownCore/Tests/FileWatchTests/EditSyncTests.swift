import Testing
@testable import FileWatch

@Suite("Režim úprav: disk ↔ editor")
struct EditSyncTests {
    @Test func withoutEditingEveryChangeReloads() {
        var sync = EditSync(text: "a")
        #expect(sync.diskDidChange("b") == .reloaded("b"))
        #expect(sync.text == "b")
        #expect(sync.diskDidChange("b") == .ignored)
        #expect(sync.pendingSave == nil)
    }

    @Test func editAndSave() {
        var sync = EditSync(text: "a")
        #expect(sync.beginEditing() == "a")
        #expect(sync.pendingSave == nil)
        sync.edit("ab")
        #expect(sync.hasUnsavedChanges)
        #expect(sync.text == "ab")
        #expect(sync.pendingSave == "ab")
        sync.didSave("ab")
        #expect(!sync.hasUnsavedChanges)
        #expect(sync.pendingSave == nil)
        #expect(sync.disk == "ab")
    }

    @Test func ownWriteEchoIsIgnoredEvenWhenLate() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("ab")
        sync.didSave("ab")
        sync.edit("abc")
        sync.didSave("abc")
        sync.edit("abcd")
        // Watcher hlásí zápisy se zpožděním a mimo pořadí uložení editoru.
        #expect(sync.diskDidChange("ab") == .ignored)
        #expect(sync.diskDidChange("abc") == .ignored)
        #expect(sync.buffer == "abcd")
        #expect(sync.pendingSave == "abcd")
        #expect(!sync.hasConflict)
    }

    @Test func externalChangeWithoutUnsavedEditsReloadsEditor() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("ab")
        sync.didSave("ab")
        #expect(sync.diskDidChange("agent") == .reloaded("agent"))
        #expect(sync.buffer == "agent")
        #expect(!sync.hasConflict)
        #expect(sync.pendingSave == nil)
    }

    @Test func externalChangeWithUnsavedEditsIsConflict() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("moje")
        #expect(sync.diskDidChange("agent") == .conflict)
        #expect(sync.hasConflict)
        #expect(sync.pendingSave == nil)
        #expect(sync.text == "moje")
        // Další zápis agenta konflikt jen aktualizuje.
        #expect(sync.diskDidChange("agent 2") == .conflict)
        #expect(sync.disk == "agent 2")
        // Psaní konflikt neukončí.
        sync.edit("moje 2")
        #expect(sync.hasConflict)
    }

    @Test func resolveKeepingMineSavesBuffer() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("moje")
        _ = sync.diskDidChange("agent")
        sync.resolveKeepingMine()
        #expect(!sync.hasConflict)
        #expect(sync.pendingSave == "moje")
    }

    @Test func resolveTakingDiskDiscardsBuffer() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("moje")
        _ = sync.diskDidChange("agent")
        sync.resolveTakingDisk()
        #expect(!sync.hasConflict)
        #expect(sync.buffer == "agent")
        #expect(sync.pendingSave == nil)
    }

    @Test func agentWritingSameTextAsEditorIsNotConflict() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("b")
        #expect(sync.diskDidChange("b") == .ignored)
        #expect(!sync.hasConflict)
        #expect(!sync.hasUnsavedChanges)
    }

    @Test func endEditingFallsBackToDisk() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("moje")
        _ = sync.diskDidChange("agent")
        sync.endEditing()
        #expect(!sync.isEditing)
        #expect(!sync.hasConflict)
        #expect(sync.text == "agent")
        #expect(sync.diskDidChange("agent 2") == .reloaded("agent 2"))
    }

    @Test func caughtUpWatcherForgetsOwnWrites() {
        var sync = EditSync(text: "a")
        _ = sync.beginEditing()
        sync.edit("b")
        sync.didSave("b")
        #expect(sync.diskDidChange("b") == .ignored)
        // Agent vrátí soubor na starší vlastní verzi – už to není ozvěna vlastního zápisu.
        sync.edit("c")
        sync.didSave("c")
        #expect(sync.diskDidChange("c") == .ignored)
        #expect(sync.diskDidChange("b") == .reloaded("b"))
    }
}
