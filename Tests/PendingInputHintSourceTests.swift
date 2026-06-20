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
            source.contains("回复是/否，或直接写新任务"),
            "Pending confirmation placeholders should stay concise once the detailed decision semantics already live in the runtime cards."
        )
        XCTAssertTrue(
            source.contains("case .overwriteAgentFile:\n            return \"回复是/否，或直接写新任务\"\n        case .chooseExecutionModeForTask:\n            return \"回复是/否，或直接写新任务\""),
            "InputArea should reuse the same compact pending-reply placeholder across confirmation types instead of restating full decision copy in the bottom composer."
        )
        XCTAssertTrue(
            source.contains("if let pendingDecisionHint, pendingUserDecision == nil"),
            "Inline pending-decision hints should disappear once confirmation mode is active and the dedicated placeholder/confirmation block already explains the response options."
        )
        XCTAssertTrue(
            source.contains("提交回复或新任务 (回车)"),
            "Send button help should clarify pending-confirmation submissions."
        )
    }
}
