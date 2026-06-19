import XCTest

final class MultiAgentFinalPlanSyncSourceTests: XCTestCase {
    func testMultiAgentFinalPlanIsSynchronizedBeforeCancellingPlanSubscription() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let functionRange = try XCTUnwrap(
            source.range(
                of: "private func processWithMultiAgent(input: String, engine: MultiAgentEngine, runID: UUID) async throws {"
            ),
            "Multi-Agent execution should stay centralized inside processWithMultiAgent."
        )
        let functionBodyRange = functionRange.lowerBound..<source.endIndex

        let resultRange = try XCTUnwrap(
            source.range(of: "let result = await engine.processTask(input)", range: functionBodyRange),
            "Multi-Agent execution should await the worker engine result."
        )
        let finalPlanRange = try XCTUnwrap(
            source.range(of: "if let finalPlan = engine.currentPlan", range: functionBodyRange),
            "AgentEngine should read the final Multi-Agent plan after processTask returns."
        )
        let currentPlanRange = try XCTUnwrap(
            source.range(of: "currentTaskPlan = finalPlan", range: functionBodyRange),
            "The final Multi-Agent plan should be published to the context panel/task plan UI."
        )
        let syncRange = try XCTUnwrap(
            source.range(of: "syncPipeline(with: finalPlan)", range: functionBodyRange),
            "The execution pipeline should be synchronized from the final Multi-Agent plan."
        )
        let guardRange = try XCTUnwrap(
            source.range(of: "guard processingRunID == runID else { return }", range: functionBodyRange),
            "Multi-Agent execution should ignore final plan and answer writes after the run has been invalidated."
        )
        let cancelRange = try XCTUnwrap(
            source.range(of: "defer { cancellable.cancel() }", range: functionBodyRange),
            "The plan subscription should still be cancelled even when the run exits early."
        )
        let sinkGuardRange = try XCTUnwrap(
            source.range(of: "guard let self, self.processingRunID == runID else { return }", range: functionBodyRange),
            "Published Multi-Agent plan updates should stop mutating the active conversation once a newer run takes over."
        )

        XCTAssertLessThan(sinkGuardRange.lowerBound, resultRange.lowerBound)
        XCTAssertLessThan(resultRange.lowerBound, guardRange.lowerBound)
        XCTAssertLessThan(guardRange.lowerBound, finalPlanRange.lowerBound)
        XCTAssertLessThan(finalPlanRange.lowerBound, currentPlanRange.lowerBound)
        XCTAssertLessThan(currentPlanRange.lowerBound, syncRange.lowerBound)
        XCTAssertLessThan(cancelRange.lowerBound, resultRange.lowerBound)
    }

    func testFailedMultiAgentPlanKeepsPipelineFailureOnSourceStage() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let syncRange = try XCTUnwrap(
            source.range(of: "private func syncPipeline(with plan: TaskPlan)"),
            "Pipeline synchronization should stay centralized."
        )
        let syncBodyRange = syncRange.lowerBound..<source.endIndex
        let failedCaseRange = try XCTUnwrap(
            source.range(of: "case .failed:\n            failPipeline(for: plan, builder: builder)", range: syncBodyRange),
            "Failed Multi-Agent plans should use plan-aware failure routing instead of failing the active stage."
        )
        let helperRange = try XCTUnwrap(
            source.range(of: "private func failPipeline(for plan: TaskPlan, builder: PipelineBuilder)"),
            "Pipeline failure routing should inspect the final task plan."
        )
        let completeSynthesisRange = try XCTUnwrap(
            source.range(of: "completeRunningSynthesisStageIfNeeded(builder: builder)", range: helperRange.lowerBound..<source.endIndex),
            "If synthesis produced the final answer, the running synthesis stage should not be mislabeled as failed."
        )
        let executionSourceRange = try XCTUnwrap(
            source.range(of: "subTask.failureSource == .execution", range: helperRange.lowerBound..<source.endIndex),
            "Pipeline failure routing should use the preserved sub-task failure source for execution failures."
        )
        let dependencySourceRange = try XCTUnwrap(
            source.range(of: "subTask.failureSource == .dependency", range: helperRange.lowerBound..<source.endIndex),
            "Dependency-blocked tasks should also keep the pipeline focused on execution."
        )
        let verificationSourceRange = try XCTUnwrap(
            source.range(of: "subTask.failureSource == .verification", range: helperRange.lowerBound..<source.endIndex),
            "Pure verification failures should land on the verification stage instead of the execution stage."
        )
        let executionFailureRange = try XCTUnwrap(
            source.range(of: "failPipelineStage(currentExecutionStageId, builder: builder, error: \"子任务执行失败\")", range: helperRange.lowerBound..<source.endIndex),
            "Sub-task execution failures should land on the execution stage."
        )
        let verificationFailureRange = try XCTUnwrap(
            source.range(of: "failPipelineStage(currentVerificationStageId, builder: builder, error: \"子任务验证未通过\")", range: helperRange.lowerBound..<source.endIndex),
            "Verification failures should land on the verification stage."
        )

        XCTAssertLessThan(failedCaseRange.lowerBound, helperRange.lowerBound)
        XCTAssertLessThan(helperRange.lowerBound, executionSourceRange.lowerBound)
        XCTAssertLessThan(executionSourceRange.lowerBound, dependencySourceRange.lowerBound)
        XCTAssertLessThan(dependencySourceRange.lowerBound, verificationSourceRange.lowerBound)
        XCTAssertLessThan(helperRange.lowerBound, completeSynthesisRange.lowerBound)
        XCTAssertLessThan(completeSynthesisRange.lowerBound, executionFailureRange.lowerBound)
        XCTAssertLessThan(executionSourceRange.lowerBound, executionFailureRange.lowerBound)
        XCTAssertLessThan(executionFailureRange.lowerBound, verificationFailureRange.lowerBound)
        XCTAssertLessThan(verificationSourceRange.lowerBound, verificationFailureRange.lowerBound)
    }
}
