import XCTest

final class TaskPlanViewSourceTests: XCTestCase {
    func testSubTaskRowsShowVisibleResultReasonsForFailureAndCancellation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/TaskPlanView.swift"))

        XCTAssertTrue(
            source.contains("case .failed: return \"失败原因\""),
            "Failed Multi-Agent sub-tasks should show their result as a visible failure reason, not only as hover text."
        )
        XCTAssertTrue(
            source.contains("case .cancelled: return \"停止原因\""),
            "Cancelled Multi-Agent sub-tasks should show a visible stop reason."
        )
        XCTAssertTrue(
            source.contains(".textSelection(.enabled)"),
            "Visible sub-task result text should be selectable so users can copy exact errors."
        )
        XCTAssertTrue(
            source.contains("subTask.status == .failed ? nil : 3"),
            "Failure reasons should not be truncated in the task plan card."
        )
        XCTAssertTrue(
            source.contains("title: \"待处理\""),
            "Task plan metrics should surface how many sub-tasks still need human attention."
        )
        XCTAssertTrue(
            source.contains("title: \"待验证\""),
            "Task plan metrics should surface how many sub-tasks are still missing verification evidence."
        )
        XCTAssertTrue(
            source.contains("private var unverifiedCount: Int"),
            "Task plan should compute a dedicated unverified count instead of hiding that state inside row-level details."
        )
        XCTAssertTrue(
            source.contains("plan.subTasks.filter(\\.needsAttention).count"),
            "Task plan attention metrics should use the shared SubTask attention state instead of re-implementing partial rules."
        )
        XCTAssertTrue(
            source.contains("private var attentionSummary: String?"),
            "Sub-task rows should derive a visible attention summary from structured recovery context."
        )
        XCTAssertTrue(
            source.contains("private var nextAttentionSummary: String?"),
            "The task plan card should provide a card-level next-action summary instead of only showing per-row attention states."
        )
        XCTAssertTrue(
            source.contains("Text(\"优先处理\")"),
            "The task plan should surface a prominent next-action callout when some sub-task needs attention."
        )
        XCTAssertTrue(
            source.contains("return \"先处理失败子任务"),
            "Failed sub-tasks should become the first recommended recovery action."
        )
        XCTAssertTrue(
            source.contains("还缺少完成证据，建议优先补充读回、测试或命令验证"),
            "Unverified sub-tasks should surface a concrete follow-up instead of reading like a passive completed state."
        )
        XCTAssertTrue(
            source.contains("return \"子任务“\\(blockedSubTask.description)”还没有可执行 Worker"),
            "Missing worker assignment should become an explicit top-level recovery instruction."
        )
        XCTAssertTrue(
            source.contains("recoveryActionDetail"),
            "Structured recovery context should point to a concrete settings destination instead of only describing the failure abstractly."
        )
        XCTAssertTrue(
            source.contains("case .unverified: return Theme.statusWarning"),
            "Unverified verification state should use warning tone in the task plan so it is not mistaken for a neutral or finished state."
        )
        XCTAssertTrue(
            source.contains("private var verificationSummaryColor: Color"),
            "Verification summaries should have their own tone mapping instead of always falling back to tertiary text."
        )
    }
}
