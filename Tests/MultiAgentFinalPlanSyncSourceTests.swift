import XCTest

final class MultiAgentFinalPlanSyncSourceTests: XCTestCase {
    func testMultiAgentFinalPlanIsSynchronizedBeforeCancellingPlanSubscription() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        let resultRange = try XCTUnwrap(
            source.range(of: "let result = await engine.processTask(input)"),
            "Multi-Agent execution should await the worker engine result."
        )
        let finalPlanRange = try XCTUnwrap(
            source.range(of: "if let finalPlan = engine.currentPlan"),
            "AgentEngine should read the final Multi-Agent plan after processTask returns."
        )
        let currentPlanRange = try XCTUnwrap(
            source.range(of: "currentTaskPlan = finalPlan"),
            "The final Multi-Agent plan should be published to the context panel/task plan UI."
        )
        let syncRange = try XCTUnwrap(
            source.range(of: "syncPipeline(with: finalPlan)"),
            "The execution pipeline should be synchronized from the final Multi-Agent plan."
        )
        let cancelRange = try XCTUnwrap(
            source.range(of: "cancellable.cancel()"),
            "The plan subscription should still be cancelled after the final state has been read."
        )

        XCTAssertLessThan(resultRange.lowerBound, finalPlanRange.lowerBound)
        XCTAssertLessThan(finalPlanRange.lowerBound, currentPlanRange.lowerBound)
        XCTAssertLessThan(currentPlanRange.lowerBound, syncRange.lowerBound)
        XCTAssertLessThan(syncRange.lowerBound, cancelRange.lowerBound)
    }
}
