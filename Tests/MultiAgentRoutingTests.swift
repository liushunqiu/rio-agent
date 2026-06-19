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

    func testRoutingDecisionMapsTargetToPreferredCapability() {
        let codeDecision = RoutingDecision.routeToTarget(
            target: "code_expert",
            params: [:],
            confidence: 0.9,
            reasoning: "code work"
        )
        let searchDecision = RoutingDecision.routeToTarget(
            target: "search_agent",
            params: [:],
            confidence: 0.9,
            reasoning: "search work"
        )

        XCTAssertEqual(codeDecision.preferredWorkerCapability, .code)
        XCTAssertEqual(searchDecision.preferredWorkerCapability, .search)
        XCTAssertNil(RoutingDecision.skip(reason: "闲聊").preferredWorkerCapability)
    }

    @MainActor
    func testSingleAgentRuntimeRolesHighlightOnlyCurrentPipelineStage() {
        var configuration = AIConfiguration()
        let originalConfigSets = ConfigSetManager.shared.configSets
        defer { ConfigSetManager.shared.configSets = originalConfigSets }

        let planningSet = ConfigSet(name: "Planning", model: "planning-model")
        let executionSet = ConfigSet(name: "Execution", model: "execution-model")
        ConfigSetManager.shared.configSets = [planningSet, executionSet]
        configuration.planningConfigSetId = planningSet.id
        configuration.executionConfigSetId = executionSet.id

        var multiAgentConfig = MultiAgentConfig()
        multiAgentConfig.router.enabled = true
        multiAgentConfig.router.model = "router-model"

        let planningPipeline = makePipelineWithRunningStage(.taskAnalysis)
        let planningRoles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: nil,
            isProcessing: true,
            usesMultiAgent: false,
            currentPipeline: planningPipeline,
            lastMessageRole: .user
        )
        XCTAssertEqual(planningRoles.filter(\.isActive).map(\.id), ["planning"])

        let executionPipeline = makePipelineWithRunningStage(.execution)
        let executionRoles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: nil,
            isProcessing: true,
            usesMultiAgent: false,
            currentPipeline: executionPipeline,
            lastMessageRole: .assistant
        )
        XCTAssertEqual(executionRoles.filter(\.isActive).map(\.id), ["execution"])

        let routerPipeline = makePipelineWithRunningStage(.router)
        let routerRoles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: nil,
            isProcessing: true,
            usesMultiAgent: false,
            currentPipeline: routerPipeline,
            lastMessageRole: .user
        )
        XCTAssertEqual(routerRoles.filter(\.isActive).map(\.id), ["router"])
    }

    @MainActor
    func testQwenRouterRuntimeRoleShowsActualQwenModel() {
        let configuration = AIConfiguration()

        var multiAgentConfig = MultiAgentConfig()
        multiAgentConfig.router.enabled = true
        multiAgentConfig.router.enableQwenRouter = true
        multiAgentConfig.router.model = "generic-router-model"
        multiAgentConfig.router.qwenModel = "Qwen/Qwen3.5-4B-Instruct"

        let routerPipeline = makePipelineWithRunningStage(.router)
        let roles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: nil,
            isProcessing: true,
            usesMultiAgent: false,
            currentPipeline: routerPipeline,
            lastMessageRole: .user
        )

        let routerRole = roles.first { $0.id == "router" }
        XCTAssertEqual(routerRole?.title, "Qwen Router")
        XCTAssertEqual(routerRole?.providerName, "Qwen / vLLM")
        XCTAssertEqual(routerRole?.modelName, "Qwen/Qwen3.5-4B-Instruct")
        XCTAssertTrue(routerRole?.isActive == true)
    }

    @MainActor
    func testGenericRouterRuntimeRoleDoesNotFallbackToExecutionModelWhenConfigIsMissing() {
        let configuration = AIConfiguration()

        var multiAgentConfig = MultiAgentConfig()
        multiAgentConfig.router.enabled = true
        multiAgentConfig.router.model = "stale-router-model"

        let routerPipeline = makePipelineWithRunningStage(.router)
        let roles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: nil,
            isProcessing: true,
            usesMultiAgent: false,
            currentPipeline: routerPipeline,
            lastMessageRole: .user
        )

        let routerRole = roles.first { $0.id == "router" }
        XCTAssertEqual(routerRole?.providerName, "未配置")
        XCTAssertEqual(routerRole?.modelName, "未选择模型配置")
        XCTAssertTrue(routerRole?.isActive == true)
    }

    @MainActor
    func testGenericRouterRuntimeRoleUsesConfigSetModelWhenRouterModelIsBlank() {
        let configuration = AIConfiguration()
        let routerSet = ConfigSet(
            name: "Router Set",
            provider: .openAICompatible,
            baseURL: "https://router.example.com/v1",
            model: "router-config-model"
        )

        var multiAgentConfig = MultiAgentConfig()
        multiAgentConfig.router.enabled = true
        multiAgentConfig.router.configSetId = routerSet.id
        multiAgentConfig.router.model = "   "

        let roles = RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: routerSet,
            isProcessing: false,
            usesMultiAgent: false,
            currentPipeline: nil,
            lastMessageRole: nil
        )

        let routerRole = roles.first { $0.id == "router" }
        XCTAssertEqual(routerRole?.providerName, AIProvider.openAICompatible.displayName)
        XCTAssertEqual(routerRole?.modelName, "router-config-model")
    }

    func testGenericRouterExecutionUsesConfigSetModelWhenRouterModelIsBlank() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        XCTAssertTrue(
            source.contains("let configuredRouterModel = routerConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)"),
            "Generic Router execution should trim the optional model override before deciding whether it is configured."
        )
        XCTAssertTrue(
            source.contains("? (configSet(for: configSetId)?.model ?? configuration.executionModel)"),
            "Generic Router execution should prefer the bound Router config set's model before falling back to the execution model."
        )
    }

    func testQwenRouterServiceRejectsInvalidConfigBeforeRequest() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Services/RouterService.swift"))

        XCTAssertTrue(
            source.contains("if let readinessIssue = config.qwenReadinessIssue"),
            "Qwen router should validate config before constructing a network request."
        )
        XCTAssertTrue(
            source.contains("service: AIService?"),
            "RouterService should allow Qwen routing without a generic AI service."
        )
        XCTAssertTrue(
            source.contains("static func routeDetailed("),
            "RouterService should expose a detailed routing path so the UI can distinguish specific router failures."
        )
        XCTAssertTrue(
            source.contains("guard let service else"),
            "Generic router calls should still require a usable AI service."
        )
        XCTAssertTrue(
            source.contains("return (nil, reason)"),
            "Detailed router failures should be carried back to the caller instead of being collapsed into a bare nil."
        )
        XCTAssertTrue(
            source.contains("guard let url = config.qwenChatCompletionsURL"),
            "Qwen router should use the normalized chat completions URL from RouterConfig."
        )
        XCTAssertTrue(
            source.contains("\"model\": config.qwenModel.trimmingCharacters(in: .whitespacesAndNewlines)"),
            "Qwen router should send a trimmed model id after readiness validation."
        )
        XCTAssertTrue(
            source.contains("let sampling = config.normalizedQwenSamplingParameters"),
            "Qwen router requests should normalize sampling values even when config was loaded from older persisted settings."
        )
        XCTAssertTrue(
            source.contains("\"temperature\": sampling.temperature")
                && source.contains("\"top_p\": sampling.topP")
                && source.contains("\"top_k\": sampling.topK")
                && source.contains("\"presence_penalty\": sampling.presencePenalty"),
            "The Qwen request body should use normalized sampling values instead of raw editable config values."
        )
        XCTAssertTrue(
            source.contains("Qwen 路由请求失败：HTTP")
                && source.contains("Qwen Router 响应不是有效 JSON 路由决策")
                && source.contains("Router 响应不是有效 JSON 路由决策"),
            "Detailed router failures should classify HTTP failures and invalid JSON decisions separately."
        )
    }

    @MainActor
    func testRouterPreferredCapabilityCanBeClearedBetweenTasks() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())

        engine.setRouterPreferredCapability(.code)
        XCTAssertEqual(engine.currentRouterPreferredCapability, .code)

        engine.clearRouterPreferredCapability()
        XCTAssertNil(engine.currentRouterPreferredCapability)
    }

    @MainActor
    func testServiceUnavailableResultExplainsMissingWorkerAssignment() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let subTask = SubTask(description: "do work")

        let result = engine.serviceUnavailableResult(for: subTask)

        XCTAssertEqual(result.errors.first, "未分配执行 Agent。请在 设置 → Multi-Agent 启用并选择一个 Worker。")
        XCTAssertEqual(result.verificationStatus, .needsRetry)
        XCTAssertTrue(result.verificationSummary?.contains("当前子任务无法验证") == true)
        XCTAssertEqual(result.recoveryContext, .multiAgentWorkerAssignment)
    }

    @MainActor
    func testServiceUnavailableResultExplainsMissingConfigSetForWorker() {
        let missingConfigId = UUID()
        let worker = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: missingConfigId,
            provider: .openAICompatible,
            model: "deepseek-chat"
        )
        let engine = MultiAgentEngine(config: MultiAgentConfig(workers: [worker]))
        engine.configureConfigSets([])
        let subTask = SubTask(description: "do work", assignedWorker: worker)

        let result = engine.serviceUnavailableResult(for: subTask)

        XCTAssertEqual(result.errors.first, "代码 Agent 未选择可用模型配置。请前往 设置 → Multi-Agent 为该 Agent 选择模型配置。")
        XCTAssertEqual(result.recoveryContext, .multiAgentWorkerModel)
    }

    @MainActor
    func testServiceUnavailableResultExplainsIncompleteWorkerConfigSet() {
        let brokenConfig = ConfigSet(
            id: UUID(),
            name: "Broken Gateway",
            provider: .openAICompatible,
            baseURL: "",
            model: "deepseek-chat"
        )
        let worker = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: brokenConfig.id,
            provider: .openAICompatible,
            model: "deepseek-chat"
        )
        let engine = MultiAgentEngine(config: MultiAgentConfig(workers: [worker]))
        engine.configureConfigSets([brokenConfig])
        let subTask = SubTask(description: "do work", assignedWorker: worker)

        let result = engine.serviceUnavailableResult(for: subTask)

        XCTAssertEqual(result.errors.first, "代码 Agent 使用的模型配置「Broken Gateway」不可用：缺少 API 端点。请前往 设置 → AI 配置 → 模型配置补全。")
        XCTAssertEqual(result.recoveryContext, .multiAgentWorkerModel)
    }

    @MainActor
    func testOrchestratorServiceUnavailablePublishesDedicatedRecoveryContext() async {
        let brokenConfig = ConfigSet(
            id: UUID(),
            name: "Broken Orchestrator",
            provider: .openAICompatible,
            baseURL: "",
            model: "deepseek-chat"
        )
        let orchestrator = AgentConfig(
            name: "主 Agent",
            role: .orchestrator,
            capability: .general,
            configSetId: brokenConfig.id,
            provider: .openAICompatible,
            model: "deepseek-chat"
        )
        let engine = MultiAgentEngine(
            config: MultiAgentConfig(
                orchestrator: orchestrator,
                workers: []
            )
        )
        engine.configureConfigSets([brokenConfig])

        let result = await engine.processTask("拆分一个复杂任务")

        XCTAssertTrue(result.contains("处理失败"))
        XCTAssertEqual(engine.errorRecoveryContext, .multiAgentOrchestratorModel)
    }

    @MainActor
    private func makePipelineWithRunningStage(_ type: PipelineStage.StageType) -> ExecutionPipeline {
        let builder = PipelineBuilder(mode: .singleAgent)
        let stageId = builder.addStage(type)
        builder.startStage(stageId)
        return builder.build()
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
    func testFailedSubTaskDisplayResultFallsBackToErrorsAndVerificationSummary() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let result = ExecutionResult(
            subTaskId: UUID(),
            output: "  ",
            errors: ["工具调用失败：权限不足"],
            retryCount: 1,
            verificationStatus: .needsRetry,
            verificationSummary: "缺少可验证的完成证据。",
            recoveryContext: nil
        )

        let display = engine.subTaskDisplayResult(for: result, status: .failed)

        XCTAssertTrue(display?.contains("工具调用失败：权限不足") == true)
        XCTAssertTrue(display?.contains("缺少可验证的完成证据。") == true)
    }

    @MainActor
    func testApplyExecutionResultSynchronizesVerificationStateImmediately() {
        let subTaskId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        var plan = TaskPlan(
            originalTask: "run worker",
            subTasks: [
                SubTask(id: subTaskId, description: "call worker", status: .running)
            ],
            status: .executing
        )
        let result = ExecutionResult(
            subTaskId: subTaskId,
            output: "",
            errors: ["代码 Agent 未选择可用模型配置。"],
            retryCount: 0,
            verificationStatus: .needsRetry,
            verificationSummary: "当前子任务无法验证。",
            recoveryContext: .multiAgentWorkerModel
        )

        engine.applyExecutionResult(result, to: &plan, status: .failed)

        XCTAssertEqual(plan.subTasks[0].status, .failed)
        XCTAssertEqual(plan.subTasks[0].verificationStatus, .needsRetry)
        XCTAssertEqual(plan.subTasks[0].verificationSummary, "当前子任务无法验证。")
        XCTAssertEqual(plan.subTasks[0].recoveryContext, .multiAgentWorkerModel)
        XCTAssertEqual(plan.subTasks[0].failureSource, .execution)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].verificationStatus, .needsRetry)
        XCTAssertEqual(engine.currentPlan?.subTasks[0].recoveryContext, .multiAgentWorkerModel)
    }

    @MainActor
    func testApplyExecutionResultMarksVerifierFailureSource() {
        let subTaskId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        var plan = TaskPlan(
            originalTask: "verify worker",
            subTasks: [
                SubTask(id: subTaskId, description: "produce answer", status: .running)
            ],
            status: .executing
        )
        let result = ExecutionResult(
            subTaskId: subTaskId,
            output: "answer without enough evidence",
            errors: ["缺少可验证证据。"],
            retryCount: 0,
            verificationStatus: .needsRetry,
            verificationSummary: "缺少可验证证据。",
            recoveryContext: nil
        )

        engine.applyExecutionResult(result, to: &plan, status: .failed)

        XCTAssertEqual(plan.subTasks[0].failureSource, .verification)
    }

    @MainActor
    func testTerminalPlanStatusFailsWhenAnySubTaskNeedsRetry() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let subTasks = [
            SubTask(description: "verified work", status: .completed, verificationStatus: .verified),
            SubTask(description: "blocked work", status: .failed, verificationStatus: .needsRetry)
        ]

        XCTAssertEqual(engine.terminalPlanStatus(for: subTasks), .failed)
    }

    @MainActor
    func testSynthesisResultsTextFollowsPlanOrder() throws {
        let firstId = UUID()
        let secondId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let subTasks = [
            SubTask(id: firstId, description: "first planned step"),
            SubTask(id: secondId, description: "second planned step")
        ]
        let results: [UUID: ExecutionResult] = [
            secondId: ExecutionResult(
                subTaskId: secondId,
                output: "second output",
                errors: [],
                retryCount: 0,
                verificationStatus: .verified,
                verificationSummary: nil,
                recoveryContext: nil
            ),
            firstId: ExecutionResult(
                subTaskId: firstId,
                output: "first output",
                errors: [],
                retryCount: 0,
                verificationStatus: .verified,
                verificationSummary: nil,
                recoveryContext: nil
            )
        ]

        let text = engine.synthesisResultsText(results: results, subTasks: subTasks)

        let firstRange = try XCTUnwrap(text.range(of: "子任务 1：first planned step"))
        let secondRange = try XCTUnwrap(text.range(of: "子任务 2：second planned step"))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    @MainActor
    func testDependencyContextCarriesFailureReasonWhenOutputIsEmpty() {
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let dependency = ExecutionResult(
            subTaskId: UUID(),
            output: "",
            errors: ["前置任务失败：模型配置缺失"],
            retryCount: 0,
            verificationStatus: .needsRetry,
            verificationSummary: "前置任务没有完成，不能直接继续。",
            recoveryContext: nil
        )

        let context = engine.buildWorkerContext(
            for: SubTask(description: "continue work"),
            dependencyResults: [dependency]
        )

        XCTAssertTrue(context.contains("前置任务失败：模型配置缺失"))
        XCTAssertTrue(context.contains("前置任务没有完成，不能直接继续。"))
    }

    @MainActor
    func testBlockedDependencyResultKeepsDownstreamTaskFromLookingCompleted() {
        let failedId = UUID()
        let blockedId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let plan = TaskPlan(
            originalTask: "run dependent tasks",
            subTasks: [
                SubTask(id: failedId, description: "prepare data", status: .failed),
                SubTask(id: blockedId, description: "use prepared data", dependencies: [failedId])
            ],
            status: .executing
        )

        let result = engine.dependencyBlockedResult(
            for: plan.subTasks[1],
            plan: plan,
            finishedIds: [failedId],
            successfulIds: []
        )
        let display = engine.subTaskDisplayResult(for: result, status: .failed)

        XCTAssertEqual(result.verificationStatus, .needsRetry)
        XCTAssertTrue(result.errors.first?.contains("前置依赖未成功完成") == true)
        XCTAssertTrue(display?.contains("prepare data") == true)
        XCTAssertTrue(display?.contains("不能视为完成") == true)
    }

    @MainActor
    func testUnverifiedDependencyDoesNotCountAsSuccessfulDependency() {
        let dependencyId = UUID()
        let blockedId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let dependencyResult = ExecutionResult(
            subTaskId: dependencyId,
            output: "finished without tool evidence",
            errors: [],
            retryCount: 0,
            verificationStatus: .unverified,
            verificationSummary: "缺少可验证证据。",
            recoveryContext: nil
        )
        let plan = TaskPlan(
            originalTask: "run dependent tasks",
            subTasks: [
                SubTask(id: dependencyId, description: "inspect repository", status: .completed, verificationStatus: .unverified),
                SubTask(id: blockedId, description: "modify dependent code", dependencies: [dependencyId])
            ],
            status: .executing
        )

        let successfulIds: Set<UUID> = engine.isSuccessfulDependencyResult(dependencyResult) ? [dependencyId] : []
        let result = engine.dependencyBlockedResult(
            for: plan.subTasks[1],
            plan: plan,
            finishedIds: [dependencyId],
            successfulIds: successfulIds
        )

        XCTAssertFalse(engine.isSuccessfulDependencyResult(dependencyResult))
        XCTAssertEqual(result.verificationStatus, .needsRetry)
        XCTAssertTrue(result.errors.first?.contains("失败或未验证的前置任务：inspect repository") == true)
    }

    @MainActor
    func testBlockedDependencyResultInheritsUpstreamRecoveryContext() {
        let failedId = UUID()
        let blockedId = UUID()
        let engine = MultiAgentEngine(config: MultiAgentConfig())
        let plan = TaskPlan(
            originalTask: "run dependent tasks",
            subTasks: [
                SubTask(
                    id: failedId,
                    description: "configure worker",
                    status: .failed,
                    verificationStatus: .needsRetry,
                    recoveryContext: .multiAgentWorkerModel
                ),
                SubTask(id: blockedId, description: "use configured worker", dependencies: [failedId])
            ],
            status: .executing
        )

        let result = engine.dependencyBlockedResult(
            for: plan.subTasks[1],
            plan: plan,
            finishedIds: [failedId],
            successfulIds: []
        )

        XCTAssertEqual(result.recoveryContext, .multiAgentWorkerModel)
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
        let memory = makeIsolatedAgentMemory(testCase: self)
        memory.clearAllMemory()
        memory.recordSuccessfulPattern(taskType: "search", tool: "read_file")

        let engine = MultiAgentEngine(config: MultiAgentConfig(), memory: memory)

        let context = engine.buildProjectContext()

        XCTAssertTrue(context.contains("## Verified Memory"))
        XCTAssertTrue(context.contains("【摘要】任务类型 search 优先使用 read_file"))
    }
}
