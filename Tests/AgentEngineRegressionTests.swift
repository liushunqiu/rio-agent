import XCTest
@testable import RioAgent

@MainActor
final class AgentEngineRegressionTests: XCTestCase {

    func testContextMessagesReflectUpdatedWorkingDirectoryAfterInitialBuild() {
        let engine = AgentEngine()
        engine.appendMessage(.user("hello"))

        let initialSystemPrompt = engine.buildContextMessages().first?.content ?? ""
        XCTAssertFalse(initialSystemPrompt.contains("Working directory:"))

        engine.workingDirectory = "/tmp/rio-agent-project"

        let updatedSystemPrompt = engine.buildContextMessages().first?.content ?? ""
        XCTAssertTrue(updatedSystemPrompt.contains("Working directory: /tmp/rio-agent-project"))
    }

    func testClearConversationResetsUsageTracking() {
        let engine = AgentEngine()

        engine.trackTokenUsage(.init(promptTokens: 120, completionTokens: 45))
        engine.isProcessing = true
        engine.currentToolExecution = .executing(toolCall: ToolCall(id: "tool-1", name: "read_file"))
        XCTAssertGreaterThan(engine.sessionCost, 0)
        XCTAssertFalse(engine.getSessionUsageSummary().isEmpty)

        engine.clearConversation()

        XCTAssertEqual(engine.sessionCost, 0)
        XCTAssertEqual(engine.getSessionUsageSummary(), "")
        XCTAssertEqual(engine.getTotalTokensUsed(), 0)
        XCTAssertFalse(engine.isProcessing)
        XCTAssertNil(engine.currentToolExecution)
    }

    func testClearConversationClearsWorkingDirectoryAndPendingDecision() async {
        let engine = AgentEngine()
        engine.workingDirectory = "/tmp/rio-agent-project"

        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)
        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")

        XCTAssertEqual(
            engine.pendingUserDecision,
            .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试")
        )

        engine.clearConversation()

        XCTAssertNil(engine.workingDirectory)
        XCTAssertNil(engine.pendingUserDecision)
        XCTAssertTrue(engine.messages.isEmpty)
    }

    func testLoadConversationResetsUsageTracking() {
        let engine = AgentEngine()

        engine.trackTokenUsage(.init(promptTokens: 80, completionTokens: 20))
        engine.isProcessing = true
        engine.currentToolExecution = .executing(toolCall: ToolCall(id: "tool-1", name: "read_file"))
        XCTAssertGreaterThan(engine.sessionCost, 0)

        let conversation = Conversation(
            messages: [.user("restored message")],
            workingDirectory: "/tmp/restored"
        )
        engine.loadConversation(conversation)

        XCTAssertEqual(engine.sessionCost, 0)
        XCTAssertEqual(engine.getSessionUsageSummary(), "")
        XCTAssertEqual(engine.workingDirectory, "/tmp/restored")
        XCTAssertFalse(engine.isProcessing)
        XCTAssertNil(engine.currentToolExecution)
    }

    func testLoadConversationClearsVisibleRuntimeState() {
        let engine = AgentEngine()
        engine.singleAgentVerificationSummary = .init(status: .unverified, summary: "旧摘要")
        engine.currentPipeline = ExecutionPipeline(mode: .singleAgent)
        engine.currentPipeline?.stages = [
            PipelineStage(type: .execution, details: .execution(toolCalls: ["read_file"], completedCount: 0, totalCount: 1))
        ]
        engine.isProcessing = true

        let conversation = Conversation(
            messages: [.user("restored message")],
            workingDirectory: "/tmp/restored"
        )
        engine.loadConversation(conversation)

        XCTAssertNil(engine.singleAgentVerificationSummary)
        XCTAssertNil(engine.currentPipeline)
        XCTAssertFalse(engine.isProcessing)
    }

    func testClearConversationInvalidatesInFlightProcessingRun() {
        let engine = AgentEngine()
        engine.isProcessing = true

        let oldRunID = Mirror(reflecting: engine).children.first { $0.label == "processingRunID" }?.value as? UUID
        engine.clearConversation()
        let newRunID = Mirror(reflecting: engine).children.first { $0.label == "processingRunID" }?.value as? UUID

        XCTAssertNotNil(oldRunID)
        XCTAssertNotNil(newRunID)
        XCTAssertNotEqual(oldRunID, newRunID)
    }

    func testClearConversationInvalidatesInFlightErrorWrites() {
        let engine = AgentEngine()

        let oldRunID = Mirror(reflecting: engine).children.first { $0.label == "processingRunID" }?.value as? UUID
        engine.clearConversation()
        let newRunID = Mirror(reflecting: engine).children.first { $0.label == "processingRunID" }?.value as? UUID

        XCTAssertNotEqual(oldRunID, newRunID)
        XCTAssertNil(engine.error)
    }

    func testRunInvalidationGuardsRouterAndPlanningWritesInSource() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        XCTAssertTrue(
            source.contains("let runID = processingRunID"),
            "User-input processing should capture a run identifier before router and planning work begins."
        )
        XCTAssertTrue(
            source.contains("guard processingRunID == runID else { return }\n                    if let decision = routeResult.decision"),
            "Router results should be discarded if the conversation context has already been reset."
        )
        XCTAssertTrue(
            source.contains("let taskAnalysis = await TaskPlanner.analyzeTaskEnhanced(trimmedInput, memory: memory, aiService: planningService, model: configuration.planningModel)\n        guard processingRunID == runID else { return }"),
            "Task-analysis results should not publish plan or confirmation state after a newer run has taken over."
        )
    }

    func testProcessingWithoutPendingDecisionRejectsNewUserInput() {
        let engine = AgentEngine()
        var didComplete = false
        engine.isProcessing = true

        let accepted = engine.submitUserInput("这条应该被忽略") {
            didComplete = true
        }

        XCTAssertFalse(accepted)
        XCTAssertFalse(engine.canAcceptUserInput)
        XCTAssertFalse(didComplete)
        XCTAssertTrue(engine.messages.isEmpty)
    }

    func testMissingExecutionConfigReportsUnselectedModelConfiguration() async {
        let engine = AgentEngine()
        var config = engine.configuration
        config.executionConfigSetId = nil
        engine.updateConfiguration(config)

        await engine.processUserInput("请回复一句话")

        XCTAssertEqual(
            engine.error,
            "执行模型未选择模型配置。请前往 设置 → AI 配置，先添加并选择一个模型配置。"
        )
        XCTAssertEqual(engine.errorRecoveryContext, .executionModel)
    }

    func testIncompleteExecutionConfigReportsSpecificReadinessIssue() async {
        let originalConfigSets = ConfigSetManager.shared.configSets
        defer { ConfigSetManager.shared.configSets = originalConfigSets }

        let brokenConfig = ConfigSet(
            name: "Broken Gateway",
            provider: .openAICompatible,
            baseURL: "",
            model: "custom-model"
        )
        ConfigSetManager.shared.configSets = [brokenConfig]

        let engine = AgentEngine()
        var config = engine.configuration
        config.executionConfigSetId = brokenConfig.id
        engine.updateConfiguration(config)

        await engine.processUserInput("请回复一句话")

        XCTAssertEqual(
            engine.error,
            "执行模型配置「Broken Gateway」不可用：缺少 API 端点。请前往 设置 → AI 配置 → 模型配置补全。"
        )
        XCTAssertEqual(engine.errorRecoveryContext, .executionModel)
    }

    func testExecutionConfigMissingModelReportsSpecificReadinessIssue() async {
        let originalConfigSets = ConfigSetManager.shared.configSets
        defer { ConfigSetManager.shared.configSets = originalConfigSets }

        let brokenConfig = ConfigSet(
            name: "Nameless Gateway",
            provider: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            model: "   "
        )
        ConfigSetManager.shared.configSets = [brokenConfig]

        let engine = AgentEngine()
        var config = engine.configuration
        config.executionConfigSetId = brokenConfig.id
        engine.updateConfiguration(config)

        await engine.processUserInput("请回复一句话")

        XCTAssertEqual(
            engine.error,
            "执行模型配置「Nameless Gateway」不可用：缺少模型标识。请前往 设置 → AI 配置 → 模型配置补全。"
        )
        XCTAssertEqual(engine.errorRecoveryContext, .executionModel)
    }

    func testStopProcessingClearsRecoveryContext() {
        let engine = AgentEngine()
        engine.isProcessing = true
        engine.error = "旧错误"
        engine.errorRecoveryContext = .routerModel

        engine.stopProcessing()

        XCTAssertNil(engine.error)
        XCTAssertNil(engine.errorRecoveryContext)
    }

    func testAgentEngineContainsStructuredMultiAgentRecoveryMapping() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let sharedContextSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/ErrorRecoveryContext.swift"))
        let taskModelSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/MultiAgentConfig.swift"))

        XCTAssertTrue(
            sharedContextSource.contains("enum ErrorRecoveryContext: Equatable"),
            "Structured error recovery context should live in a shared model instead of staying implicit in message text."
        )
        XCTAssertTrue(
            source.contains("presentError(message, recoveryContext: .routerModel)"),
            "Router configuration failures should publish a router recovery context."
        )
        XCTAssertTrue(
            source.contains("if routerConfig.enableQwenRouter"),
            "Qwen Router should use its dedicated vLLM configuration path instead of requiring a generic router config set."
        )
        XCTAssertTrue(
            source.contains("let routeResult = await RouterService.routeDetailed(")
                && source.contains("service: nil,")
                && source.contains("model: routerConfig.qwenModel,"),
            "Qwen Router calls should not require a generic AIService or bound model endpoint."
        )
        XCTAssertTrue(
            source.contains("Qwen Router 配置不可用"),
            "Invalid Qwen Router settings should publish a concrete recovery error."
        )
        XCTAssertTrue(
            source.contains("routerFallbackMessage(")
                && source.contains("title: \"Qwen Router 暂不可用\"")
                && source.contains("title: \"Router 暂不可用\""),
            "Router runtime failures should be visible to users while the normal flow continues."
        )
        XCTAssertTrue(
            source.contains("private func routerFallbackMessage(title: String, reason: String?, guidance: String) -> String"),
            "Router runtime fallback messaging should be centralized so degraded-flow copy stays consistent."
        )
        XCTAssertTrue(
            source.contains("let reasonDetail = cleanedReason?.isEmpty == false ? \"原因：\\(cleanedReason!)。\" : \"\""),
            "Router fallback banners should surface the concrete router failure reason when one is available."
        )
        XCTAssertTrue(
            source.contains("private func applyRouterDecision(input: String, decision: RoutingDecision)"),
            "Router decision application should be centralized across generic and Qwen router paths."
        )
        XCTAssertTrue(
            source.contains("return .multiAgentOrchestratorModel"),
            "Multi-Agent orchestrator failures should map to a dedicated orchestrator recovery context."
        )
        XCTAssertTrue(
            source.contains("recoveryContext: .executionModel"),
            "Execution model failures should publish an execution-model recovery context."
        )
        XCTAssertTrue(
            source.contains("errorRecoveryContext = engine.errorRecoveryContext ?? failedSubTasks"),
            "AgentEngine should prefer the Multi-Agent engine's structured failure context before falling back to sub-task recovery state."
        )
        XCTAssertTrue(
            taskModelSource.contains("let recoveryContext: ErrorRecoveryContext?"),
            "Sub-task and execution results should carry structured recovery context through the Multi-Agent pipeline."
        )
    }

    func testPendingDecisionAllowsUserInputEvenWhenProcessingFlagIsStale() async {
        let engine = AgentEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-init-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingAgentFile = tempDir.appendingPathComponent("AGENT.md")
        try? "# existing".write(to: existingAgentFile, atomically: true, encoding: .utf8)

        engine.workingDirectory = tempDir.path
        await engine.processUserInput("/init")
        engine.isProcessing = true

        var didComplete = false
        let accepted = engine.submitUserInput("否") {
            didComplete = true
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(accepted)
        XCTAssertTrue(engine.canAcceptUserInput)
        XCTAssertTrue(didComplete)
        XCTAssertNil(engine.pendingUserDecision)
        XCTAssertTrue(engine.messages.contains {
            $0.role == .system && $0.content.contains("已取消重新生成 AGENT.md。")
        })
    }

    func testLoadConversationClearsTransientExecutionState() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("旧任务")
        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.error(toolCallId: "1", error: "exit code 1")],
            consecutiveErrors: 1
        )
        _ = await engine.handleFinalContent("已经修复。")

        let conversation = Conversation(
            messages: [.user("restored message")],
            workingDirectory: "/tmp/restored"
        )
        engine.loadConversation(conversation)

        XCTAssertNil(engine.memory.session.currentTask)
        let finalized = await engine.handleFinalContent("新的普通回答。")
        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.messages.last?.content, "新的普通回答。")
    }

    func testContextMessagesHonorConfiguredMessageLimit() {
        let engine = AgentEngine()

        engine.appendMessage(.system("system note"))
        engine.appendMessage(.user("first"))
        engine.appendMessage(.assistant("second"))
        engine.appendMessage(.user("third"))
        engine.appendMessage(.assistant("fourth"))

        var config = engine.configuration
        config.maxContextMessages = 2
        engine.updateConfiguration(config)

        let contextMessages = engine.buildContextMessages()

        XCTAssertEqual(contextMessages.count, 3)
        XCTAssertEqual(contextMessages.dropFirst().map(\.content), ["third", "fourth"])
    }

    func testManualTaskSplitStrategyPromptsBeforeStartingMultiAgent() async {
        let engine = AgentEngine()
        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)

        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")

        XCTAssertFalse(engine.isProcessing)
        XCTAssertTrue(engine.messages.contains {
            $0.role == .system && $0.content.contains("适合 Multi-Agent 协作")
        })
        XCTAssertTrue(engine.messages.contains {
            $0.role == .user && $0.content == "请分析这个项目并修改多个文件后再测试"
        })
    }

    func testManualExecutionConfirmationKeepsOriginalTaskInMemory() async {
        let engine = AgentEngine()
        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)

        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")
        await engine.processUserInput("是")

        XCTAssertEqual(engine.memory.session.currentTask, "请分析这个项目并修改多个文件后再测试")
    }

    func testInitConfirmationKeepsOriginalDirectoryContext() async {
        let engine = AgentEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-init-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingAgentFile = tempDir.appendingPathComponent("AGENT.md")
        try? "# existing".write(to: existingAgentFile, atomically: true, encoding: .utf8)

        engine.workingDirectory = tempDir.path

        await engine.processUserInput("/init")
        XCTAssertEqual(engine.pendingUserDecision, .overwriteAgentFile(directory: tempDir.path))
        engine.workingDirectory = "/tmp/project-b"
        await engine.processUserInput("是")

        XCTAssertNil(engine.pendingUserDecision)
        XCTAssertEqual(engine.memory.session.currentTask, "初始化 \(tempDir.path) 下的 AGENT.md")
    }

    func testInitExecutionPromptStaysInternalOnly() async {
        let engine = AgentEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-init-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        engine.workingDirectory = tempDir.path
        await engine.processUserInput("/init")

        let initPromptMessage = engine.messages.last(where: {
            $0.role == .user && $0.content.contains("你正在为项目初始化 AGENT.md 上下文文件")
        })

        XCTAssertEqual(initPromptMessage?.presentation, .internalOnly)
        XCTAssertFalse(initPromptMessage?.isVisibleInTranscript ?? true)
    }

    func testInitConfirmationTreatsFreshInputAsNewTask() async {
        let engine = AgentEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-init-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingAgentFile = tempDir.appendingPathComponent("AGENT.md")
        try? "# existing".write(to: existingAgentFile, atomically: true, encoding: .utf8)

        engine.workingDirectory = tempDir.path

        await engine.processUserInput("/init")
        await engine.processUserInput("请顺便检查一下这个项目结构")

        XCTAssertNil(engine.pendingUserDecision)
        XCTAssertEqual(engine.memory.session.currentTask, "请顺便检查一下这个项目结构")
        XCTAssertFalse(engine.messages.contains {
            $0.role == .system && $0.content.contains("继续处理你的新请求")
        })
        XCTAssertTrue(engine.messages.contains {
            $0.role == .user && $0.content == "请顺便检查一下这个项目结构"
        })
    }

    func testManualExecutionConfirmationTreatsFreshInputAsNewTask() async {
        let engine = AgentEngine()
        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)

        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")
        XCTAssertEqual(engine.pendingUserDecision, .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试"))
        await engine.processUserInput("改成先只检查路由配置")

        XCTAssertEqual(engine.memory.session.currentTask, "改成先只检查路由配置")
        XCTAssertEqual(engine.pendingUserDecision, .chooseExecutionModeForTask("改成先只检查路由配置"))
        XCTAssertFalse(engine.messages.contains {
            $0.role == .system && $0.content.contains("继续处理你的新请求")
        })
        XCTAssertTrue(engine.messages.contains {
            $0.role == .user && $0.content == "改成先只检查路由配置"
        })
    }

    func testClearConversationClearsPendingUserDecision() async {
        let engine = AgentEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-init-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingAgentFile = tempDir.appendingPathComponent("AGENT.md")
        try? "# existing".write(to: existingAgentFile, atomically: true, encoding: .utf8)

        engine.workingDirectory = tempDir.path
        await engine.processUserInput("/init")

        XCTAssertNotNil(engine.pendingUserDecision)
        engine.clearConversation()
        XCTAssertNil(engine.pendingUserDecision)
    }

    func testOlderLargeToolOutputsAreCompressedButRecentOnesStayIntact() {
        let engine = AgentEngine()
        let largeOutput = String(repeating: "0123456789", count: 300)
        var config = engine.configuration
        config.maxContextMessages = 999
        engine.updateConfiguration(config)

        engine.appendMessage(Message(
            role: .user,
            content: "",
            toolResults: [ToolResult.success(toolCallId: "older", output: largeOutput)]
        ))
        engine.appendMessage(.assistant("filler-1"))
        engine.appendMessage(.user("filler-2"))
        engine.appendMessage(.assistant("middle"))
        engine.appendMessage(Message(
            role: .user,
            content: "",
            toolResults: [ToolResult.success(toolCallId: "recent", output: largeOutput)]
        ))

        let contextMessages = engine.buildContextMessages()
        let toolMessages = contextMessages.filter { $0.toolResults != nil }

        XCTAssertEqual(toolMessages.count, 2)
        guard toolMessages.count == 2 else { return }
        XCTAssertTrue(toolMessages[0].toolResults?.first?.output.contains("[... truncated") == true)
        XCTAssertFalse(toolMessages[1].toolResults?.first?.output.contains("[... truncated") == true)
    }

    func testCompressedToolMessagesPreservePresentationAndSourceMetadata() {
        let engine = AgentEngine()
        let largeOutput = String(repeating: "0123456789", count: 300)
        let timestamp = Date(timeIntervalSince1970: 123)
        let source = MessageSource(providerName: "Provider", modelName: "model", agentName: "Agent")
        var config = engine.configuration
        config.maxContextMessages = 999
        engine.updateConfiguration(config)

        engine.appendMessage(Message(
            role: .system,
            content: "internal tool result",
            timestamp: timestamp,
            toolResults: [ToolResult.success(toolCallId: "older", output: largeOutput)],
            source: source,
            presentation: .internalOnly
        ))
        engine.appendMessage(.assistant("filler-1"))
        engine.appendMessage(.user("filler-2"))
        engine.appendMessage(.assistant("filler-3"))
        engine.appendMessage(.user("filler-4"))

        let compressed = engine.buildContextMessages().first {
            $0.toolResults?.first?.toolCallId == "older"
        }

        XCTAssertEqual(compressed?.presentation, .internalOnly)
        XCTAssertEqual(compressed?.source, source)
        XCTAssertEqual(compressed?.timestamp, timestamp)
        XCTAssertTrue(compressed?.toolResults?.first?.output.contains("[... truncated") == true)
    }

    func testHandleFinalContentSkipsVerificationWhenNoToolEvidenceExists() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("just chat")

        let finalized = await engine.handleFinalContent("这是普通回答。")

        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.messages.last?.content, "这是普通回答。")
    }

    func testHandleFinalContentAppendsUnverifiedNoteWhenEvidenceIsWeak() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("修改文件")

        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.success(toolCallId: "1", output: "")],
            consecutiveErrors: 0
        )

        let finalized = await engine.handleFinalContent("已完成修改。")

        XCTAssertTrue(finalized)
        XCTAssertTrue(engine.messages.last?.content.contains("未验证说明") == true)
        XCTAssertEqual(engine.singleAgentVerificationSummary?.status, .unverified)
    }

    func testHandleFinalContentRequestsRevisionWhenVerifierNeedsRetry() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("运行测试")

        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.error(toolCallId: "1", error: "exit code 1")],
            consecutiveErrors: 1
        )

        let finalized = await engine.handleFinalContent("测试已经通过。")

        XCTAssertFalse(finalized)
        XCTAssertTrue(engine.messages.last?.role == .system)
        XCTAssertTrue(engine.messages.last?.presentation == .internalOnly)
        XCTAssertTrue(engine.messages.last?.content.contains("[Verification Audit]") == true)
        XCTAssertEqual(engine.singleAgentVerificationSummary?.status, .needsRetry)
    }

    func testHandleFinalContentKeepsSingleAgentVerificationSummaryVisibleAfterFinalize() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("修改文件")

        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.success(toolCallId: "1", output: "")],
            consecutiveErrors: 0
        )

        let finalized = await engine.handleFinalContent("已完成修改。")

        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.singleAgentVerificationSummary?.status, .unverified)
    }

    func testHandleFinalContentMarksDeliveredAssistantReplyAsFinalAnswer() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("just chat")

        let finalized = await engine.handleFinalContent("这是最后交付的回答。")

        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.messages.last?.presentation, .finalAnswer)
        XCTAssertTrue(engine.messages.last?.isFinalAnswer == true)
    }

    func testHandleFinalContentDemotesPreviousFinalAnswerWhenNewOneArrives() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("just chat")

        _ = await engine.handleFinalContent("第一版最终答复。")
        _ = await engine.handleFinalContent("第二版最终答复。")

        let finalAnswers = engine.messages.filter(\.isFinalAnswer)
        XCTAssertEqual(finalAnswers.count, 1)
        XCTAssertEqual(finalAnswers.first?.content, "第二版最终答复。")
        XCTAssertTrue(engine.messages.contains {
            $0.content == "第一版最终答复。" && $0.presentation == .normal
        })
    }

    func testMultiAgentSynthesisAppendsFinalAnswerPresentation() async {
        let engine = AgentEngine()

        engine.appendMessage(.assistant("过程消息"))
        engine.appendMessage(.assistant("多 Agent 汇总结果", source: nil, presentation: .finalAnswer))

        XCTAssertEqual(engine.messages.last?.presentation, .finalAnswer)
        XCTAssertTrue(engine.messages.last?.isVisibleInTranscript == true)
    }

    func testProcessUserInputAppendsUserMessageImmediatelyForNormalTurn() async {
        let engine = AgentEngine()
        var callbackCount = 0
        engine.onUserMessageAdded = {
            callbackCount += 1
        }

        await engine.processUserInput("你好，帮我看下项目")

        let userMessages = engine.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.first?.content, "你好，帮我看下项目")
        XCTAssertEqual(callbackCount, 1)
    }

    func testProcessUserInputClearsPreviousSingleAgentPlanStateBeforeNewRun() async {
        let engine = AgentEngine()
        engine.currentSingleAgentPlan = AgentEngine.SingleAgentPlan(
            originalTask: "old",
            steps: ["step 1"],
            currentStep: 1,
            complexity: .simple,
            reasoning: "",
            estimatedTime: 1,
            status: .completed
        )
        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.error(toolCallId: "1", error: "exit code 1")],
            consecutiveErrors: 1
        )

        await engine.processUserInput("新的任务，帮我看下项目")

        let finalized = await engine.handleFinalContent("普通新回答。")
        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.messages.last?.content, "普通新回答。")
    }

    func testProcessUserInputClearsPreviousSingleAgentVerificationSummaryBeforeNewRun() async {
        let engine = AgentEngine()
        engine.singleAgentVerificationSummary = .init(status: .unverified, summary: "旧的验证摘要")

        await engine.processUserInput("新的任务，帮我看下项目")

        XCTAssertNil(engine.singleAgentVerificationSummary)
    }

    func testFinalizePreparedTaskExecutionKeepsCancelledSingleAgentPlanCancelled() {
        let engine = AgentEngine()
        engine.currentSingleAgentPlan = AgentEngine.SingleAgentPlan(
            originalTask: "cancel me",
            steps: ["step 1", "step 2"],
            currentStep: 1,
            complexity: .simple,
            reasoning: "",
            estimatedTime: 1,
            status: .cancelled
        )

        engine.finalizePreparedTaskExecution(useDAG: false)

        XCTAssertEqual(engine.currentSingleAgentPlan?.status, .cancelled)
        XCTAssertEqual(engine.currentSingleAgentPlan?.currentStep, 1)
    }

    func testStopProcessingClearsStaleErrorAndPendingDecisionState() {
        let engine = AgentEngine()
        engine.error = "旧的失败提示"
        engine.isProcessing = true
        engine.singleAgentVerificationSummary = .init(status: .unverified, summary: "旧的验证摘要")
        engine.currentToolExecution = .executing(toolCall: ToolCall(id: "tool-1", name: "read_file"))
        engine.currentSingleAgentPlan = AgentEngine.SingleAgentPlan(
            originalTask: "cancel me",
            steps: ["step 1"],
            currentStep: 0,
            complexity: .simple,
            reasoning: "",
            estimatedTime: 1,
            status: .executing
        )

        engine.stopProcessing()

        XCTAssertFalse(engine.isProcessing)
        XCTAssertNil(engine.error)
        XCTAssertNil(engine.currentToolExecution)
        XCTAssertNil(engine.singleAgentVerificationSummary)
        XCTAssertNil(engine.pendingUserDecision)
        XCTAssertEqual(engine.currentSingleAgentPlan?.status, .cancelled)
        XCTAssertTrue(engine.messages.contains {
            $0.role == .system && $0.content.contains("已停止当前任务")
        })
    }

    func testClearCommandClearsCurrentConversationStateImmediately() async {
        let engine = AgentEngine()
        engine.appendMessage(.user("old"))
        engine.trackTokenUsage(.init(promptTokens: 10, completionTokens: 5))
        engine.isProcessing = true
        engine.currentToolExecution = .executing(toolCall: ToolCall(id: "tool-1", name: "read_file"))

        await engine.processUserInput("/clear")

        XCTAssertTrue(engine.messages.isEmpty)
        XCTAssertEqual(engine.getTotalTokensUsed(), 0)
        XCTAssertFalse(engine.isProcessing)
        XCTAssertNil(engine.currentToolExecution)
    }

    func testExportAsMarkdownOmitsInternalOnlyMessages() {
        let engine = AgentEngine()
        engine.workingDirectory = "/tmp/project"
        engine.appendMessage(.user("visible user"))
        engine.appendMessage(Message.assistant("visible assistant"))
        engine.appendMessage(Message.system(
            "[Internal Planning Context]",
            presentation: .internalOnly
        ))
        engine.appendMessage(Message(
            role: .system,
            content: "",
            toolResults: [ToolResult.success(toolCallId: "hidden", output: "secret tool output")],
            presentation: .internalOnly
        ))

        let markdown = engine.exportAsMarkdown()

        XCTAssertTrue(markdown.contains("visible user"))
        XCTAssertTrue(markdown.contains("visible assistant"))
        XCTAssertFalse(markdown.contains("[Internal Planning Context]"))
        XCTAssertFalse(markdown.contains("secret tool output"))
    }

    func testExportAsMarkdownPreservesToolErrorsAndCancellationReasons() {
        let engine = AgentEngine()
        engine.appendMessage(Message(
            role: .assistant,
            content: "执行记录",
            toolResults: [
                .error(toolCallId: "failed", error: "Permission denied"),
                .cancelled(toolCallId: "cancelled", reason: "用户停止任务"),
                .success(toolCallId: "empty", output: "")
            ]
        ))

        let markdown = engine.exportAsMarkdown()

        XCTAssertTrue(markdown.contains("Tool Result · 错误"))
        XCTAssertTrue(markdown.contains("Permission denied"))
        XCTAssertTrue(markdown.contains("Tool Result · 取消原因"))
        XCTAssertTrue(markdown.contains("用户停止任务"))
        XCTAssertTrue(markdown.contains(ToolResultDisplay.emptyOutputPlaceholder))
    }

    func testExportAsMarkdownPreservesCompleteToolResultOutput() {
        let engine = AgentEngine()
        let longOutput = String(repeating: "0123456789", count: 80) + "TAIL-MARKER"
        engine.appendMessage(Message(
            role: .assistant,
            content: "执行记录",
            toolResults: [.success(toolCallId: "long", output: longOutput)]
        ))

        let markdown = engine.exportAsMarkdown()

        XCTAssertTrue(markdown.contains(longOutput))
        XCTAssertTrue(markdown.contains("TAIL-MARKER"))
        XCTAssertFalse(markdown.contains(String(longOutput.prefix(500)) + "\n```"))
    }

    func testExportAsMarkdownUsesSafeFenceForToolOutputContainingBackticks() {
        let engine = AgentEngine()
        let output = "before\n```swift\nprint(\"hello\")\n```\nafter"
        engine.appendMessage(Message(
            role: .assistant,
            content: "执行记录",
            toolResults: [.success(toolCallId: "code", output: output)]
        ))

        let markdown = engine.exportAsMarkdown()

        XCTAssertTrue(markdown.contains("````\n\(output)\n````"))
    }

    func testExportConversationPreservesWorkingDirectory() {
        let engine = AgentEngine()
        engine.workingDirectory = "/tmp/exported-project"
        engine.appendMessage(.user("visible user"))

        let conversation = engine.exportConversation()

        XCTAssertEqual(conversation.workingDirectory, "/tmp/exported-project")
        XCTAssertEqual(conversation.messages.last?.content, "visible user")
    }

    func testExportConversationPreservesPendingUserDecision() async {
        let engine = AgentEngine()
        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)

        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")

        let conversation = engine.exportConversation()

        XCTAssertEqual(
            conversation.pendingDecision,
            .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试")
        )
    }

    func testLoadConversationRestoresPendingUserDecision() {
        let engine = AgentEngine()
        let conversation = Conversation(
            messages: [
                .user("请分析这个项目并修改多个文件后再测试"),
                .system("检测到该任务适合 Multi-Agent 协作。回复「是」或「yes」继续使用 Multi-Agent；回复其他内容则改用单 Agent。")
            ],
            pendingDecision: .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试")
        )

        engine.loadConversation(conversation)

        XCTAssertEqual(
            engine.pendingUserDecision,
            .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试")
        )
        XCTAssertTrue(engine.canAcceptUserInput)
    }

    func testTaskResumeSkipsConfirmationReplyMessages() {
        let messages: [Message] = [
            .user("请分析这个项目并修改多个文件后再测试"),
            .system("检测到该任务适合 Multi-Agent 协作。回复「是」或「yes」继续使用 Multi-Agent；回复其他内容则改用单 Agent。"),
            .user("是")
        ]

        let resumable = messages
            .reversed()
            .first(where: { message in
                guard message.role == .user, message.isVisibleInTranscript else { return false }
                let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.lowercased()
                let confirmationWords = [
                    "是", "yes", "y", "确认", "ok", "好", "继续",
                    "否", "不", "no", "n", "取消", "算了", "continue"
                ]
                return !trimmed.isEmpty && !confirmationWords.contains(where: { normalized == $0 })
            })?
            .content

        XCTAssertEqual(resumable, "请分析这个项目并修改多个文件后再测试")
    }
}
