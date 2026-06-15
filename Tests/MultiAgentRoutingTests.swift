import XCTest
@testable import RioAgent

final class MultiAgentRoutingTests: XCTestCase {
    func testIdentityQuestionDoesNotUseMultiAgent() {
        let analysis = TaskPlanner.TaskAnalysis(
            complexity: .simple,
            estimatedSteps: 1,
            suggestedSteps: [],
            reasoning: "short conversational input",
            estimatedTime: 5
        )

        XCTAssertFalse(MultiAgentRouting.shouldUseMultiAgent(for: "你是？", analysis: analysis))
    }

    func testShortConversationalInputOverridesModerateAnalysis() {
        let analysis = TaskPlanner.TaskAnalysis(
            complexity: .moderate,
            estimatedSteps: 2,
            suggestedSteps: [.analyze],
            reasoning: "contains an analysis keyword",
            estimatedTime: 30
        )

        XCTAssertFalse(MultiAgentRouting.shouldUseMultiAgent(for: "你是谁？", analysis: analysis))
    }

    func testComplexTaskUsesMultiAgent() {
        let analysis = TaskPlanner.TaskAnalysis(
            complexity: .complex,
            estimatedSteps: 4,
            suggestedSteps: [.explore, .analyze, .modify, .test],
            reasoning: "requires multiple independent steps",
            estimatedTime: 120
        )

        XCTAssertTrue(MultiAgentRouting.shouldUseMultiAgent(
            for: "分析这个项目并修复登录失败的问题，最后运行测试",
            analysis: analysis
        ))
    }

    @MainActor
    func testMalformedSplitResponseDoesNotCreateFallbackSubTask() {
        let engine = MultiAgentEngine(config: MultiAgentConfig(isEnabled: true))

        let subTasks = engine.parseSubTasks(from: "我是 Rio Agent，可以帮助你处理代码和文件任务。")

        XCTAssertTrue(subTasks.isEmpty)
    }
}
