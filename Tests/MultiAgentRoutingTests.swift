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

    func testReconcileConfigSetsFallsBackWhenStoredIdsAreMissing() {
        let fallback = ConfigSet(
            id: UUID(),
            name: "Claude Fallback",
            provider: .claude,
            baseURL: "",
            model: "claude-sonnet-4"
        )
        let workerFallback = ConfigSet(
            id: UUID(),
            name: "Compatible Worker",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "deepseek-chat"
        )

        var config = MultiAgentConfig(
            orchestrator: AgentConfig(
                name: "主 Agent",
                role: .orchestrator,
                capability: .general,
                configSetId: UUID(),
                provider: .claude,
                model: "missing-model",
                systemPrompt: ""
            ),
            workers: [
                AgentConfig(
                    name: "代码 Agent",
                    role: .worker,
                    capability: .code,
                    configSetId: UUID(),
                    provider: .openAICompatible,
                    model: "deepseek-chat",
                    systemPrompt: ""
                )
            ],
            router: RouterConfig(
                enabled: true,
                configSetId: UUID(),
                model: "deepseek-chat"
            )
        )

        config.reconcileConfigSets(with: [fallback, workerFallback])

        XCTAssertEqual(config.orchestrator.configSetId, fallback.id)
        XCTAssertEqual(config.orchestrator.model, fallback.model)
        XCTAssertEqual(config.workers.first?.configSetId, workerFallback.id)
        XCTAssertEqual(config.router.configSetId, workerFallback.id)
        XCTAssertEqual(config.router.model, "deepseek-chat")
    }

    func testReconcileConfigSetsUsesFirstAvailableWhenRouterHasNoMatch() {
        let first = ConfigSet(
            id: UUID(),
            name: "First",
            provider: .claude,
            baseURL: "",
            model: "claude-haiku-4"
        )
        let second = ConfigSet(
            id: UUID(),
            name: "Second",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "gemini-2.0-flash"
        )

        var config = MultiAgentConfig()
        config.router.configSetId = UUID()
        config.router.model = ""

        config.reconcileConfigSets(with: [first, second])

        XCTAssertEqual(config.router.configSetId, first.id)
        XCTAssertEqual(config.orchestrator.configSetId, first.id)
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
    func testCancelProcessingMarksActiveSubTasksAsCancelled() {
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
        XCTAssertEqual(engine.currentPlan?.status, .cancelled)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].status, .cancelled)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].result, "已取消")
        XCTAssertEqual(engine.currentPlan?.subTasks[0].verificationStatus, .unverified)
        XCTAssertEqual(engine.currentPlan?.subTasks[1].status, .cancelled)
        XCTAssertEqual(engine.currentPlan?.subTasks[2].status, .completed)
    }

    @MainActor
    func testBuildProjectContextIncludesVerifiedMemoryWhenAvailable() {
        let memory = AgentMemory()
        memory.clearAllMemory()
        memory.recordSuccessfulPattern(taskType: "search", tool: "read_file")

        let engine = MultiAgentEngine(config: MultiAgentConfig(), memory: memory)

        let context = engine.buildProjectContext()

        XCTAssertTrue(context.contains("## Verified Memory"))
        XCTAssertTrue(context.contains("【摘要】任务类型 search 优先使用 read_file"))
    }
}
