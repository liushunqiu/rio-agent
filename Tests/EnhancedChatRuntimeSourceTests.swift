import XCTest

final class EnhancedChatRuntimeSourceTests: XCTestCase {
    func testMainTranscriptSurfacesRuntimeGuidanceBeforeDetailedPlan() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedMessageBubble.swift"))

        XCTAssertTrue(
            source.contains("TranscriptRuntimeCard("),
            "The main transcript should render a runtime summary card so users do not need to rely only on the side panel."
        )
        XCTAssertTrue(
            source.contains("if currentPipeline != nil || pendingUserDecision != nil || singleAgentVerification != nil"),
            "The main transcript should keep runtime guidance visible even when only pending confirmation or verification state remains."
        )
        XCTAssertTrue(
            source.contains("singleAgentVerification: singleAgentVerification"),
            "The transcript runtime card should receive single-agent verification state so verification gaps stay visible in the main reading flow."
        )
        XCTAssertTrue(
            source.contains("let pendingUserDecision: AgentEngine.PendingUserDecision?"),
            "The transcript runtime card should model pending confirmation state explicitly instead of inferring it from pipeline status."
        )
        XCTAssertTrue(
            source.contains("let pipeline: ExecutionPipeline?"),
            "Transcript runtime guidance should support paused or post-run states even when no active pipeline remains."
        )
        XCTAssertTrue(
            source.contains("pendingUserDecision: pendingUserDecision"),
            "EnhancedChatView should pass pending confirmation state into the transcript runtime card."
        )
        XCTAssertTrue(
            source.contains("taskPlan?.subTasks.filter(\\.needsAttention).count ?? 0"),
            "Transcript runtime metrics should use the shared SubTask attention state so blocked and cancelled subtasks stay visible."
        )
        XCTAssertTrue(
            source.contains("Text(\"当前流程\")"),
            "The transcript runtime card should label the current process state explicitly."
        )
        XCTAssertTrue(
            source.contains("return \"验证摘要\""),
            "The transcript runtime card should label verifier output as a summary so the separate status badge remains the single source of truth for verified state."
        )
        XCTAssertTrue(
            source.contains("if pipeline?.overallStatus == .completed {\n            return \"交付摘要\"\n        }"),
            "Completed transcript states should shift the focus row into a delivery-review summary instead of reusing the generic current-focus label."
        )
        XCTAssertTrue(
            source.contains("return \"等待输入\""),
            "The transcript runtime card should switch its focus title to a waiting-for-user state when execution pauses for confirmation."
        )
        XCTAssertTrue(
            source.contains("return singleAgentVerification.summary"),
            "The transcript runtime card should show the verifier summary instead of forcing users to infer it from final answer text."
        )
        XCTAssertTrue(
            source.contains("case .verified:\n                return \"进入结果复核\""),
            "Verified single-agent outcomes should shift the transcript headline into a review state instead of repeating the verified badge."
        )
        XCTAssertTrue(
            source.contains("return \"进入交付复核\""),
            "Completed transcript headlines without verifier state should read like a delivery review step instead of just repeating that execution finished."
        )
        XCTAssertTrue(
            source.contains("return \"等待确认\""),
            "The transcript runtime card should badge pending confirmation as a paused-for-user state instead of continuing to look active."
        )
        XCTAssertTrue(
            source.contains("case .none: return \"流程\""),
            "Transcript runtime status should still render a neutral label when no active pipeline is present."
        )
        XCTAssertTrue(
            source.contains("return Theme.statusWarning"),
            "Pending confirmation should use the warning tone so it reads as attention-needed instead of success or running."
        )
        XCTAssertTrue(
            source.contains("return \"当前缺少足够的完成证据，优先补充读回、测试或命令验证。\""),
            "The transcript runtime card should provide a concrete follow-up when the answer is still unverified."
        )
        XCTAssertTrue(
            source.contains("return \"复核完成后，直接开始下一项任务。\""),
            "Verified transcript next actions should describe the closeout move and leave the concrete review checklist to the focus summary row."
        )
        XCTAssertTrue(
            source.contains("return \"优先核对结果、文件改动和验证状态。\""),
            "Completed transcript focus text should summarize what to review without repeating the closeout action."
        )
        XCTAssertTrue(
            source.contains("return \"复核无误后，直接开始下一项任务。\""),
            "Completed transcript next actions should remain a concise closeout action once the review target already appears in the focus row."
        )
        XCTAssertTrue(
            source.contains("回复“是”继续多 Agent；回复其他内容改走单 Agent，也可以直接输入新任务"),
            "Execution-mode confirmations in the main transcript should preserve the same new-task escape hatch as other pending-decision surfaces."
        )
        XCTAssertTrue(
            source.contains("taskPlan?.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })"),
            "Transcript recovery guidance should prioritize blocked subtasks that already expose structured recovery context."
        )
        XCTAssertTrue(
            source.contains("private var prioritizedFailedSubTask: SubTask?"),
            "Transcript failure guidance should identify the concrete failed subtask before choosing focus copy."
        )
        XCTAssertTrue(
            source.contains("subTask.resolvedFailureSource"),
            "Transcript failure guidance should use the model-level resolved source so retry-required verification gaps are not mislabeled."
        )
        XCTAssertTrue(
            source.contains("return \"依赖阻塞待处理\""),
            "Dependency-blocked transcript headlines should describe the actual blocker instead of a generic failure."
        )
        XCTAssertTrue(
            source.contains("return \"验证未通过待修订\""),
            "Verification-failed transcript headlines should point users toward revision."
        )
        XCTAssertTrue(
            source.contains("return \"执行失败待修复\""),
            "Execution-failed transcript headlines should stay distinct from dependency and verification failures."
        )
        XCTAssertTrue(
            source.contains("return \"失败阶段待查看\""),
            "When the transcript only knows a pipeline stage failed, it should ask the user to inspect that stage instead of showing a vague process-level warning."
        )
        XCTAssertTrue(
            source.contains("先查看失败阶段和错误摘要"),
            "Generic failed-stage transcript guidance should point to the visible diagnostics before suggesting configuration changes."
        )
        XCTAssertTrue(
            source.contains("return exceptionalStage.status == .failed ? failureSourceLabel : \"停止原因\""),
            "The transcript focus title should use dependency, verification, or execution source labels for failed runs."
        )
        XCTAssertTrue(
            source.contains("return exceptionalStage.status == .failed ? failureSourceIcon : \"pause.circle.fill\""),
            "The transcript focus icon should also reflect the failure source."
        )
        XCTAssertTrue(
            source.contains("return exceptionalStage.status == .failed ? failedStageFocusText(for: exceptionalStage) : stageSummary(for: exceptionalStage)"),
            "Failed transcript focus text should explain the source-specific blocked subtask instead of echoing only stage counters."
        )
        XCTAssertTrue(
            source.contains("return failedStageNextActionText"),
            "Failed transcript next actions should use source-specific recovery guidance."
        )
        XCTAssertTrue(
            source.contains("return \"先处理上游失败或补足验证证据，再重新执行受阻子任务。\""),
            "Dependency-blocked transcript guidance should route users to upstream repair before retrying."
        )
        XCTAssertTrue(
            source.contains("return \"先根据验证摘要补证或修订结果，避免把未通过的子任务继续汇总。\""),
            "Verification-failed transcript guidance should keep unverified work out of synthesis."
        )
        XCTAssertTrue(
            source.contains("return \"先阅读失败原因和验证摘要；如果有恢复提示，优先按提示修复模型、路由或 Worker 配置。\""),
            "Execution-failed transcript guidance should preserve concrete recovery routing."
        )
        XCTAssertTrue(
            source.contains("return recoveryContext.recoveryActionDetail"),
            "Transcript recovery guidance should route users to a concrete settings destination instead of generic repair advice."
        )
        XCTAssertTrue(
            source.contains("title: \"下一步建议\""),
            "The transcript runtime card should provide a concrete next action."
        )
        XCTAssertTrue(
            source.contains("return \"当前焦点\""),
            "The transcript runtime card should still surface the generic current-focus label while the pipeline is running."
        )
        XCTAssertTrue(
            source.contains("return exceptionalStage.status == .failed ? failureSourceLabel : \"停止原因\""),
            "The transcript runtime card should distinguish between source-labeled failures and cancelled flow."
        )
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "TranscriptRuntimeCard(")?.lowerBound),
            try XCTUnwrap(source.range(of: "ForEach(transcriptEntries)")?.lowerBound),
            "Runtime guidance should appear before the transcript entries so the session opens with clear context."
        )
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "TranscriptRuntimeCard(")?.lowerBound),
            try XCTUnwrap(source.range(of: "TaskPlanView(")?.lowerBound),
            "The high-level runtime summary should appear before the raw task plan details."
        )
        XCTAssertTrue(
            source.contains("if message.isFinalAnswer && !activityBuffer.isEmpty {\n                    entries.append(.message(message))\n                    flushActivity(isSupportingDetail: true)\n                    continue\n                }"),
            "When a final answer arrives after tool activity, the transcript should surface the delivered result before demoting the execution trace into supporting detail."
        )
        XCTAssertTrue(
            source.contains("case activity(messages: [Message], isSupportingDetail: Bool)"),
            "Transcript entries should track when an activity group becomes supporting detail after a final answer."
        )
        XCTAssertTrue(
            source.contains("private var hasVisibleFinalAnswer: Bool"),
            "The transcript should detect when a delivered final answer is already visible before deciding how much Multi-Agent plan detail to keep open."
        )
        XCTAssertTrue(
            source.contains("prefersCondensedCompletedState: hasVisibleFinalAnswer"),
            "Completed task plans in the transcript should collapse only once a final answer is already present in the main reading flow."
        )
    }
}
