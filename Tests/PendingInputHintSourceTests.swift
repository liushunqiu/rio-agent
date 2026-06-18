import XCTest

final class PendingInputHintSourceTests: XCTestCase {
    func testInputAreaExplainsPendingDecisionResponses() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("TextField(inputPlaceholder"),
            "InputArea should use a dynamic placeholder instead of the normal task placeholder while waiting for confirmation."
        )
        XCTAssertTrue(
            source.contains("输入“是”覆盖，输入“否”取消，或直接写新任务"),
            "Overwrite confirmation should tell the user exactly how yes/no/new-task input will be interpreted."
        )
        XCTAssertTrue(
            source.contains("输入“是”用 Multi-Agent，输入“否”改单 Agent，或直接写新任务"),
            "Execution-mode confirmation should tell the user how to choose the mode or start a new task."
        )
        XCTAssertTrue(
            source.contains("提交回复或新任务 (Cmd+Return)"),
            "Send button help should clarify pending-confirmation submissions."
        )
    }
}
