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
            source.contains("memory.deleteMemoryNote(id: pendingDeleteMemoryNote.id)"),
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
}
