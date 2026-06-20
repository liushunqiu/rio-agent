import XCTest

final class MemoryNoteDeleteConfirmationSourceTests: XCTestCase {
    func testDeletingSingleMemoryNoteRequiresExplicitConfirmation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("@State private var pendingDeleteMemoryNote: AgentMemory.MemoryNote?"),
            "Settings should stage a memory note for deletion instead of deleting immediately from the row."
        )
        XCTAssertTrue(
            source.contains(".alert(\"删除记忆条目？\""),
            "Deleting an individual memory note should show a confirmation alert."
        )
        XCTAssertTrue(
            source.contains("deleteMemoryNoteConfirmationMessage"),
            "The confirmation should explain which memory note will be deleted."
        )
        XCTAssertTrue(
            source.contains("pendingDeleteMemoryNote.summary"),
            "The confirmation should include the note summary and delete that exact staged note."
        )
        XCTAssertTrue(
            source.contains("try memory.deleteMemoryNote(id: pendingDeleteMemoryNote.id)"),
            "Deleting a staged memory note should use its unique id so duplicate summaries do not remove multiple notes."
        )
        XCTAssertTrue(
            source.contains("这个操作无法撤销"),
            "The confirmation should explicitly warn that deletion is irreversible."
        )
        XCTAssertFalse(
            source.contains("Button(role: .destructive, action: onDelete)"),
            "MemoryNoteCard should not wire the destructive button directly to deletion."
        )
    }

    func testClearMemoryButtonIsDisabledWhenThereAreNoPersistedNotes() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(source.contains("private var canClearMemoryMarkdown: Bool"))
        XCTAssertTrue(source.contains("!memory.persistedNotes.isEmpty"))
        XCTAssertTrue(source.contains(".disabled(!canClearMemoryMarkdown)"))
        XCTAssertTrue(source.contains(".help(clearMemoryMarkdownHelpText)"))
        XCTAssertTrue(
            source.contains("当前没有可清空的持久化记忆"),
            "The disabled destructive action should explain the empty-state reason on hover."
        )
    }

    func testMemoryManagementActionsUseIconLabelsAndHoverHelp() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(source.contains("Label(\"刷新\", systemImage: \"arrow.clockwise\")"))
        XCTAssertTrue(source.contains(".help(\"重新读取 MEMORY.md\")"))
        XCTAssertTrue(source.contains("Label(\"清空 MEMORY.md\", systemImage: \"trash\")"))
        XCTAssertTrue(source.contains(".help(\"删除记忆条目\")"))
    }

    func testMemoryWriteFailuresAreVisibleInSettings() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))
        let memorySource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentMemory.swift"))

        XCTAssertTrue(
            memorySource.contains("func deleteMemoryNote(id: String) throws")
                && memorySource.contains("func clearMemoryMarkdown() throws")
                && memorySource.contains("private func saveMemoryNotes(_ notes: [MemoryNote]) throws"),
            "Manual MEMORY.md delete and clear operations should surface write failures instead of only logging them."
        )
        XCTAssertTrue(
            settingsSource.contains("@State private var memoryOperationErrorMessage: String?")
                && settingsSource.contains(".alert(\"MEMORY.md 操作失败\", isPresented: memoryOperationErrorBinding)"),
            "Settings should keep and show a visible MEMORY.md operation error."
        )
        XCTAssertTrue(
            settingsSource.contains("try memory.clearMemoryMarkdown()")
                && settingsSource.contains("try memory.deleteMemoryNote(id: pendingDeleteMemoryNote.id)")
                && settingsSource.contains("memoryOperationErrorMessage = memoryOperationErrorMessage(for: error)"),
            "Clear and delete actions should catch MEMORY.md write failures and present them to the user."
        )
        XCTAssertTrue(
            settingsSource.contains("无法写入 MEMORY.md：\\(error.localizedDescription)"),
            "The visible error should identify MEMORY.md as the failing storage target."
        )
    }
}
