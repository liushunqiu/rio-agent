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
}
