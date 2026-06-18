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
            source.contains("singleAgentVerification: singleAgentVerification"),
            "The transcript runtime card should receive single-agent verification state so verification gaps stay visible in the main reading flow."
        )
        XCTAssertTrue(
            source.contains("let pendingUserDecision: AgentEngine.PendingUserDecision?"),
            "The transcript runtime card should model pending confirmation state explicitly instead of inferring it from pipeline status."
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
            source.contains("return \"验证状态\""),
            "The transcript runtime card should surface a dedicated verification focus title once single-agent verification has completed."
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
            source.contains("return \"等待确认\""),
            "The transcript runtime card should badge pending confirmation as a paused-for-user state instead of continuing to look active."
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
            source.contains("taskPlan?.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })"),
            "Transcript recovery guidance should prioritize blocked subtasks that already expose structured recovery context."
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
            "The transcript runtime card should surface the current focus while the pipeline is still running."
        )
        XCTAssertTrue(
            source.contains("return exceptionalStage.status == .failed ? \"异常焦点\" : \"停止原因\""),
            "The transcript runtime card should distinguish between failures and cancelled flow."
        )
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "TranscriptRuntimeCard(")?.lowerBound),
            try XCTUnwrap(source.range(of: "ForEach(transcriptEntries)")?.lowerBound),
            "Runtime guidance should appear before the transcript entries so the session opens with clear context."
        )
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "TranscriptRuntimeCard(")?.lowerBound),
            try XCTUnwrap(source.range(of: "TaskPlanView(plan: taskPlan)")?.lowerBound),
            "The high-level runtime summary should appear before the raw task plan details."
        )
    }
}
