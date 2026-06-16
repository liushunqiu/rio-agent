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

    @Published var messages: [Message] = []
    @Published var isProcessing = false
    @Published var error: String?
    @Published var currentToolExecution: ToolExecutionState?
    @Published var currentTaskPlan: TaskPlan?

    /// 当前正在执行的工具调用 ID，用于驱动文件操作动画
    var currentToolCallId: String? {
        return currentToolExecution?.id
    }
    var pendingInitConfirmation = false
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
    var configuration: AIConfiguration
    var multiAgentConfig: MultiAgentConfig
    private var multiAgentEngine: MultiAgentEngine?

    /// 优化的 Token 追踪器（准确度提升 30%，性能提升 3-5x）
    private let tokenTracker = TokenTracker()

    /// 对话压缩器（智能压缩历史消息）
    private lazy var conversationCompactor: ConversationCompactor = {
        return ConversationCompactor(aiService: planningService, model: configuration.planningModel)
    }()

    /// 上下文构建器（智能管理消息上下文和 Token 预算）
    private lazy var contextBuilder: ContextBuilder = {
        return ContextBuilder(tokenTracker: tokenTracker, model: configuration.executionModel, workingDirectory: workingDirectory)
    }()

    /// 工具执行器（管理工具调用的执行流程）
    private lazy var toolExecutor: ToolExecutor = {
        let executor = ToolExecutor(toolRegistry: toolRegistry, memory: memory)
        executor.onExecutionStateChanged = { [weak self] state in
            self?.currentToolExecution = state
        }
        return executor
    }()

    /// Called when a user message is added to the conversation (for immediate title update)
    var onUserMessageAdded: (() -> Void)?

    /// The currently running processing task, used for cancellation
    private var currentProcessingTask: Task<Void, Never>?
    /// Flag to signal cancellation to the processing loop
    private var isCancelled = false

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
    }

    private func createService(configSetId: UUID?) -> AIService? {
        guard let id = configSetId,
              let data = UserDefaults.standard.data(forKey: "config_sets_v2"),
              let sets = try? JSONDecoder().decode([ConfigSet].self, from: data),
              let configSet = sets.first(where: { $0.id == id }) else {
            return nil
        }
        let provider = configSet.provider
        let baseURL = configSet.baseURL
        let apiKey = configSet.loadAPIKey()
        
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
        let engine = MultiAgentEngine(config: multiAgentConfig, toolRegistry: toolRegistry, criticService: criticService)
        var keys: [AIProvider: String] = [:]
        var urls: [AIProvider: String] = [:]
        let configManager = ConfigSetManager.shared
        for configSet in configManager.configSets {
            let key = configSet.loadAPIKey()
            if !key.isEmpty {
                keys[configSet.provider] = key
                urls[configSet.provider] = configSet.baseURL
            }
        }
        engine.configureAPIKeys(keys, baseUrls: urls)
        multiAgentEngine = engine
    }

    func updateConfiguration(_ newConfig: AIConfiguration) {
        configuration = newConfig
        setupAIService()
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
            return buildMultiAgentRuntimeRoles(
                config: multiAgentEngine.currentConfig,
                plan: currentTaskPlan
            )
        }
        return buildSingleAgentRuntimeRoles()
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

    // MARK: - Configuration Persistence

    private func buildSingleAgentRuntimeRoles() -> [RuntimeModelRole] {
        var roles: [RuntimeModelRole] = []

        if multiAgentConfig.router.enabled {
            let routerConfigSet = configSet(for: multiAgentConfig.router.configSetId)
            let routerModel = multiAgentConfig.router.model.isEmpty
                ? configuration.executionModel
                : multiAgentConfig.router.model
            let routerProvider = routerConfigSet?.provider.displayName
                ?? configuration.executionProvider.displayName
            roles.append(RuntimeModelRole(
                id: "router",
                title: "Router",
                providerName: routerProvider,
                modelName: routerModel,
                isActive: isProcessing && messages.last?.role != .assistant
            ))
        }

        let planningActive = isProcessing && !usesMultiAgentForCurrentPlan
        roles.append(RuntimeModelRole(
            id: "planning",
            title: "Planning",
            providerName: configuration.planningProvider.displayName,
            modelName: configuration.planningModel,
            isActive: planningActive
        ))

        roles.append(RuntimeModelRole(
            id: "execution",
            title: "Execution",
            providerName: configuration.executionProvider.displayName,
            modelName: configuration.executionModel,
            isActive: isProcessing && !usesMultiAgentForCurrentPlan
        ))

        return deduplicatedRoles(roles)
    }

    private func buildMultiAgentRuntimeRoles(
        config: MultiAgentConfig,
        plan: TaskPlan?
    ) -> [RuntimeModelRole] {
        var activeIds = Set<String>()
        if let plan {
            switch plan.status {
            case .planning, .synthesizing, .verifying:
                activeIds.insert("orchestrator")
            case .executing:
                let runningWorkers = plan.subTasks.compactMap { subTask -> String? in
                    guard subTask.status == .running, let worker = subTask.assignedWorker else { return nil }
                    return "worker-\(worker.id.uuidString)"
                }
                if runningWorkers.isEmpty {
                    activeIds.insert("orchestrator")
                } else {
                    runningWorkers.forEach { activeIds.insert($0) }
                }
            case .completed, .failed:
                break
            }
        }

        var roles: [RuntimeModelRole] = [
            RuntimeModelRole(
                id: "orchestrator",
                title: "Orchestrator",
                providerName: config.orchestrator.provider.displayName,
                modelName: config.orchestrator.model,
                isActive: activeIds.contains("orchestrator")
            )
        ]

        for worker in config.workers where worker.isEnabled {
            roles.append(RuntimeModelRole(
                id: "worker-\(worker.id.uuidString)",
                title: worker.name,
                providerName: worker.provider.displayName,
                modelName: worker.model,
                isActive: activeIds.contains("worker-\(worker.id.uuidString)")
            ))
        }

        return deduplicatedRoles(roles)
    }

    private func deduplicatedRoles(_ roles: [RuntimeModelRole]) -> [RuntimeModelRole] {
        roles.filter { !$0.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

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
            setupMultiAgentEngine()
        } catch {
            RioLogger.config.error("⚠️ 加载 Multi-Agent 配置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public Methods

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
                let cancelMessage = Message.system("已取消重新生成 AGENT.md。")
                messages.append(cancelMessage)
            }
            return
        }

        // MARK: - Router interception (本地路由模型前置拦截)
        var routerSkip = false
        if multiAgentConfig.router.enabled {
            RioLogger.service.info("🔀 Router 已启用，开始路由分析...")
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
                    switch decision {
                    case .skip(let reason):
                        RioLogger.service.info("🔀 Router 决策: SKIP - \(reason, privacy: .public)")
                        let userMessage = Message.user(input)
                        messages.append(userMessage)
                        onUserMessageAdded?()
                        let response = Message.assistant(reason)
                        messages.append(response)
                        routerSkip = true
                    case .routeToTarget(let target, _, let confidence, let reasoning):
                        RioLogger.service.info("🔀 Router 决策: \(target, privacy: .public) (置信度: \(confidence, privacy: .public)) - \(reasoning, privacy: .public)")
                    }
                } else {
                    RioLogger.service.warning("⚠️ Router 调用失败，继续执行标准流程")
                }
            } else {
                RioLogger.service.warning("⚠️ Router 已启用但未配置 configSetId 或 API Key，跳过路由")
            }
        } else {
            RioLogger.service.debug("⏭️ Router 未启用，跳过路由阶段")
        }
        guard !routerSkip else { return }
        
        // Analyze task complexity and generate plan if needed
        RioLogger.agent.info("📊 开始分析任务复杂度...")
        let taskAnalysis = await TaskPlanner.analyzeTaskEnhanced(trimmedInput, memory: memory, aiService: planningService, model: configuration.planningModel)
        RioLogger.agent.info("📊 任务复杂度: \(taskAnalysis.complexity, privacy: .public), 预计步骤: \(taskAnalysis.estimatedSteps, privacy: .public)")

        // For complex tasks, generate a plan and inform the user
        if taskAnalysis.complexity != .simple {
            RioLogger.agent.info("📝 任务复杂度非 simple，生成执行计划...")
            let plan = TaskPlanner.decomposeTask(trimmedInput, memory: memory)
            let formattedPlan = TaskPlanner.formatPlanForExecution(plan, analysis: taskAnalysis)
            RioLogger.agent.info("📝 生成计划包含 \(plan.count, privacy: .public) 个步骤")

            // Add plan to messages for user to see
            let planMessage = Message.system(formattedPlan)
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
            let guidanceMessage = Message.system(guidance)
            messages.append(guidanceMessage)
        } else {
            RioLogger.agent.info("⏭️ 任务复杂度为 simple，跳过计划生成")
            clearActivePlan()
        }

        isProcessing = true
        isCancelled = false
        error = nil
        currentTaskPlan = nil

        let userMessage = Message.user(input)
        messages.append(userMessage)
        onUserMessageAdded?()

        toolRegistry.setupConfirmationCallbacks { [weak self] title, message in
            return await self?.showConfirmation(title: title, message: message) ?? .denied
        }

        do {
            // Unified pipeline: Planner complexity decides execution strategy
            // 降低 Multi-Agent 触发阈值：moderate 及以上都可以使用 Multi-Agent
            let useDAG = taskAnalysis.complexity == .moderate || taskAnalysis.complexity == .complex || taskAnalysis.complexity == .veryComplex

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
        } catch {
            self.error = error.localizedDescription
        }

        // Auto-compact if too many messages (save tokens)
        await autoCompactIfNeeded()
        
        isProcessing = false
    }

    /// Stop the current processing (cancel ongoing API calls and tool executions)
    func stopProcessing() {
        guard isProcessing else { return }
        isCancelled = true
        isProcessing = false
        currentToolExecution = nil

        let cancelMessage = Message.system("⏹ 已停止当前任务。")
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
        case "/compact", "/summarize":
            await compactConversation()
        case "/export":
            if let path = exportToFile() {
                let msg = Message.system("✅ 对话已导出到: \(path)")
                messages.append(msg)
            }
        case "/help":
            showHelp()
        default:
            let errorMessage = Message.system("未知命令: \(cmd)\n输入 /help 查看可用命令")
            messages.append(errorMessage)
        }
    }

    private func initProject() async {
        guard let dir = workingDirectory else {
            let errorMessage = Message.system("请先设置工作目录，然后再执行 /init 命令")
            messages.append(errorMessage)
            return
        }

        let agentMDPath = "\(dir)/AGENT.md"

        // 检查 AGENT.md 是否已存在
        if FileManager.default.fileExists(atPath: agentMDPath) {
            let confirmMessage = Message.system("⚠️ AGENT.md 已存在于 \(dir)\n\n是否要重新生成？这将覆盖现有文件。\n\n回复「是」或「yes」确认重新生成，或回复其他内容取消。")
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
                  开始新的对话
        
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
        """)
        messages.append(helpMessage)
    }

    // MARK: - Multi-Agent Processing

    private func processWithMultiAgent(input: String, engine: MultiAgentEngine) async throws {
        let systemMessage = Message.system("Multi-Agent 模式已启动，正在分析和拆分任务...")
        messages.append(systemMessage)

        let cancellable = engine.$currentPlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                self?.currentTaskPlan = plan
            }

        let result = await engine.processTask(input)

        cancellable.cancel()

        let assistantMessage = Message.assistant(result)
        messages.append(assistantMessage)

        currentTaskPlan = nil
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
        }
    }

    /// Clear the active task plan
    func clearPlan() { clearActivePlan() }

    /// Handle final assistant content when no tool calls are returned
    func handleFinalContent(_ content: String?) {
        if let content, !content.isEmpty {
            messages.append(Message.assistant(content))
        }
    }

    /// Build error reflection + optional critic analysis for tool results
    func buildToolResultReflection(
        toolCalls: [ToolCall],
        results: [ToolResult],
        consecutiveErrors: Int
    ) async -> String {
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
                let criticFeedback = await criticService.analyze(
                    task: taskContext, errors: errorMessages,
                    output: messages.last?.content ?? "", systemPrompt: nil
                )
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

        try await ConversationLoop.run(engine: self) { contextMessages in
            // Pre-call setup: add streaming placeholder message
            let streamingMessage = Message.streamingAssistant()
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
                    tools: self.toolRegistry.getToolDefinitions(),
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
                        toolCalls: toolCalls
                    )
                }
            }

            return AIResponse(
                content: nil,
                reasoningContent: response.reasoningContent,
                toolCalls: response.toolCalls,
                usage: response.usage
            )
        }
    }

    // MARK: - Non-streaming Single Agent Processing

    private func processConversationLoop(aiService: AIService) async throws {
        let model = configuration.executionModel
        try await ConversationLoop.run(engine: self) { contextMessages in
            try await aiService.sendMessage(
                contextMessages,
                tools: self.toolRegistry.getToolDefinitions(),
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
    }
    
    func executeToolCalls(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        return await toolExecutor.executeToolCalls(toolCalls)
    }

    /// Generate reflection prompt when errors occur
    private func generateErrorReflection(toolCall: ToolCall, result: ToolResult) -> String {
        return toolExecutor.generateErrorReflection(toolCall: toolCall, result: result)
    }


    private func showConfirmation(title: String, message: String) async -> ConfirmationResult {
        return await withCheckedContinuation { continuation in
            NotificationCenter.default.post(
                name: .showConfirmation,
                object: nil,
                userInfo: [
                    "title": title,
                    "message": message,
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
        pendingInitConfirmation = false
        memory.clearSession()
        clearActivePlan()
    }
    
    /// Auto-compact conversation when message count exceeds threshold
    private func autoCompactIfNeeded() async {
        guard conversationCompactor.shouldCompact(messageCount: messages.count, threshold: 50) else {
            return
        }

        // Perform AI-powered compaction silently
        messages = await conversationCompactor.compact(
            messages: messages,
            keepRecent: 30,
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
        messages = conversation.messages
        workingDirectory = conversation.workingDirectory
        error = nil
        currentTaskPlan = nil
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

        for message in messages {
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
                md += "> ℹ️ \(message.content)\n\n"
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
