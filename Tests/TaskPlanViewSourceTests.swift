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
            source.contains("Text(summaryBannerTitle)"),
            "The task plan should surface an action-first summary banner that can adapt to failures, blocked work, and verification follow-ups."
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
            source.contains("plan.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })"),
            "Task-plan recovery guidance should prioritize any blocked sub-task that already exposes structured recovery context."
        )
        XCTAssertTrue(
            source.contains("return \"子任务“\\(blockedSubTask.description)”当前受阻，先\\(recoveryContext.recoveryActionDetail)\""),
            "Blocked task-plan summaries should route users through the same structured recovery action detail used elsewhere in runtime chrome."
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
        XCTAssertTrue(
            source.contains("SubTaskMetaPill("),
            "Sub-task rows should use compact meta pills so status and verification state remain scannable."
        )
        XCTAssertTrue(
            source.contains("private var shouldShowRunningMetric: Bool"),
            "Running-count metrics should disappear once a completed plan is already in closeout mode."
        )
        XCTAssertTrue(
            source.contains("private var shouldShowVerifiedMetric: Bool"),
            "Verified-count metrics should stay out of the way when unfinished verification work is still the more important state."
        )
        XCTAssertTrue(
            source.contains("text: statusDisplayText"),
            "Sub-task rows should expose a visible status pill instead of relying only on the leading icon."
        )
        XCTAssertTrue(
            source.contains("text: subTask.verificationStatus.displayText"),
            "Sub-task rows should expose a visible verification-state pill for fast scanning."
        )
        XCTAssertTrue(
            source.contains("text: \"需关注\""),
            "Rows that need follow-up should show an explicit attention pill."
        )
        XCTAssertTrue(
            source.contains(".help(subTask.description)"),
            "Long sub-task descriptions should provide hover help so truncation does not hide the full task."
        )
        XCTAssertTrue(
            source.contains(".help(worker.model)"),
            "Worker model identifiers should remain accessible when truncated in the row."
        )
        XCTAssertTrue(
            source.contains(".help(reason)"),
            "Assignment reasons should provide hover help when line-clamped."
        )
        XCTAssertTrue(
            source.contains(".help(attentionSummary)"),
            "Attention summaries should keep the full structured recovery guidance accessible."
        )
        XCTAssertTrue(
            source.contains(".help(summary)"),
            "Verification summaries should keep the full evidence guidance accessible."
        )
        XCTAssertTrue(
            source.contains(".help(resultText)"),
            "Sub-task result text should provide hover help in addition to visible inline content."
        )
        XCTAssertTrue(
            source.contains(".background(rowTone.opacity(0.08))"),
            "Sub-task rows should use row-level tone to make critical states stand out in a dense plan."
        )
        XCTAssertTrue(
            source.contains(".stroke(rowTone.opacity(0.18), lineWidth: 1)"),
            "Sub-task rows should keep a visible outline tied to row tone for scanability."
        )
        XCTAssertTrue(
            source.contains("private var statusDisplayText: String"),
            "Sub-task rows should derive explicit status text instead of exposing only iconography."
        )
        XCTAssertTrue(
            source.contains("private var rowTone: Color"),
            "Sub-task rows should derive a consistent visual tone from task state."
        )
        XCTAssertTrue(
            source.contains("@State private var showAllSubTasks = false"),
            "Task-plan cards should manage an explicit expanded state instead of always rendering every stable sub-task at once."
        )
        XCTAssertTrue(
            source.contains("private var highlightedSubTasks: [SubTask]"),
            "Task plans should prioritize active, attention-needed, and unverified sub-tasks before stable ones."
        )
        XCTAssertTrue(
            source.contains("subTask.status == .running || subTask.needsAttention || subTask.verificationStatus == .unverified"),
            "Collapsed task-plan mode should keep running, blocked, and unverified work visible."
        )
        XCTAssertTrue(
            source.contains("private var shouldCollapseStableSubTasks: Bool"),
            "Task-plan cards should collapse stable sub-tasks only when the plan is large enough to create scanning pressure."
        )
        XCTAssertTrue(
            source.contains("return highlightedSubTasks + stableSubTasks.prefix(2)"),
            "Collapsed task-plan mode should still keep a small sample of stable sub-tasks visible for context."
        )
        XCTAssertTrue(
            source.contains("Text(showAllSubTasks ? \"已展开全部子任务\" : \"已折叠稳定项\")"),
            "Task-plan cards should explain when some stable sub-tasks are intentionally collapsed."
        )
        XCTAssertTrue(
            source.contains("Button(collapseToggleTitle)"),
            "Users should be able to expand all sub-tasks on demand instead of being locked into the condensed view."
        )
        XCTAssertTrue(
            source.contains("showAllSubTasks = false"),
            "The condensed/expanded state should reset when a different task plan replaces the current one."
        )
        XCTAssertTrue(
            source.contains("let prefersCondensedCompletedState: Bool"),
            "Task-plan cards should support a transcript-specific condensed-completion mode instead of forcing the same density everywhere."
        )
        XCTAssertTrue(
            source.contains("private var shouldOfferCompletedSummary: Bool {\n        prefersCondensedCompletedState && plan.status == .completed\n    }"),
            "Only completed transcript plans should collapse into a summary state."
        )
        XCTAssertTrue(
            source.contains("if !plan.subTasks.isEmpty && !isShowingCompletedSummary {"),
            "Completed condensed plans should hide top-level metric chips until the user expands the full plan again."
        )
        XCTAssertTrue(
            source.contains("Text(\"计划已收束\")"),
            "Completed transcript plans should expose an explicit closeout summary instead of leaving the full task grid open by default."
        )
        XCTAssertTrue(
            source.contains("Button(\"展开计划\")"),
            "Users should still be able to expand a completed transcript plan on demand."
        )
        XCTAssertTrue(
            source.contains("Button(\"收起计划\")"),
            "Expanded completed transcript plans should be collapsible again once the user has reviewed the details."
        )
        XCTAssertTrue(
            source.contains("showCompletedPlanDetails = false"),
            "Completed-plan detail expansion should reset when a different task plan replaces the current one."
        )
    }
}
