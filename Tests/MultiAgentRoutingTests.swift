import XCTest
@testable import RioAgent

final class MultiAgentRoutingTests: XCTestCase {
    func testComplexityAnalysisSimple() {
        let analysis = TaskPlanner.TaskAnalysis(
            complexity: .simple,
            estimatedSteps: 1,
            suggestedSteps: [],
            reasoning: "short conversational input",
            estimatedTime: 5
        )

        XCTAssertEqual(analysis.complexity, .simple)
    }

    func testComplexityAnalysisComplex() {
        let analysis = TaskPlanner.TaskAnalysis(
            complexity: .complex,
            estimatedSteps: 4,
            suggestedSteps: [.explore, .analyze, .modify, .test],
            reasoning: "requires multiple independent steps",
            estimatedTime: 120
        )

        XCTAssertEqual(analysis.complexity, .complex)
    }

    @MainActor
    func testMalformedSplitResponseDoesNotCreateFallbackSubTask() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())

        let subTasks = engine.parseSubTasks(from: "我是 Rio Agent，可以帮助你处理代码和文件任务。")

        XCTAssertTrue(subTasks.isEmpty)
    }
}
