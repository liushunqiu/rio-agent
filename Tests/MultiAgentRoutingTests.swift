import XCTest
@testable import RioAgent

final class MultiAgentRoutingTests: XCTestCase {
    func testAgentConfigResolvesExactConfigSetIdBeforeProviderFallback() {
        let primary = ConfigSet(
            id: UUID(),
            name: "Claude Primary",
            provider: .claude,
            baseURL: "",
            model: "claude-sonnet-4"
        )
        let alternate = ConfigSet(
            id: UUID(),
            name: "OpenRouter DeepSeek",
            provider: .openAICompatible,
            baseURL: "https://openrouter.ai/api/v1",
            model: "deepseek-chat"
        )
        let agent = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: alternate.id,
            provider: .claude,
            model: "claude-sonnet-4",
            systemPrompt: ""
        )

        let resolved = agent.resolvedConfigSet(from: [primary, alternate])

        XCTAssertEqual(resolved?.id, alternate.id)
    }

    func testAgentConfigFallsBackToProviderAndModelMatch() {
        let fast = ConfigSet(
            id: UUID(),
            name: "Fast",
            provider: .openAICompatible,
            baseURL: "https://one.example.com",
            model: "gemini-2.0-flash"
        )
        let code = ConfigSet(
            id: UUID(),
            name: "Code",
            provider: .openAICompatible,
            baseURL: "https://two.example.com",
            model: "deepseek-chat"
        )
        let agent = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            provider: .openAICompatible,
            model: "deepseek-chat",
            systemPrompt: ""
        )

        let resolved = agent.resolvedConfigSet(from: [fast, code])

        XCTAssertEqual(resolved?.id, code.id)
    }

    func testAgentConfigFallsBackToFirstConfigSetForProvider() {
        let first = ConfigSet(
            id: UUID(),
            name: "First Claude",
            provider: .claude,
            baseURL: "",
            model: "claude-haiku-4"
        )
        let second = ConfigSet(
            id: UUID(),
            name: "Second Claude",
            provider: .claude,
            baseURL: "",
            model: "claude-sonnet-4"
        )
        let agent = AgentConfig(
            name: "搜索 Agent",
            role: .worker,
            capability: .search,
            provider: .claude,
            model: "unknown-model",
            systemPrompt: ""
        )

        let resolved = agent.resolvedConfigSet(from: [first, second])

        XCTAssertEqual(resolved?.id, first.id)
    }

    func testApplyConfigSetSynchronizesConfigSetProviderAndModel() {
        let configSet = ConfigSet(
            id: UUID(),
            name: "Router",
            provider: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            model: "qwen3.5-4b"
        )
        var agent = AgentConfig(
            name: "主 Agent",
            role: .orchestrator,
            capability: .general,
            provider: .claude,
            model: "claude-sonnet-4",
            systemPrompt: ""
        )

        agent.applyConfigSet(configSet)

        XCTAssertEqual(agent.configSetId, configSet.id)
        XCTAssertEqual(agent.provider, .openAICompatible)
        XCTAssertEqual(agent.model, "qwen3.5-4b")
    }

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

    @MainActor
    func testExecutionBatchesRespectMaxParallelWorkers() {
        let config = MultiAgentConfig(maxParallelWorkers: 2)
        let engine = MultiAgentEngine(config: config)
        let wave = [
            SubTask(description: "1"),
            SubTask(description: "2"),
            SubTask(description: "3"),
            SubTask(description: "4"),
            SubTask(description: "5")
        ]

        let batches = engine.executionBatches(for: wave)

        XCTAssertEqual(batches.map(\.count), [2, 2, 1])
    }

    @MainActor
    func testCancelProcessingMarksActiveSubTasksAsFailed() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        engine.currentPlan = TaskPlan(
            originalTask: "cancel me",
            subTasks: [
                SubTask(description: "running", status: .running),
                SubTask(description: "pending", status: .pending),
                SubTask(description: "done", status: .completed, result: "ok", verificationStatus: .verified)
            ],
            status: .executing
        )
        engine.isProcessing = true

        engine.cancelProcessing()

        XCTAssertFalse(engine.isProcessing)
        XCTAssertNil(engine.error)
        XCTAssertEqual(engine.currentPlan?.status, .failed)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].status, .failed)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].result, "已取消")
        XCTAssertEqual(engine.currentPlan?.subTasks[1].status, .failed)
        XCTAssertEqual(engine.currentPlan?.subTasks[2].status, .completed)
    }
}
