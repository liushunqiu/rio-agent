import XCTest
@testable import RioAgent

@MainActor
final class AgentMemoryMarkdownTests: XCTestCase {
    func testMemoryMarkdownIsCreatedAndUpdatedFromVerifiedSignals() {
        let memory = AgentMemory()

        memory.clearAllMemory()
        let path = memory.memoryMarkdownPath()

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        memory.recordSuccessfulPattern(taskType: "code_fix", tool: "apply_patch")
        memory.learnFromCorrection(
            original: "直接覆盖整个文件",
            corrected: "优先使用 apply_patch 精确修改",
            reason: "更容易审计，且回归风险更低"
        )

        XCTAssertTrue(memory.persistedNotes.contains { $0.summary == "【摘要】任务类型 code_fix 优先使用 apply_patch" })
        XCTAssertTrue(memory.persistedNotes.contains { $0.summary == "【摘要】用户纠正：直接覆盖整个文件 应改为 优先使用 apply_patch 精确修改" })

        let content = memory.loadMemoryMarkdownContent()

        XCTAssertTrue(content.contains("【摘要】任务类型 code_fix 优先使用 apply_patch"))
        XCTAssertTrue(content.contains("【摘要】用户纠正：直接覆盖整个文件 应改为 优先使用 apply_patch 精确修改"))
    }

    func testGenerateMemoryContextIncludesVerifiedMemorySummariesOnly() {
        let memory = AgentMemory()

        memory.clearAllMemory()
        memory.recordSuccessfulPattern(taskType: "search", tool: "read_file")

        let context = memory.generateMemoryContext()

        XCTAssertTrue(context.contains("## Verified Memory Notes"))
        XCTAssertTrue(context.contains("【摘要】任务类型 search 优先使用 read_file"))
        XCTAssertFalse(context.contains("Why important"))
    }

    func testDeleteMemoryNoteRemovesOnlyTargetEntry() {
        let memory = AgentMemory()

        memory.clearAllMemory()
        memory.recordSuccessfulPattern(taskType: "search", tool: "read_file")
        memory.recordSuccessfulPattern(taskType: "edit", tool: "apply_patch")

        memory.deleteMemoryNote(summary: "【摘要】任务类型 search 优先使用 read_file")

        let notes = memory.loadMemoryNotes()
        XCTAssertFalse(notes.contains { $0.summary == "【摘要】任务类型 search 优先使用 read_file" })
        XCTAssertTrue(notes.contains { $0.summary == "【摘要】任务类型 edit 优先使用 apply_patch" })
        XCTAssertEqual(memory.persistedNotes, notes)
    }

    func testClearMemoryMarkdownRemovesPersistedNotes() {
        let memory = AgentMemory()

        memory.clearAllMemory()
        memory.recordSuccessfulPattern(taskType: "code_fix", tool: "apply_patch")
        XCTAssertFalse(memory.loadMemoryNotes().isEmpty)

        memory.clearMemoryMarkdown()

        XCTAssertTrue(memory.loadMemoryNotes().isEmpty)
        XCTAssertTrue(memory.persistedNotes.isEmpty)
        XCTAssertFalse(memory.loadMemoryMarkdownContent().contains("【摘要】"))
    }
}
