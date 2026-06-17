import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class AgentEngine: ObservableObject {
    struct RuntimeModelRole: Identifiable, Equatable {
        let id: String
        let title: String
        let providerName: String
        let modelName: String
        let isActive: Bool
    }

    private struct PendingExecutionStrategyConfirmation {
        let input: String
        let analysis: TaskPlanner.TaskAnalysis
    }

    @Published var messages: [Message] = []
    @Published var isProcessing = false
    @Published var error: String?
    @Published var currentToolExecution: ToolExecutionState?
    @Published var currentTaskPlan: TaskPlan?
    @Published var currentSingleAgentPlan: SingleAgentPlan?
    @Published var currentPipeline: ExecutionPipeline?

    struct SingleAgentPlan: Identifiable {
        let id: UUID
        var originalTask: String
        var steps: [String]
        var currentStep: Int
        var complexity: TaskPlanner.TaskComplexity
        var reasoning: String
        var estimatedTime: TimeInterval
        var status: TaskPlanStatus

        init(
            id: UUID = UUID(),
            originalTask: String,
            steps: [String],
            currentStep: Int = 0,
            complexity: TaskPlanner.TaskComplexity,
            reasoning: String,
            estimatedTime: TimeInterval,
            status: TaskPlanStatus = .planning
        ) {
            self.id = id
            self.originalTask = originalTask
            self.steps = steps
            self.currentStep = currentStep
            self.complexity = complexity
            self.reasoning = reasoning
            self.estimatedTime = estimatedTime
            self.status = status
        }
    }

    /// 当前正在执行的工具调用 ID，用于驱动文件操作动画
    var currentToolCallId: String? {
        return currentToolExecution?.id
    }
    var pendingInitConfirmation = false
    private var pendingExecutionStrategyConfirmation: PendingExecutionStrategyConfirmation?

    /// Pipeline 构建器（单次执行期间有效）
    private var pipelineBuilder: PipelineBuilder?
    private var currentRouterStageId: UUID?
    private var currentTaskAnalysisStageId: UUID?
    private var currentDAGPlanningStageId: UUID?
    private var currentExecutionStageId: UUID?
    private var currentVerificationStageId: UUID?
    private var currentSynthesisStageId: UUID?
    private var currentErrorRecoveryStageId: UUID?
    private var executionStageToolNames: [String] = []
    private var executionSubsteps: [String: (id: UUID, startTime: Date)] = [:]
    private var multiAgentExecutionSubsteps: [UUID: UUID] = [:]
    private var multiAgentVerificationSubsteps: [UUID: UUID] = [:]

    /// 当前 Router 决策（用于决定是否启用工具调用）
    private var currentRouterDecision: RoutingDecision?
    @Published var workingDirectory: String? {
        didSet {
            ToolRegistry.shared.workingDirectory = workingDirectory
        }
    }

    private let toolRegistry = ToolRegistry.shared
    let memory = AgentMemory()
    let multiFileCoordinator = MultiFileCoordinator()
    private var planningService: AIService?
    private var executionService: AIService?
    private var criticService: CriticService?
    private var verifierService: VerifierService?
    var configuration: AIConfiguration
    var multiAgentConfig: MultiAgentConfig
    private var multiAgentEngine: MultiAgentEngine?

    /// 优化的 Token 追踪器（准确度提升 30%，性能提升 3-5x）
    private let tokenTracker = TokenTracker()

    /// 对话压缩器（始终跟随最新规划模型配置）
    private var conversationCompactor: ConversationCompactor {
        ConversationCompactor(aiService: planningService, model: configuration.planningModel)
    }

    /// 上下文构建器（始终跟随最新执行模型和工作目录）
    private var contextBuilder: ContextBuilder {
        ContextBuilder(
            tokenTracker: tokenTracker,
            model: configuration.executionModel,
            workingDirectory: workingDirectory,
            maxContextMessages: configuration.maxContextMessages,
            systemPrompt: composedSingleAgentSystemPrompt,
            memoryContext: memory.generateMemoryContext()
        )
    }

    /// 工具执行器（管理工具调用的执行流程）
    private lazy var toolExecutor: ToolExecutor = {
        let executor = ToolExecutor(toolRegistry: toolRegistry, memory: memory)
        executor.onExecutionStateChanged = { [weak self] state in
            self?.currentToolExecution = state
            self?.syncExecutionSubstep(with: state)
        }
        return executor
    }()

    /// Called when a user message is added to the conversation (for immediate title update)
    var onUserMessageAdded: (() -> Void)?

    /// The currently running processing task, used for cancellation
    private var currentProcessingTask: Task<Void, Never>?
    /// Flag to signal cancellation to the processing loop
    private var isCancelled = false
    private var recentSingleAgentEvidence: [String] = []
    private var recentSingleAgentToolErrors: [String] = []
    private var isAwaitingSingleAgentVerificationRetry = false
    var textToolCallRedirectCount = 0

    init(configuration: AIConfiguration = AIConfiguration(), multiAgentConfig: MultiAgentConfig = MultiAgentConfig()) {
        self.configuration = configuration
        self.multiAgentConfig = multiAgentConfig
        loadConfiguration()
        loadMultiAgentConfig()
        setupAIService()
        setupMultiAgentEngine()
    }

    private func setupAIService() {
        planningService = createService(configSetId: configuration.planningConfigSetId)
        executionService = createService(configSetId: configuration.executionConfigSetId)
        setupCriticService()
    }

    private func setupCriticService() {
        let service = createService(configSetId: configuration.planningConfigSetId)
        criticService = CriticService(
            aiService: service,
            model: configuration.planningModel
        )
        verifierService = VerifierService(
            aiService: service,
            model: configuration.planningModel
        )
    }

    private func createService(configSetId: UUID?) -> AIService? {
        guard let id = configSetId,
              let configSet = ConfigSetManager.shared.configSet(for: id) else {
            return nil
        }
        let provider = configSet.provider
        let baseURL = configSet.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = configSet.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if provider == .openAICompatible {
            guard !baseURL.isEmpty else { return nil }
            return AIServiceFactory.createService(provider: provider, apiKey: apiKey, baseURL: baseURL)
        }
        guard !apiKey.isEmpty else { return nil }
        return AIServiceFactory.createService(provider: provider, apiKey: apiKey, baseURL: baseURL)
    }

    private func configSet(for id: UUID?) -> ConfigSet? {
        ConfigSetManager.shared.configSet(for: id)
    }

    private func missingServiceMessage(role: String, provider: AIProvider) -> String {
        if provider == .openAICompatible {
            return "\(role)未配置 API 端点。请前往 设置 → AI 配置 → 自定义端点填写服务地址。"
        }
        return "\(role)未配置 API Key。请前往 设置 → AI 配置 → \(provider.displayName) 填写 API Key。"
    }

    private func setupMultiAgentEngine() {
        let engine = MultiAgentEngine(
            config: multiAgentConfig,
            toolRegistry: toolRegistry,
            criticService: criticService,
            verifierService: verifierService,
            memory: memory
        )
        let configManager = ConfigSetManager.shared
        engine.configureConfigSets(configManager.configSets)
        multiAgentEngine = engine
    }

    func updateConfiguration(_ newConfig: AIConfiguration) {
        configuration = newConfig
        setupAIService()
        setupMultiAgentEngine()
        saveConfiguration()
    }

    func updateMultiAgentConfig(_ newConfig: MultiAgentConfig) {
        multiAgentConfig = newConfig
        setupMultiAgentEngine()
        saveMultiAgentConfig()
    }

    var usesMultiAgentForCurrentPlan: Bool {
        currentTaskPlan != nil
    }

    var runtimeModelRoles: [RuntimeModelRole] {
        if usesMultiAgentForCurrentPlan, let multiAgentEngine {
            return RuntimeModelRoleBuilder.multiAgentRoles(
                config: multiAgentEngine.currentConfig,
                plan: currentTaskPlan
            )
        }
        return RuntimeModelRoleBuilder.singleAgentRoles(
            configuration: configuration,
            multiAgentConfig: multiAgentConfig,
            routerConfigSet: configSet(for: multiAgentConfig.router.configSetId),
            isProcessing: isProcessing,
            usesMultiAgent: usesMultiAgentForCurrentPlan,
            lastMessageRole: messages.last?.role
        )
    }

    var primaryDisplayModelName: String {
        runtimeModelRoles.first(where: \.isActive)?.modelName
            ?? runtimeModelRoles.first?.modelName
            ?? configuration.executionModel
    }

    var primaryDisplayProviderName: String {
        runtimeModelRoles.first(where: \.isActive)?.providerName
            ?? runtimeModelRoles.first?.providerName
            ?? configuration.executionProvider.displayName
    }

    private var planningMessageSource: MessageSource {
        MessageSource(
            providerName: configuration.planningProvider.displayName,
            modelName: configuration.planningModel,
            agentName: "Planning"
        )
    }

    private var executionMessageSource: MessageSource {
        MessageSource(
            providerName: configuration.executionProvider.displayName,
            modelName: configuration.executionModel,
            agentName: "Execution"
        )
    }

    private var multiAgentMessageSource: MessageSource {
        MessageSource(
            providerName: multiAgentConfig.orchestrator.provider.displayName,
            modelName: multiAgentConfig.orchestrator.model,
            agentName: multiAgentConfig.orchestrator.name
        )
    }

    // MARK: - Configuration Persistence

    private let configurationKey = "ai_configuration"
    private let multiAgentConfigKey = "multi_agent_configuration"

    func saveConfiguration() {
        do {
            let data = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(data, forKey: configurationKey)
            RioLogger.config.info("💾 配置已保存 - 规划: \(self.configuration.planningProvider.displayName, privacy: .public)/\(self.configuration.planningModel, privacy: .public), 执行: \(self.configuration.executionProvider.displayName, privacy: .public)/\(self.configuration.executionModel, privacy: .public)")
        } catch {
            RioLogger.config.error("⚠️ 保存配置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey) else {
            RioLogger.config.info("📂 未找到已保存的配置，使用默认值")
            return
        }
        do {
            configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)
            setupAIService()
            RioLogger.config.info("📂 已加载配置 - 规划: \(self.configuration.planningProvider.displayName, privacy: .public)/\(self.configuration.planningModel, privacy: .public), 执行: \(self.configuration.executionProvider.displayName, privacy: .public)/\(self.configuration.executionModel, privacy: .public)")
        } catch {
            RioLogger.config.error("⚠️ 加载配置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveMultiAgentConfig() {
        do {
            let data = try JSONEncoder().encode(multiAgentConfig)
            UserDefaults.standard.set(data, forKey: multiAgentConfigKey)
        } catch {
            RioLogger.config.error("⚠️ 保存 Multi-Agent 配置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadMultiAgentConfig() {
        guard let data = UserDefaults.standard.data(forKey: multiAgentConfigKey) else { return }
        do {
            multiAgentConfig = try JSONDecoder().decode(MultiAgentConfig.self, from: data)
            multiAgentConfig.migrateBuiltInPromptsIfNeeded()
            setupMultiAgentEngine()
        } catch {
            RioLogger.config.error("⚠️ 加载 Multi-Agent 配置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public Methods

    func submitUserInput(
        _ input: String,
        onComplete: @escaping @MainActor () -> Void = {}
    ) {
        guard !isProcessing else { return }

        currentProcessingTask?.cancel()
        currentProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.currentProcessingTask = nil
                onComplete()
            }
            await self.processUserInput(input)
        }
    }

    func processUserInput(_ input: String) async {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        // Record current task in memory
        memory.setCurrentTask(trimmedInput)
        
        // 检查是否是命令（以/开头）
        if trimmedInput.hasPrefix("/") {
            await handleCommand(trimmedInput)
            return
        }

        // 处理 /init 确认流程
        if pendingInitConfirmation {
            pendingInitConfirmation = false
            let userMessage = Message.user(input)
            messages.append(userMessage)

            let confirmWords = ["是", "yes", "y", "确认", "ok", "好"]
            if confirmWords.contains(where: { trimmedInput.lowercased().hasPrefix($0) }) {
                if let dir = workingDirectory {
                    await performInit(directory: dir)
                }
            } else {
                let cancelMessage = Message.system("已取消重新生成 AGENT.md。", source: executionMessageSource)
                messages.append(cancelMessage)
            }
            return
        }

        if let pendingExecutionStrategyConfirmation {
            self.pendingExecutionStrategyConfirmation = nil
            let userMessage = Message.user(input)
            messages.append(userMessage)

            let confirmWords = ["是", "yes", "y", "确认", "ok", "好", "继续", "continue"]
            let useMultiAgent = confirmWords.contains { trimmedInput.lowercased().hasPrefix($0) }
            let modeMessage = Message.system(
                useMultiAgent ? "已确认使用 Multi-Agent 模式。" : "已切换为单 Agent 模式。",
                source: planningMessageSource
            )
            messages.append(modeMessage)

            await executePreparedTask(
                input: pendingExecutionStrategyConfirmation.input,
                taskAnalysis: pendingExecutionStrategyConfirmation.analysis,
                useDAG: useMultiAgent,
                appendUserMessage: false
            )
            return
        }

        // For a normal user turn, render the message immediately so a brand-new
        // conversation switches out of the landing view before router/planning work finishes.
        let userMessage = Message.user(input)
        messages.append(userMessage)
        onUserMessageAdded?()
        isProcessing = true
        isCancelled = false
        error = nil
        currentTaskPlan = nil

        // MARK: - Router interception (本地路由模型前置拦截)
        currentRouterDecision = nil
        currentRouterStageId = nil
        currentTaskAnalysisStageId = nil
        currentDAGPlanningStageId = nil
        currentExecutionStageId = nil
        currentVerificationStageId = nil
        currentSynthesisStageId = nil
        currentErrorRecoveryStageId = nil
        executionStageToolNames = []
        currentPipeline = nil
        pipelineBuilder = PipelineBuilder(mode: .singleAgent)
        currentPipeline = pipelineBuilder?.build()

        if multiAgentConfig.router.enabled {
            RioLogger.service.info("🔀 Router 已启用，开始路由分析...")
            RioLogger.service.debug("🔀 RouterConfig - configSetId: \(self.multiAgentConfig.router.configSetId?.uuidString ?? "nil", privacy: .public)")
            RioLogger.service.debug("🔀 RouterConfig - model: '\(self.multiAgentConfig.router.model, privacy: .public)'")
            if let configSetId = multiAgentConfig.router.configSetId,
               let routerService = createService(configSetId: configSetId) {
                let routerConfig = multiAgentConfig.router
                let model = routerConfig.model.isEmpty ? configuration.executionModel : routerConfig.model
                RioLogger.service.info("🔀 Router 使用模型: \(model, privacy: .public)")

                if let decision = await RouterService.route(
                    input: trimmedInput,
                    service: routerService,
                    model: model,
                    config: routerConfig
                ) {
                    // 安全兜底：如果 Router 判断为 skip，但用户消息包含明确的任务关键词，
                    // 则覆盖 skip 决策，允许执行模型使用工具。
                    let finalDecision = Self.applySkipSafetyOverride(
                        input: trimmedInput,
                        decision: decision
                    )
                    if case .skip = decision, case .routeToTarget = finalDecision {
                        RioLogger.agent.warning("🔀 Router 原始决策为 skip，已被安全兜底覆盖为 process")
                    }
                    currentRouterDecision = finalDecision
                    trackRouterStage(decision: finalDecision)

                    switch finalDecision {
                    case .skip(let reason):
                        RioLogger.service.info("🔀 Router 决策: SKIP - \(reason, privacy: .public)")
                        // skip 意味着无需工具调用，但仍需让 AI 回答问题，因此继续执行但禁用工具
                    case .routeToTarget(let target, _, let confidence, let reasoning):
                        RioLogger.service.info("🔀 Router 决策: \(target, privacy: .public) (置信度: \(confidence, privacy: .public)) - \(reasoning, privacy: .public)")
                        // TODO: 根据 target 路由到特定 Worker（未来扩展）
                    }
                } else {
                    RioLogger.service.warning("⚠️ Router 调用失败，继续执行标准流程")
                    trackRouterStage(decision: nil)
                }
            } else {
                RioLogger.service.warning("⚠️ Router 已启用但未配置 configSetId 或 API Key，跳过路由")
            }
        } else {
            RioLogger.service.debug("⏭️ Router 未启用，跳过路由阶段")
        }

        // Analyze task complexity and generate plan if needed
        RioLogger.agent.info("📊 开始分析任务复杂度...")
        let taskAnalysis = await TaskPlanner.analyzeTaskEnhanced(trimmedInput, memory: memory, aiService: planningService, model: configuration.planningModel)
        RioLogger.agent.info("📊 任务复杂度: \(taskAnalysis.complexity, privacy: .public), 预计步骤: \(taskAnalysis.estimatedSteps, privacy: .public)")

        // 追踪任务分析阶段
        trackTaskAnalysisStage(analysis: taskAnalysis)

        // For complex tasks, generate a plan and inform the user
        if taskAnalysis.complexity != .simple {
            RioLogger.agent.info("📝 任务复杂度非 simple，生成执行计划...")
            let plan = taskAnalysis.plannedSteps.isEmpty
                ? TaskPlanner.decomposeTask(trimmedInput, memory: memory)
                : taskAnalysis.plannedSteps
            let formattedPlan = TaskPlanner.formatPlanForExecution(plan, analysis: taskAnalysis)
            RioLogger.agent.info("📝 生成计划包含 \(plan.count, privacy: .public) 个步骤")

            // Add plan to messages for user to see
            // Use a clear internal-context marker so the model treats this as metadata,
            // not as additional instructions that override the user's request.
            let planMessage = Message.system(
                "[Internal Planning Context — for your reference only, do not repeat to user]\n\(formattedPlan)",
                source: planningMessageSource,
                presentation: .internalOnly
            )
            messages.append(planMessage)

            // Store plan for execution guidance in system prompt
            activePlan = plan
            currentPlanStep = 0
            activePlanAnalysis = taskAnalysis

            // Add execution guidance
            let guidance = TaskPlanner.generateExecutionGuidance(
                analysis: taskAnalysis,
                currentStep: nil,
                totalSteps: plan.count
            )
            let guidanceMessage = Message.system(
                "[Internal Execution Guidance — for your reference only, do not repeat to user]\n\(guidance)",
                source: planningMessageSource,
                presentation: .internalOnly
            )
            messages.append(guidanceMessage)
        } else {
            RioLogger.agent.info("⏭️ 任务复杂度为 simple，跳过计划生成")
            clearActivePlan()
        }

        let useDAG = shouldUseMultiAgent(for: taskAnalysis)
        if useDAG {
            currentSingleAgentPlan = nil
        }
        RioLogger.agent.info("🚦 执行模式决策: useDAG=\(useDAG, privacy: .public), taskSplitStrategy=\(String(describing: self.multiAgentConfig.taskSplitStrategy), privacy: .public)")
        if useDAG, multiAgentConfig.taskSplitStrategy == .manual {
            isProcessing = false
            messages.append(
                Message.system("检测到该任务适合 Multi-Agent 协作。回复「是」或「yes」继续使用 Multi-Agent；回复其他内容则改用单 Agent。")
            )
            pendingExecutionStrategyConfirmation = PendingExecutionStrategyConfirmation(
                input: input,
                analysis: taskAnalysis
            )
            return
        }

        await executePreparedTask(
            input: input,
            taskAnalysis: taskAnalysis,
            useDAG: useDAG,
            appendUserMessage: false
        )
    }

    private func executePreparedTask(
        input: String,
        taskAnalysis: TaskPlanner.TaskAnalysis,
        useDAG: Bool,
        appendUserMessage: Bool
    ) async {
        isProcessing = true
        isCancelled = false
        error = nil
        currentTaskPlan = nil

        let mode: ExecutionPipeline.ExecutionMode = useDAG ? .multiAgent : .singleAgent
        if let pipelineBuilder {
            pipelineBuilder.setMode(mode)
            currentPipeline = pipelineBuilder.build()
        } else {
            pipelineBuilder = PipelineBuilder(mode: mode)
            currentPipeline = pipelineBuilder?.build()
        }

        if appendUserMessage {
            let userMessage = Message.user(input)
            messages.append(userMessage)
            onUserMessageAdded?()
        }

        toolRegistry.setupConfirmationCallbacks { [weak self] title, message, allowsTrustForSession in
            return await self?.showConfirmation(
                title: title,
                message: message,
                allowsTrustForSession: allowsTrustForSession
            ) ?? .denied
        }

        do {
            if useDAG {
                RioLogger.agent.info("🚀 任务复杂度达到 \(taskAnalysis.complexity, privacy: .public)，启用 Multi-Agent 模式")
                if let multiAgentEngine = multiAgentEngine {
                    RioLogger.agent.info("🚀 Multi-Agent 引擎已就绪，开始并行执行")
                    try await processWithMultiAgent(input: input, engine: multiAgentEngine)
                } else {
                    RioLogger.agent.warning("⚠️ Multi-Agent 引擎未初始化，回退到单 Agent 模式")
                    guard let executionService else {
                        error = missingServiceMessage(role: "执行模型", provider: configuration.executionProvider)
                        isProcessing = false
                        return
                    }

                    if configuration.isStreaming {
                        try await processConversationLoopStreaming(aiService: executionService)
                    } else {
                        try await processConversationLoop(aiService: executionService)
                    }
                }
            } else {
                RioLogger.agent.info("⚡️ 任务复杂度为 \(taskAnalysis.complexity, privacy: .public)，使用单 Agent 模式")
                publishSingleAgentPlanIfNeeded(input: input, analysis: taskAnalysis)
                currentSingleAgentPlan?.status = .executing
                guard let executionService else {
                    error = missingServiceMessage(role: "执行模型", provider: configuration.executionProvider)
                    isProcessing = false
                    return
                }

                if configuration.isStreaming {
                    try await processConversationLoopStreaming(aiService: executionService)
                } else {
                    try await processConversationLoop(aiService: executionService)
                }
            }
        } catch is CancellationError {
            RioLogger.agent.info("⏹️ 用户取消了当前任务")
        } catch {
            self.error = error.localizedDescription
            if !useDAG {
                currentSingleAgentPlan?.status = .failed
            }
        }

        completeExecutionStage()
        if !useDAG, currentSingleAgentPlan?.status != .failed {
            currentSingleAgentPlan?.status = .completed
            currentSingleAgentPlan?.currentStep = currentSingleAgentPlan?.steps.count ?? 0
        }

        // Auto-compact if too many messages (save tokens)
        await autoCompactIfNeeded()

        // 完成 Pipeline
        pipelineBuilder?.finish()
        currentPipeline = pipelineBuilder?.build()
        pipelineBuilder = nil

        isProcessing = false
    }

    private func shouldUseMultiAgent(for taskAnalysis: TaskPlanner.TaskAnalysis) -> Bool {
        taskAnalysis.complexity == .moderate
            || taskAnalysis.complexity == .complex
            || taskAnalysis.complexity == .veryComplex
    }

    /// Stop the current processing (cancel ongoing API calls and tool executions)
    func stopProcessing() {
        guard isProcessing else { return }
        isCancelled = true
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        multiAgentEngine?.cancelProcessing()
        isProcessing = false
        currentToolExecution = nil
        currentSingleAgentPlan?.status = .failed
        failActivePipelineStage()
        pipelineBuilder?.finish()
        currentPipeline = pipelineBuilder?.build()
        pipelineBuilder = nil

        let cancelMessage = Message.system("⏹ 已停止当前任务。", source: executionMessageSource)
        messages.append(cancelMessage)
    }

    // MARK: - Command Handling

    private func handleCommand(_ command: String) async {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).lowercased()

        switch cmd {
        case "/init":
            await initProject()
        case "/clear":
            clearConversation()
            NotificationCenter.default.post(name: .createNewConversation, object: nil)
        case "/compact", "/summarize":
            await compactConversation()
        case "/export":
            if let path = exportToFile() {
                let msg = Message.system("✅ 对话已导出到: \(path)", source: executionMessageSource)
                messages.append(msg)
            }
        case "/help":
            showHelp()
        default:
            let errorMessage = Message.system("未知命令: \(cmd)\n输入 /help 查看可用命令", source: executionMessageSource)
            messages.append(errorMessage)
        }
    }

    private func initProject() async {
        guard let dir = workingDirectory else {
            let errorMessage = Message.system("请先设置工作目录，然后再执行 /init 命令", source: executionMessageSource)
            messages.append(errorMessage)
            return
        }

        let agentMDPath = "\(dir)/AGENT.md"

        // 检查 AGENT.md 是否已存在
        if FileManager.default.fileExists(atPath: agentMDPath) {
            let confirmMessage = Message.system(
                "⚠️ AGENT.md 已存在于 \(dir)\n\n是否要重新生成？这将覆盖现有文件。\n\n回复「是」或「yes」确认重新生成，或回复其他内容取消。",
                source: executionMessageSource
            )
            messages.append(confirmMessage)

            // 等待用户确认：将控制权交给对话循环，下一条用户消息会决定是否继续
            // 使用一个标记让 processUserInput 知道下一步是确认 /init
            pendingInitConfirmation = true
            return
        }

        await performInit(directory: dir)
    }

    /// 用户确认后的实际初始化逻辑
    private func performInit(directory: String) async {
        let agentMDPath = "\(directory)/AGENT.md"

        let initPrompt = """
        你正在为项目初始化 AGENT.md 上下文文件。工作目录是：\(directory)

        请严格按以下步骤操作：

        ## 步骤 1：探索项目

        使用可用工具全面分析项目：
        - 使用 list_directory 查看根目录结构
        - 使用 read_file 读取关键配置文件（如 package.json、Cargo.toml、go.mod、pyproject.toml、Makefile、README.md、.gitignore 等，根据实际存在哪些来读取）
        - 使用 execute_command 执行 git log --oneline -10 了解最近的开发活动
        - 使用 find_files 查找 .eslintrc、.prettierrc、rustfmt.toml、biome.json、ruff.toml 等代码风格配置文件
        - 使用 find_files 查找 .cursorrules、.cursor/rules/、.github/copilot-instructions.md 等 AI 工具配置
        - 使用 find_files 查找 .env.example 等环境变量模板
        - 使用 search_files 搜索项目中的关键模式（如有必要）

        ## 步骤 2：生成 AGENT.md 内容

        基于你在步骤 1 中发现的信息，生成 AGENT.md 文件内容。内容应包含：

        ### 必须包含的
        - **项目概述**：项目类型、语言、框架、简要描述
        - **构建/测试/运行命令**：从 package.json scripts、Makefile、Cargo.toml 等中提取的实际命令。只写非标准的、AI 不容易猜到的命令。标准命令（如 npm test、cargo test）如果用法没有特殊之处则不需要列出。
        - **代码风格规则**：从 .eslintrc、.prettierrc 等配置中提取的关键规则，特别是与语言默认规范不同的规则
        - **项目架构**：高层架构概述（模块划分、关键目录的职责），不是文件列表
        - **非显而易见的注意事项**：环境变量要求、特殊的工作流约定、容易踩坑的地方
        - **已有 AI 工具配置**：如果存在 .cursorrules、AGENTS.md 等文件，提取其中的重要规则

        ### 必须排除的
        - ❌ 不要列出文件和目录清单（AI 可以自己用工具发现）
        - ❌ 不要写通用建议（"写好代码"、"添加注释"、"确保测试通过"）
        - ❌ 不要写标准语言规范（AI 已经知道）
        - ❌ 不要写占位符（"在这里添加构建命令"）
        - ❌ 不要写频繁变化的信息（用 @path 引用源文件代替）

        每一行都要通过这个测试："如果删掉这条，AI 会犯错吗？" 如果不会，就删掉。

        ## 步骤 3：写入文件

        使用 write_file 工具将生成的内容写入：\(agentMDPath)

        文件开头必须是：
        # AGENT.md
        本文件为 Rio Agent 提供项目上下文信息。

        ## 步骤 4：报告结果

        写入成功后，简要说明你发现了什么以及生成了哪些内容。
        """

        let userMessage = Message.user(initPrompt)
        messages.append(userMessage)

        isProcessing = true
        error = nil

        guard let executionService else {
            error = missingServiceMessage(role: "执行模型", provider: configuration.executionProvider)
            isProcessing = false
            return
        }

        do {
            if configuration.isStreaming {
                try await processConversationLoopStreaming(aiService: executionService)
            } else {
                try await processConversationLoop(aiService: executionService)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isProcessing = false
    }

    private func showHelp() {
        let helpMessage = Message.system("""
        📖 Rio Agent 命令帮助
        
        可用命令:
        
        /init    - AI 智能初始化项目，生成 AGENT.md 文件
                  AI 会自动分析项目结构、配置文件和代码风格，生成精准的项目上下文
        
        /clear   - 清除当前对话历史
                  立即新建一个空白对话，保留旧对话历史
        
        /compact - 压缩对话上下文
                  将历史消息压缩为摘要，节省 token 消耗
        
        /export  - 导出当前对话为 Markdown 文件
                  保存到用户选择的位置
        
        /help    - 显示此帮助信息
                  查看所有可用命令
        
        💡 提示:
        - 命令必须以 / 开头
        - 命令不区分大小写
        - 当对话较长时，使用 /compact 可节省 token 消耗
        - 设置工作目录后，/init 会自动分析项目并生成 AGENT.md
        """, source: executionMessageSource)
        messages.append(helpMessage)
    }

    // MARK: - Multi-Agent Processing

    private func processWithMultiAgent(input: String, engine: MultiAgentEngine) async throws {
        let systemMessage = Message.system(
            "Multi-Agent 模式已启动，正在分析和拆分任务...",
            source: multiAgentMessageSource
        )
        messages.append(systemMessage)

        let cancellable = engine.$currentPlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                self?.currentTaskPlan = plan
                if let plan {
                    self?.syncPipeline(with: plan)
                }
            }

        let result = await engine.processTask(input)

        cancellable.cancel()

        let assistantMessage = Message.assistant(result, source: multiAgentMessageSource)
        messages.append(assistantMessage)
    }

    // MARK: - Tool Call Loop Constants

    /// Maximum number of tool call iterations to prevent infinite loops
    static let maxIterations = 9999
    /// Maximum consecutive errors before aborting
    static let maxConsecutiveErrors = 5

    // MARK: - Bridge Properties & Methods (for ConversationLoop)

    /// Cancellation flag exposed to ConversationLoop
    var isCancelledFlag: Bool { isCancelled }

    /// Append a message to the conversation
    func appendMessage(_ message: Message) { messages.append(message) }

    /// Build context messages for the AI call
    func buildContextMessages() -> [Message] { getContextMessages() }

    /// Track token usage from an API response
    func trackTokenUsage(_ usage: AIResponse.Usage?) { trackUsage(usage) }

    /// Advance the active plan step on successful tool execution
    func advancePlanStep() {
        if !activePlan.isEmpty {
            currentPlanStep = min(currentPlanStep + 1, activePlan.count)
            currentSingleAgentPlan?.currentStep = currentPlanStep
            if currentPlanStep > 0 {
                currentSingleAgentPlan?.status = .executing
            }
        }
    }

    /// Clear the active task plan
    func clearPlan() { clearActivePlan() }

    /// Handle final assistant content when no tool calls are returned
    func handleFinalContent(_ content: String?) async -> Bool {
        guard let content, !content.isEmpty else {
            return true
        }

        if shouldVerifySingleAgentCompletion(for: content) {
            let verification = await verifySingleAgentCompletion(output: content)
            switch verification.status {
            case .verified, .unverified:
                let finalizedContent = attachVerificationNoteIfNeeded(
                    content: content,
                    verification: verification
                )
                finalizeAssistantMessage(finalizedContent)
                resetSingleAgentVerificationState()
                return true
            case .needsRetry:
                if isAwaitingSingleAgentVerificationRetry {
                    let finalizedContent = content + "\n\n未验证说明：\(verification.summary)"
                    finalizeAssistantMessage(finalizedContent)
                    resetSingleAgentVerificationState()
                    return true
                }

                isAwaitingSingleAgentVerificationRetry = true
                hideDraftAssistantMessage(matching: content)
                let auditMessage = Message.system("""
                [Verification Audit]
                当前答案不能直接视为已完成。

                审计结论：\(verification.summary)

                请基于本轮已经拿到的工具结果修订你的回答：
                - 只保留能被证据支持的结论
                - 把未验证部分明确标为“未验证”
                - 如果任务实际上未完成，直接说明缺什么验证或哪一步失败
                """, source: planningMessageSource, presentation: .internalOnly)
                messages.append(auditMessage)
                return false
            }
        }

        finalizeAssistantMessage(content)
        resetSingleAgentVerificationState()
        return true
    }

    /// Build error reflection + optional critic analysis for tool results
    func buildToolResultReflection(
        toolCalls: [ToolCall],
        results: [ToolResult],
        consecutiveErrors: Int
    ) async -> String {
        recordSingleAgentToolEvidence(toolCalls: toolCalls, results: results)

        var reflection = ""
        for (index, toolCall) in toolCalls.enumerated() {
            if index < results.count && results[index].status == .error {
                reflection += generateErrorReflection(toolCall: toolCall, result: results[index])
            }
        }
        if consecutiveErrors >= 2, let criticService {
            let errorMessages = results.filter { $0.status == .error }.compactMap { $0.error }
            if !errorMessages.isEmpty {
                let taskContext = activePlan.first ?? memory.session.currentTask ?? ""
                trackErrorRecoveryStage(retryCount: consecutiveErrors, analysis: nil)
                let criticFeedback = await criticService.analyze(
                    task: taskContext, errors: errorMessages,
                    output: messages.last?.content ?? "", systemPrompt: nil
                )
                updateErrorRecoveryStage(retryCount: consecutiveErrors, analysis: criticFeedback)
                completeErrorRecoveryStage()
                reflection += "\n\n[Critic Analysis]\n\(criticFeedback)"
            }
        }
        return reflection
    }

    // MARK: - Streaming Single Agent Processing

    private func processConversationLoopStreaming(aiService: AIService) async throws {
        let model = configuration.executionModel
        var thinkingStartTime: Date?
        var hasThinkingContent = false

        // 根据 Router 决策决定是否启用工具
        let enableTools: Bool
        if case .skip = currentRouterDecision {
            enableTools = false
            RioLogger.service.info("🔀 Router 决策为 skip，禁用工具调用")
        } else {
            enableTools = true
            RioLogger.service.info("🔀 Router 决策为 process（或无 Router），启用工具调用")
        }

        RioLogger.service.debug("📝 系统提示词长度: \(self.composedSingleAgentSystemPrompt.count) 字符，前200字: \(String(self.composedSingleAgentSystemPrompt.prefix(200)), privacy: .public)")
        RioLogger.service.debug("🔧 可用工具数: \(self.toolRegistry.getToolDefinitions().count)")

        try await ConversationLoop.run(engine: self) { contextMessages in
            // Pre-call setup: add streaming placeholder message
            let streamingMessage = Message.streamingAssistant(source: self.executionMessageSource)
            self.messages.append(streamingMessage)
            let streamingIndex = self.messages.count - 1
            let messageId = streamingMessage.id

            // Buffer coalesces rapid streaming chunks into fewer UI updates (~12fps)
            let buffer = StreamBuffer(interval: 0.08, maxCharsBeforeFlush: 500)

            // Unified flush handler — updates streaming message content & thinking
            let flushHandler: @MainActor @Sendable (String, String) async -> Void = { [weak self] content, thinking in
                guard let self, streamingIndex < self.messages.count else { return }
                if !content.isEmpty {
                    self.messages[streamingIndex].content += content
                }
                if !thinking.isEmpty {
                    let current = self.messages[streamingIndex].thinkingContent ?? ""
                    self.messages[streamingIndex].thinkingContent = current + thinking
                    // Update duration during streaming so it displays in real-time
                    if let start = thinkingStartTime {
                        self.messages[streamingIndex].thinkingDuration = Date().timeIntervalSince(start)
                    }
                }
            }

            let response: AIResponse
            do {
                response = try await aiService.sendMessageStreaming(
                    contextMessages,
                    tools: enableTools ? self.toolRegistry.getToolDefinitions() : [],
                    model: model,
                    maxTokens: self.configuration.maxTokens,
                    onChunk: { chunk in
                        buffer.appendContent(chunk)
                        await buffer.flushIfNeeded(update: flushHandler)
                    },
                    onThinkingChunk: { chunk in
                        if !hasThinkingContent {
                            hasThinkingContent = true
                            thinkingStartTime = Date()
                        }
                        buffer.appendThinking(chunk)
                        await buffer.flushIfNeeded(update: flushHandler)
                    }
                )
            } catch {
                if streamingIndex < self.messages.count {
                    self.messages.remove(at: streamingIndex)
                }
                throw error
            }

            // Flush remaining buffered content
            await buffer.flush(update: flushHandler)

            guard streamingIndex < self.messages.count else {
                // Message was removed (shouldn't happen), return empty to break loop
                return AIResponse(content: nil, reasoningContent: nil, toolCalls: nil, usage: nil)
            }

            // Record final thinking duration once streaming is complete
            if hasThinkingContent, let start = thinkingStartTime {
                self.messages[streamingIndex].thinkingDuration = Date().timeIntervalSince(start)
            }

            // Update streaming message with final response
            let hasReasoning = hasThinkingContent && (self.messages[streamingIndex].thinkingContent?.isEmpty == false)
            if let content = response.content, !content.isEmpty {
                self.messages[streamingIndex].content = content
                self.messages[streamingIndex].isStreaming = false
            } else if response.toolCalls == nil {
                if hasReasoning {
                    self.messages[streamingIndex].isStreaming = false
                } else if streamingIndex < self.messages.count {
                    self.messages.remove(at: streamingIndex)
                }
            }

            // Attach tool calls to streaming message if present
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                if let content = response.content, !content.isEmpty {
                    self.messages[streamingIndex].content = content
                    self.messages[streamingIndex].isStreaming = false
                    self.messages[streamingIndex].toolCalls = toolCalls
                } else {
                    let existingThinking = self.messages[streamingIndex].thinkingContent
                    let existingDuration = self.messages[streamingIndex].thinkingDuration
                    self.messages[streamingIndex] = Message(
                        id: messageId, role: .assistant,
                        content: response.content ?? "",
                        thinkingContent: existingThinking,
                        thinkingDuration: existingDuration,
                        toolCalls: toolCalls,
                        source: self.executionMessageSource
                    )
                }
            }

            return AIResponse(
                content: response.content,
                reasoningContent: response.reasoningContent,
                toolCalls: response.toolCalls,
                usage: response.usage
            )
        }
    }

    // MARK: - Non-streaming Single Agent Processing

    private func processConversationLoop(aiService: AIService) async throws {
        let model = configuration.executionModel

        // 根据 Router 决策决定是否启用工具
        let enableTools: Bool
        if case .skip = currentRouterDecision {
            enableTools = false
            RioLogger.service.info("🔀 Router 决策为 skip，禁用工具调用")
        } else {
            enableTools = true
            RioLogger.service.info("🔀 Router 决策为 process（或无 Router），启用工具调用")
        }

        RioLogger.service.debug("📝 系统提示词长度: \(self.composedSingleAgentSystemPrompt.count) 字符，前200字: \(String(self.composedSingleAgentSystemPrompt.prefix(200)), privacy: .public)")
        RioLogger.service.debug("🔧 可用工具数: \(self.toolRegistry.getToolDefinitions().count)")

        try await ConversationLoop.run(engine: self) { contextMessages in
            try await aiService.sendMessage(
                contextMessages,
                tools: enableTools ? self.toolRegistry.getToolDefinitions() : [],
                model: model,
                maxTokens: self.configuration.maxTokens
            )
        }
    }

    // MARK: - Token Tracking

    /// Estimated total cost for current session (USD)
    @Published var sessionCost: Double = 0.0

    /// Reset tracking for a new conversation
    private func resetUsageTracking() {
        tokenTracker.reset()
        sessionCost = 0.0
    }

    // MARK: - Context Management

    private func estimateTokens(_ text: String) -> Int {
        return tokenTracker.estimateTokens(text)
    }

    private func estimateMessageTokens(_ message: Message) -> Int {
        return contextBuilder.estimateMessageTokens(message)
    }

    /// Track usage from an API response and calculate running cost
    private func trackUsage(_ usage: AIResponse.Usage?) {
        guard let usage = usage else { return }
        tokenTracker.trackUsage(
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            model: configuration.executionModel
        )
        sessionCost = tokenTracker.sessionCost
    }

    /// Get a formatted summary of session token usage and cost
    func getSessionUsageSummary() -> String {
        return tokenTracker.getSessionSummary()
    }

    /// Get the estimated total tokens used in this conversation
    func getTotalTokensUsed() -> Int {
        // If we have actual usage data, prefer it
        let actualTotal = tokenTracker.accumulatedUsage.promptTokens + tokenTracker.accumulatedUsage.completionTokens
        if actualTotal > 0 { return actualTotal }
        // Otherwise estimate from messages
        return messages.reduce(0) { $0 + estimateMessageTokens($1) }
    }

    private func getContextMessages() -> [Message] {
        return contextBuilder.buildContextMessages(from: messages)
    }

    // MARK: - Tool Execution (internal for ConversationLoop)

    /// Tracks recent tool errors for pattern detection
    private var recentErrors: [(toolName: String, error: String, timestamp: Date)] = []

    // MARK: - Active Task Plan (single-agent mode)

    /// Active execution plan steps from TaskPlanner
    private var activePlan: [String] = []
    /// Current step index in the active plan
    private var currentPlanStep: Int = 0
    /// Analysis metadata for the active plan
    private var activePlanAnalysis: TaskPlanner.TaskAnalysis?

    private func clearActivePlan() {
        activePlan = []
        currentPlanStep = 0
        activePlanAnalysis = nil
        currentSingleAgentPlan = nil
    }

    private func publishSingleAgentPlanIfNeeded(
        input: String,
        analysis: TaskPlanner.TaskAnalysis
    ) {
        guard currentSingleAgentPlan == nil, !activePlan.isEmpty else { return }
        currentSingleAgentPlan = SingleAgentPlan(
            originalTask: input,
            steps: activePlan,
            currentStep: currentPlanStep,
            complexity: analysis.complexity,
            reasoning: analysis.reasoning,
            estimatedTime: analysis.estimatedTime,
            status: .planning
        )
    }

    private var composedSingleAgentSystemPrompt: String {
        SystemPromptComposer.compose(
            basePrompt: configuration.singleAgentSystemPrompt,
            scope: .singleAgent,
            availableTools: toolRegistry.getAllTools()
        )
    }

    private func shouldVerifySingleAgentCompletion(for content: String) -> Bool {
        guard !recentSingleAgentEvidence.isEmpty else { return false }

        let lower = content.lowercased()
        let completionSignals = [
            "已完成", "完成了", "修改了", "修复了", "通过了", "已更新",
            "done", "completed", "fixed", "updated", "passed", "implemented"
        ]
        return completionSignals.contains { lower.contains($0.lowercased()) } || !recentSingleAgentToolErrors.isEmpty
    }

    private func verifySingleAgentCompletion(output: String) async -> VerifierService.VerificationOutcome {
        guard let verifierService else {
            return await VerifierService(aiService: nil, model: "").verify(
                task: memory.session.currentTask ?? "",
                output: output,
                errors: recentSingleAgentToolErrors,
                evidence: recentSingleAgentEvidence,
                systemPrompt: composedSingleAgentSystemPrompt
            )
        }

        return await verifierService.verify(
            task: memory.session.currentTask ?? "",
            output: output,
            errors: recentSingleAgentToolErrors,
            evidence: recentSingleAgentEvidence,
            systemPrompt: composedSingleAgentSystemPrompt
        )
    }

    private func recordSingleAgentToolEvidence(toolCalls: [ToolCall], results: [ToolResult]) {
        for (index, toolCall) in toolCalls.enumerated() where index < results.count {
            let result = results[index]
            recentSingleAgentEvidence.append(formatSingleAgentEvidence(toolCall: toolCall, result: result))
            if result.status == .error, let error = result.error {
                recentSingleAgentToolErrors.append("[\(toolCall.name)] \(error)")
            }
        }

        if recentSingleAgentEvidence.count > 16 {
            recentSingleAgentEvidence = Array(recentSingleAgentEvidence.suffix(16))
        }
        if recentSingleAgentToolErrors.count > 8 {
            recentSingleAgentToolErrors = Array(recentSingleAgentToolErrors.suffix(8))
        }
    }

    private func formatSingleAgentEvidence(toolCall: ToolCall, result: ToolResult) -> String {
        let source = result.status == .error ? (result.error ?? "未知错误") : result.output
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.count > 500 ? String(trimmed.prefix(500)) + " ...[truncated]" : trimmed
        return """
        tool=\(toolCall.name)
        status=\(result.status.rawValue.uppercased())
        evidence=\(preview.isEmpty ? "（空输出）" : preview)
        """
    }

    private func attachVerificationNoteIfNeeded(
        content: String,
        verification: VerifierService.VerificationOutcome
    ) -> String {
        guard verification.status == .unverified else {
            return content
        }
        return content + "\n\n未验证说明：\(verification.summary)"
    }

    private func resetSingleAgentVerificationState() {
        recentSingleAgentEvidence.removeAll()
        recentSingleAgentToolErrors.removeAll()
        isAwaitingSingleAgentVerificationRetry = false
    }

    private func finalizeAssistantMessage(_ content: String) {
        if let lastIndex = messages.indices.reversed().first(where: { index in
            let message = messages[index]
            return message.role == .assistant
                && (message.toolCalls?.isEmpty ?? true)
                && (message.isStreaming || message.content == content)
        }) {
            messages[lastIndex].content = content
            messages[lastIndex].isStreaming = false
            if messages[lastIndex].source == nil {
                messages[lastIndex].source = executionMessageSource
            }
        } else {
            messages.append(Message.assistant(content, source: executionMessageSource))
        }
    }

    private func hideDraftAssistantMessage(matching content: String) {
        guard let lastIndex = messages.indices.reversed().first(where: { index in
            let message = messages[index]
            return message.role == .assistant
                && (message.toolCalls?.isEmpty ?? true)
                && (message.isStreaming || message.content == content)
        }) else {
            return
        }

        messages[lastIndex].isStreaming = false
        messages[lastIndex].presentation = .internalOnly
    }
    
    func executeToolCalls(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        let toolNames = toolCalls.map(\.name)
        executionStageToolNames = toolNames
        startExecutionStage(toolNames: toolNames)

        let results = await toolExecutor.executeToolCalls(toolCalls)

        updateExecutionProgress(
            completed: results.count,
            total: toolCalls.count,
            toolNames: toolNames
        )
        completeExecutionStage()
        return results
    }

    /// Generate reflection prompt when errors occur
    private func generateErrorReflection(toolCall: ToolCall, result: ToolResult) -> String {
        return toolExecutor.generateErrorReflection(toolCall: toolCall, result: result)
    }


    private func showConfirmation(
        title: String,
        message: String,
        allowsTrustForSession: Bool
    ) async -> ConfirmationResult {
        return await withCheckedContinuation { continuation in
            NotificationCenter.default.post(
                name: .showConfirmation,
                object: nil,
                userInfo: [
                    "title": title,
                    "message": message,
                    "allowsTrustForSession": allowsTrustForSession,
                    "continuation": continuation
                ]
            )
        }
    }

    // MARK: - Conversation Management

    func clearConversation() {
        messages.removeAll()
        error = nil
        currentToolExecution = nil
        currentTaskPlan = nil
        currentSingleAgentPlan = nil
        resetPipelineState(clearVisiblePipeline: true)
        pendingInitConfirmation = false
        pendingExecutionStrategyConfirmation = nil
        resetUsageTracking()
        memory.clearSession()
        clearActivePlan()
    }
    
    /// Auto-compact conversation when message count exceeds threshold
    private func autoCompactIfNeeded() async {
        let threshold = normalizedContextMessageLimit ?? 50
        guard conversationCompactor.shouldCompact(messageCount: messages.count, threshold: threshold) else {
            return
        }

        let keepRecent = min(max(threshold / 2, 10), 30)

        // Perform AI-powered compaction silently
        messages = await conversationCompactor.compact(
            messages: messages,
            keepRecent: keepRecent,
            showNotification: false
        )
    }

    /// Compact conversation by summarizing old messages with AI
    func compactConversation() async {
        messages = await conversationCompactor.compact(
            messages: messages,
            keepRecent: 20,
            showNotification: true
        )
    }

    func loadConversation(_ conversation: Conversation) {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        multiAgentEngine?.cancelProcessing()
        isProcessing = false
        isCancelled = true
        currentToolExecution = nil

        messages = conversation.messages
        workingDirectory = conversation.workingDirectory
        error = nil
        currentTaskPlan = nil
        currentSingleAgentPlan = nil
        resetPipelineState(clearVisiblePipeline: true)
        pendingExecutionStrategyConfirmation = nil
        pendingInitConfirmation = false
        resetUsageTracking()
    }

    func exportConversation() -> Conversation {
        var conversation = Conversation()
        for message in messages {
            conversation.addMessage(message)
        }
        return conversation
    }

    /// Export conversation as Markdown text
    func exportAsMarkdown() -> String {
        var md = "# Rio Agent 对话记录\n\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        md += "导出时间: \(formatter.string(from: Date()))\n"
        if let dir = workingDirectory {
            md += "工作目录: \(dir)\n"
        }
        md += "规划模型: \(configuration.planningModel)\n"
        md += "执行模型: \(configuration.executionModel)\n\n---\n\n"

        for message in messages where message.isVisibleInTranscript {
            switch message.role {
            case .user:
                md += "## 👤 User\n\n\(message.content)\n\n"
            case .assistant:
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    md += "<details><summary>💭 Thinking (\(String(format: "%.1f", (message.thinkingDuration ?? 0) * 1000))ms)</summary>\n\n\(thinking)\n\n</details>\n\n"
                }
                if !message.content.isEmpty {
                    md += "## 🤖 Assistant\n\n\(message.content)\n\n"
                }
                if let toolCalls = message.toolCalls {
                    for tc in toolCalls {
                        md += "### 🔧 Tool Call: `\(tc.name)`\n\n"
                        for (key, value) in tc.arguments.sorted(by: { $0.key < $1.key }) {
                            md += "- **\(key)**: `\(value.value)`\n"
                        }
                        md += "\n"
                    }
                }
            case .system:
                if !message.content.isEmpty {
                    md += "> ℹ️ \(message.content)\n\n"
                }
            }

            if let toolResults = message.toolResults {
                for tr in toolResults {
                    let icon = tr.status == .success ? "✅" : "❌"
                    md += "### \(icon) Tool Result\n\n```\n\(String(tr.output.prefix(500)))\n```\n\n"
                }
            }
        }

        return md
    }

    /// Export conversation to a file
    func exportToFile() -> String? {
        let markdown = exportAsMarkdown()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "rio_agent_\(formatter.string(from: Date())).md"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            self.error = "导出失败: \(error.localizedDescription)"
            return nil
        }
    }

    private var normalizedContextMessageLimit: Int? {
        let limit = configuration.maxContextMessages
        guard limit > 0, limit < 999 else { return nil }
        return limit
    }

    // MARK: - Pipeline Helpers

    private func updatePipelineUI() {
        currentPipeline = pipelineBuilder?.build()
    }

    private func resetPipelineState(clearVisiblePipeline: Bool) {
        pipelineBuilder = nil
        currentRouterStageId = nil
        currentTaskAnalysisStageId = nil
        currentDAGPlanningStageId = nil
        currentExecutionStageId = nil
        currentVerificationStageId = nil
        currentSynthesisStageId = nil
        currentErrorRecoveryStageId = nil
        executionStageToolNames = []
        executionSubsteps = [:]
        multiAgentExecutionSubsteps = [:]
        multiAgentVerificationSubsteps = [:]

        if clearVisiblePipeline {
            currentPipeline = nil
        }
    }

    /// 安全兜底：如果 Router 错误地将任务型消息判为 skip，
    /// 根据关键词检测覆盖为 process，防止工具被误禁用。
    private static func applySkipSafetyOverride(
        input: String,
        decision: RoutingDecision
    ) -> RoutingDecision {
        guard case .skip = decision else { return decision }

        let lower = input.lowercased()
        let taskKeywords = [
            // 中文关键词
            "项目", "代码", "文件", "目录", "结构", "探索", "分析", "修改",
            "修复", "重构", "实现", "创建", "删除", "搜索", "查找", "读取",
            "写入", "运行", "执行", "测试", "构建", "部署", "git",
            "查看", "检查", "了解", "接手", "业务", "代码库",
            // 英文关键词
            "project", "code", "file", "directory", "explore", "analyze",
            "modify", "fix", "refactor", "implement", "create", "delete",
            "search", "read", "write", "run", "execute", "test", "build",
            "deploy", "repository", "codebase"
        ]

        let matchedKeywords = taskKeywords.filter { lower.contains($0) }
        if matchedKeywords.count >= 2 {
            RioLogger.service.warning(
                "🔀 Router 判为 skip，但检测到 \(matchedKeywords.count) 个任务关键词 \(matchedKeywords.prefix(5).description, privacy: .public)，覆盖为 process"
            )
            return .routeToTarget(
                target: "process",
                params: [:],
                confidence: 0.6,
                reasoning: "skip 被安全兜底覆盖：检测到任务关键词"
            )
        }

        return decision
    }

    private func trackRouterStage(decision: RoutingDecision?) {
        guard let builder = pipelineBuilder else { return }

        if multiAgentConfig.router.enabled {
            let stageId = builder.addStage(.router)
            currentRouterStageId = stageId
            builder.startStage(stageId)
            updatePipelineUI()

            if let decision {
                switch decision {
                case .skip(let reason):
                    builder.updateStageDetails(stageId, details: .router(decision: "跳过工具调用", target: nil, confidence: nil))
                    builder.skipStage(stageId, reason: reason)
                case .routeToTarget(let target, _, let confidence, let reasoning):
                    builder.updateStageDetails(stageId, details: .router(decision: reasoning, target: target, confidence: confidence))
                    builder.completeStage(stageId)
                }
            } else {
                builder.completeStage(stageId)
            }
            updatePipelineUI()
        }
    }

    private func trackTaskAnalysisStage(analysis: TaskPlanner.TaskAnalysis) {
        guard let builder = pipelineBuilder else { return }

        let stageId = builder.addStage(.taskAnalysis)
        currentTaskAnalysisStageId = stageId
        builder.startStage(stageId)
        updatePipelineUI()

        let complexityStr: String
        switch analysis.complexity {
        case .simple: complexityStr = "简单"
        case .moderate: complexityStr = "中等"
        case .complex: complexityStr = "复杂"
        case .veryComplex: complexityStr = "非常复杂"
        }

        builder.updateStageDetails(stageId, details: .taskAnalysis(
            complexity: complexityStr,
            stepCount: analysis.estimatedSteps,
            estimatedTime: formatEstimatedTime(analysis.estimatedTime)
        ))
        builder.completeStage(stageId)
        updatePipelineUI()
    }

    private func syncPipeline(with plan: TaskPlan) {
        guard let builder = pipelineBuilder else { return }

        switch plan.status {
        case .planning:
            syncSingleStage(
                id: &currentDAGPlanningStageId,
                builder: builder,
                type: .dagPlanning,
                details: .dagPlanning(
                    subTaskCount: plan.subTasks.count,
                    workerCount: countAssignedWorkers(in: plan),
                    maxDepth: maxDependencyDepth(in: plan)
                ),
                status: .running
            )
        case .executing:
            syncSingleStage(
                id: &currentDAGPlanningStageId,
                builder: builder,
                type: .dagPlanning,
                details: .dagPlanning(
                    subTaskCount: plan.subTasks.count,
                    workerCount: countAssignedWorkers(in: plan),
                    maxDepth: maxDependencyDepth(in: plan)
                ),
                status: .completed
            )
            syncSingleStage(
                id: &currentExecutionStageId,
                builder: builder,
                type: .execution,
                details: .execution(
                    toolCalls: [],
                    completedCount: completedSubTaskCount(in: plan),
                    totalCount: plan.subTasks.count
                ),
                status: .running
            )
            syncExecutionSubsteps(for: plan, builder: builder)
            syncErrorRecoveryIfNeeded(plan: plan, builder: builder)
        case .verifying:
            completeErrorRecoveryStage()
            syncSingleStage(
                id: &currentExecutionStageId,
                builder: builder,
                type: .execution,
                details: .execution(
                    toolCalls: [],
                    completedCount: completedSubTaskCount(in: plan),
                    totalCount: plan.subTasks.count
                ),
                status: .completed
            )
            syncSingleStage(
                id: &currentVerificationStageId,
                builder: builder,
                type: .verification,
                details: .verification(
                    passedChecks: verifiedSubTaskCount(in: plan),
                    totalChecks: plan.subTasks.count
                ),
                status: .running
            )
            syncVerificationSubsteps(for: plan, builder: builder)
        case .synthesizing:
            syncSingleStage(
                id: &currentVerificationStageId,
                builder: builder,
                type: .verification,
                details: .verification(
                    passedChecks: verifiedSubTaskCount(in: plan),
                    totalChecks: plan.subTasks.count
                ),
                status: .completed
            )
            syncSingleStage(
                id: &currentSynthesisStageId,
                builder: builder,
                type: .synthesis,
                details: .synthesis(workerResults: plan.subTasks.count),
                status: .running
            )
        case .completed:
            syncSingleStage(
                id: &currentSynthesisStageId,
                builder: builder,
                type: .synthesis,
                details: .synthesis(workerResults: plan.subTasks.count),
                status: .completed
            )
        case .failed:
            failActivePipelineStage(builder: builder)
        }
    }

    private func syncExecutionSubsteps(for plan: TaskPlan, builder: PipelineBuilder) {
        guard let stageId = currentExecutionStageId else { return }

        for subTask in plan.subTasks {
            let label = pipelineLabel(for: subTask)
            let status = pipelineStatus(for: subTask.status, verificationStatus: subTask.verificationStatus)

            if multiAgentExecutionSubsteps[subTask.id] == nil {
                let substep = PipelineSubstep(title: label, status: status)
                multiAgentExecutionSubsteps[subTask.id] = substep.id
                builder.addSubstep(stageId, substep: substep)
            }

            if let substepId = multiAgentExecutionSubsteps[subTask.id] {
                builder.updateSubstep(stageId, substepId: substepId, status: status)
            }
        }

        updatePipelineUI()
    }

    private func syncVerificationSubsteps(for plan: TaskPlan, builder: PipelineBuilder) {
        guard let stageId = currentVerificationStageId else { return }

        for subTask in plan.subTasks {
            let label = pipelineLabel(for: subTask)
            let status = pipelineStatus(for: subTask.verificationStatus)

            if multiAgentVerificationSubsteps[subTask.id] == nil {
                let substep = PipelineSubstep(title: label, status: status)
                multiAgentVerificationSubsteps[subTask.id] = substep.id
                builder.addSubstep(stageId, substep: substep)
            }

            if let substepId = multiAgentVerificationSubsteps[subTask.id] {
                builder.updateSubstep(stageId, substepId: substepId, status: status)
            }
        }

        updatePipelineUI()
    }

    private func syncSingleStage(
        id: inout UUID?,
        builder: PipelineBuilder,
        type: PipelineStage.StageType,
        details: StageDetails,
        status: PipelineStageStatus
    ) {
        if id == nil {
            let stageId = builder.addStage(type, details: details)
            id = stageId
            builder.startStage(stageId)
        }

        guard let stageId = id else { return }
        builder.updateStageDetails(stageId, details: details)
        let currentStatus = builder.stageStatus(stageId)

        switch status {
        case .pending, .running:
            break
        case .completed:
            if currentStatus != .completed {
                builder.completeStage(stageId)
            }
        case .failed:
            if currentStatus != .failed {
                builder.failStage(stageId, error: "任务执行失败")
            }
        case .skipped:
            if currentStatus != .skipped {
                builder.skipStage(stageId, reason: "未执行")
            }
        }

        updatePipelineUI()
    }

    private func syncErrorRecoveryIfNeeded(plan: TaskPlan, builder: PipelineBuilder) {
        let retryCount = plan.subTasks.map(\.retryCount).max() ?? 0
        guard retryCount > 0 else { return }

        let retryingTasks = plan.subTasks
            .filter { $0.retryCount > 0 }
            .map { $0.assignedWorker?.name ?? $0.workerType.displayName }
            .sorted()
            .joined(separator: ", ")

        syncSingleStage(
            id: &currentErrorRecoveryStageId,
            builder: builder,
            type: .errorRecovery,
            details: .errorRecovery(
                retryCount: retryCount,
                analysisResult: retryingTasks.isEmpty ? "Worker 正在根据 Critic 反馈重试。" : "重试任务: \(retryingTasks)"
            ),
            status: .running
        )
    }

    private func failActivePipelineStage(builder: PipelineBuilder) {
        if let stageId = currentSynthesisStageId, builder.stageStatus(stageId) == .running {
            builder.failStage(stageId, error: "结果汇总失败")
        } else if let stageId = currentVerificationStageId, builder.stageStatus(stageId) == .running {
            builder.failStage(stageId, error: "验证阶段失败")
        } else if let stageId = currentExecutionStageId, builder.stageStatus(stageId) == .running {
            builder.failStage(stageId, error: "执行阶段失败")
        } else if let stageId = currentDAGPlanningStageId, builder.stageStatus(stageId) == .running {
            builder.failStage(stageId, error: "DAG 规划失败")
        }

        updatePipelineUI()
    }

    private func failActivePipelineStage() {
        guard let builder = pipelineBuilder else { return }
        failActivePipelineStage(builder: builder)
    }

    private func countAssignedWorkers(in plan: TaskPlan) -> Int {
        Set(plan.subTasks.compactMap { $0.assignedWorker?.id }).count
    }

    private func completedSubTaskCount(in plan: TaskPlan) -> Int {
        plan.subTasks.filter { $0.status == .completed }.count
    }

    private func verifiedSubTaskCount(in plan: TaskPlan) -> Int {
        plan.subTasks.filter { $0.verificationStatus == .verified }.count
    }

    private func maxDependencyDepth(in plan: TaskPlan) -> Int {
        let lookup = Dictionary(uniqueKeysWithValues: plan.subTasks.map { ($0.id, $0) })

        func depth(of id: UUID, visiting: Set<UUID> = []) -> Int {
            guard let task = lookup[id] else { return 0 }
            guard !visiting.contains(id) else { return 0 }
            let next = visiting.union([id])
            let childDepths = task.dependencies.map { depth(of: $0, visiting: next) }
            return 1 + (childDepths.max() ?? 0)
        }

        return plan.subTasks.map { depth(of: $0.id) }.max() ?? 0
    }

    private func startExecutionStage(toolNames: [String]) {
        guard let builder = pipelineBuilder else { return }
        guard currentExecutionStageId == nil else { return }
        executionSubsteps = [:]

        let stageId = builder.addStage(.execution, details: .execution(
            toolCalls: toolNames,
            completedCount: 0,
            totalCount: toolNames.count
        ))
        currentExecutionStageId = stageId
        builder.startStage(stageId)
        updatePipelineUI()
    }

    private func updateExecutionProgress(completed: Int, total: Int, toolNames: [String]) {
        guard let builder = pipelineBuilder, let stageId = currentExecutionStageId else { return }

        builder.updateStageDetails(stageId, details: .execution(
            toolCalls: toolNames,
            completedCount: completed,
            totalCount: total
        ))
        updatePipelineUI()
    }

    private func completeExecutionStage() {
        guard let builder = pipelineBuilder, let stageId = currentExecutionStageId else { return }
        builder.completeStage(stageId)
        currentExecutionStageId = nil
        executionSubsteps = [:]
        updatePipelineUI()
    }

    private func syncExecutionSubstep(with state: ToolExecutionState?) {
        guard let builder = pipelineBuilder, let stageId = currentExecutionStageId else { return }
        guard let state else { return }

        let toolCall: ToolCall
        let status: PipelineStageStatus
        var duration: TimeInterval?

        switch state {
        case .pending(let currentToolCall):
            toolCall = currentToolCall
            status = .pending
        case .confirming(let currentToolCall):
            toolCall = currentToolCall
            status = .pending
        case .executing(let currentToolCall):
            toolCall = currentToolCall
            status = .running
        case .completed(let currentToolCall, let result):
            toolCall = currentToolCall
            status = pipelineStatus(from: result.status)
        case .failed(let currentToolCall, _):
            toolCall = currentToolCall
            status = .failed
        }

        if executionSubsteps[toolCall.id] == nil {
            let substep = PipelineSubstep(
                title: pipelineToolLabel(for: toolCall),
                status: status
            )
            executionSubsteps[toolCall.id] = (substep.id, Date())
            builder.addSubstep(stageId, substep: substep)
        }

        if let substep = executionSubsteps[toolCall.id],
           status == .completed || status == .failed || status == .skipped {
            duration = Date().timeIntervalSince(substep.startTime)
        }

        if let substepId = executionSubsteps[toolCall.id]?.id {
            builder.updateSubstep(stageId, substepId: substepId, status: status, duration: duration)
        }

        let completedCount = builder.build().stages
            .first(where: { $0.id == stageId })?
            .substeps
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .skipped }
            .count ?? 0

        updateExecutionProgress(
            completed: completedCount,
            total: executionStageToolNames.count,
            toolNames: executionStageToolNames
        )
    }

    private func pipelineToolLabel(for toolCall: ToolCall) -> String {
        if let path = toolCall.arguments["path"]?.value as? String, !path.isEmpty {
            return "\(toolCall.name): \(path)"
        }
        return toolCall.name
    }

    private func pipelineStatus(from resultStatus: ToolResultStatus) -> PipelineStageStatus {
        switch resultStatus {
        case .success:
            return .completed
        case .error:
            return .failed
        case .cancelled:
            return .skipped
        }
    }

    private func pipelineStatus(for subTaskStatus: SubTaskStatus, verificationStatus: VerificationStatus) -> PipelineStageStatus {
        switch subTaskStatus {
        case .pending:
            return .pending
        case .running:
            return .running
        case .completed:
            return verificationStatus == .needsRetry ? .failed : .completed
        case .failed:
            return .failed
        }
    }

    private func pipelineStatus(for verificationStatus: VerificationStatus) -> PipelineStageStatus {
        switch verificationStatus {
        case .unverified:
            return .pending
        case .verified:
            return .completed
        case .needsRetry:
            return .failed
        }
    }

    private func pipelineLabel(for subTask: SubTask) -> String {
        let workerName = subTask.assignedWorker?.name ?? subTask.workerType.displayName
        let summary = subTask.description.replacingOccurrences(of: "\n", with: " ")
        let trimmed = summary.count > 48 ? String(summary.prefix(48)) + "..." : summary
        return "\(workerName): \(trimmed)"
    }

    private func trackErrorRecoveryStage(retryCount: Int, analysis: String?) {
        guard let builder = pipelineBuilder else { return }
        if let stageId = currentErrorRecoveryStageId {
            builder.updateStageDetails(stageId, details: .errorRecovery(
                retryCount: retryCount,
                analysisResult: analysis
            ))
            if builder.stageStatus(stageId) != .running {
                builder.startStage(stageId)
            }
            updatePipelineUI()
            return
        }

        let stageId = builder.addStage(.errorRecovery, details: .errorRecovery(
            retryCount: retryCount,
            analysisResult: analysis
        ))
        currentErrorRecoveryStageId = stageId
        builder.startStage(stageId)
        updatePipelineUI()
    }

    private func updateErrorRecoveryStage(retryCount: Int, analysis: String?) {
        guard let builder = pipelineBuilder, let stageId = currentErrorRecoveryStageId else { return }
        builder.updateStageDetails(stageId, details: .errorRecovery(
            retryCount: retryCount,
            analysisResult: analysis
        ))
        updatePipelineUI()
    }

    private func completeErrorRecoveryStage() {
        guard let builder = pipelineBuilder, let stageId = currentErrorRecoveryStageId else { return }
        builder.completeStage(stageId)
        currentErrorRecoveryStageId = nil
        updatePipelineUI()
    }

    private func formatEstimatedTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }

        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainingSeconds)s"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showConfirmation = Notification.Name("showConfirmation")
}

// MARK: - Stream Buffer (coalesces rapid streaming chunks into fewer UI updates)

@MainActor
class StreamBuffer {
    private var contentAccumulator = ""
    private var thinkingAccumulator = ""
    private var lastFlush = Date()
    private let interval: TimeInterval
    private let maxCharsBeforeFlush: Int

    init(interval: TimeInterval = 0.08, maxCharsBeforeFlush: Int = 500) {
        self.interval = interval
        self.maxCharsBeforeFlush = maxCharsBeforeFlush
    }

    func appendContent(_ chunk: String) { contentAccumulator += chunk }
    func appendThinking(_ chunk: String) { thinkingAccumulator += chunk }

    private var shouldFlushNow: Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFlush)

        // 达到最大字符数限制时立即刷新，不管时间间隔
        if contentAccumulator.count >= maxCharsBeforeFlush { return true }
        if thinkingAccumulator.count >= maxCharsBeforeFlush { return true }

        // 达到时间间隔后刷新
        return elapsed >= interval
    }

    func flushIfNeeded(update: @MainActor @Sendable (_ content: String, _ thinking: String) async -> Void) async {
        guard shouldFlushNow,
              !contentAccumulator.isEmpty || !thinkingAccumulator.isEmpty else { return }
        let c = contentAccumulator; contentAccumulator = ""
        let t = thinkingAccumulator; thinkingAccumulator = ""
        lastFlush = Date()
        await update(c, t)
    }

    func flush(update: @MainActor @Sendable (_ content: String, _ thinking: String) async -> Void) async {
        guard !contentAccumulator.isEmpty || !thinkingAccumulator.isEmpty else { return }
        let c = contentAccumulator; contentAccumulator = ""
        let t = thinkingAccumulator; thinkingAccumulator = ""
        await update(c, t)
    }
}
