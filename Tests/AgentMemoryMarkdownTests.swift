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

    func testDeleteMemoryNoteByIDRemovesOnlyOneDuplicateSummary() throws {
        let memory = AgentMemory()

        memory.clearAllMemory()
        let content = """
        # Agent Memory

        只记录经过验证的正确做法、用户纠错和重要原因。不要记录代码库里已经存在的内容，不要记录纯会话噪音。

        ## Note
        【摘要】重复经验
        - 第一条

        ## Note
        【摘要】重复经验
        - 第二条
        """
        try content.write(toFile: memory.memoryMarkdownPath(), atomically: true, encoding: .utf8)
        memory.refreshPersistedNotes()

        let duplicateNotes = memory.persistedNotes.filter { $0.summary == "【摘要】重复经验" }
        XCTAssertEqual(duplicateNotes.count, 2)
        XCTAssertEqual(Set(duplicateNotes.map(\.id)).count, 2)

        memory.deleteMemoryNote(id: duplicateNotes[0].id)

        let remainingDuplicates = memory.persistedNotes.filter { $0.summary == "【摘要】重复经验" }
        XCTAssertEqual(remainingDuplicates.count, 1)
        XCTAssertNotEqual(remainingDuplicates.first?.id, duplicateNotes[0].id)
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
