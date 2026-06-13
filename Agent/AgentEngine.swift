import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class AgentEngine: ObservableObject {
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
    let learningSystem = IntelligentLearningSystem()
    let intelligentConfig = IntelligentAssistantConfigManager.shared
    private var aiService: AIService?
    var configuration: AIConfiguration
    var multiAgentConfig: MultiAgentConfig
    private var multiAgentEngine: MultiAgentEngine?

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
        let baseURL = configuration.baseURL

        // 自定义端点（OpenAI Compatible）允许空 API Key（如 Ollama 等本地服务）
        if configuration.activeProvider == .openAICompatible {
            guard !baseURL.isEmpty else { return }
            let apiKey = configuration.apiKey ?? ""
            aiService = AIServiceFactory.createService(
                provider: configuration.activeProvider,
                apiKey: apiKey,
                baseURL: baseURL
            )
        } else {
            guard let apiKey = configuration.apiKey else { return }
            aiService = AIServiceFactory.createService(
                provider: configuration.activeProvider,
                apiKey: apiKey,
                baseURL: baseURL
            )
        }
    }

    private func setupMultiAgentEngine() {
        if multiAgentConfig.isEnabled {
            let engine = MultiAgentEngine(config: multiAgentConfig, toolRegistry: toolRegistry)
            // Pass API keys for multi-agent services
            var keys: [AIProvider: String] = [:]
            var urls: [AIProvider: String] = [:]
            if let claudeKey = configuration.getAPIKey(for: .claude), !claudeKey.isEmpty {
                keys[.claude] = claudeKey
                urls[.claude] = configuration.claudeConfig.baseURL
            }
            if let openAIKey = configuration.getAPIKey(for: .openAI), !openAIKey.isEmpty {
                keys[.openAI] = openAIKey
                urls[.openAI] = configuration.openAIConfig.baseURL
            }
            if !configuration.compatibleConfig.baseURL.isEmpty {
                if let compatKey = configuration.getAPIKey(for: .openAICompatible), !compatKey.isEmpty {
                    keys[.openAICompatible] = compatKey
                }
                urls[.openAICompatible] = configuration.compatibleConfig.baseURL
            }
            engine.configureAPIKeys(keys, baseUrls: urls)
            multiAgentEngine = engine
        } else {
            multiAgentEngine = nil
        }
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

    // MARK: - Configuration Persistence

    private let configurationKey = "ai_configuration"
    private let multiAgentConfigKey = "multi_agent_configuration"

    func saveConfiguration() {
        do {
            let data = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(data, forKey: configurationKey)
            RioLogger.config.info("💾 配置已保存 - 提供商: \(self.configuration.activeProvider.displayName, privacy: .public), 模型: \(self.configuration.model, privacy: .public)")
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
            RioLogger.config.info("📂 已加载配置 - 提供商: \(self.configuration.activeProvider.displayName, privacy: .public), 模型: \(self.configuration.model, privacy: .public)")
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
        
        // Analyze task complexity and generate plan if needed
        if intelligentConfig.config.enableTaskPlanning {
            let taskAnalysis = TaskPlanner.analyzeTask(trimmedInput, memory: memory)
            
            // For complex tasks, generate a plan and inform the user
            if taskAnalysis.complexity != .simple && intelligentConfig.config.showTaskPlan {
                let plan = TaskPlanner.decomposeTask(trimmedInput, memory: memory)
                let formattedPlan = TaskPlanner.formatPlan(plan)
                
                // Add plan to messages for user to see
                let planMessage = Message.system(formattedPlan)
                messages.append(planMessage)
                
                // Add execution guidance
                let guidance = TaskPlanner.generateExecutionGuidance(
                    analysis: taskAnalysis,
                    currentStep: nil,
                    totalSteps: plan.count
                )
                let guidanceMessage = Message.system(guidance)
                messages.append(guidanceMessage)
            }
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
            if multiAgentConfig.isEnabled, let multiAgentEngine = multiAgentEngine {
                try await processWithMultiAgent(input: input, engine: multiAgentEngine)
            } else {
                guard let aiService = aiService else {
                    if configuration.activeProvider == .openAICompatible {
                        error = "请先在设置中配置 API 端点地址"
                    } else {
                        error = "请先在设置中配置 API Key"
                    }
                    isProcessing = false
                    return
                }

                if configuration.isStreaming {
                    try await processConversationLoopStreaming(aiService: aiService)
                } else {
                    try await processConversationLoop(aiService: aiService)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

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

        guard let aiService = aiService else {
            if configuration.activeProvider == .openAICompatible {
                error = "请先在设置中配置 API 端点地址"
            } else {
                error = "请先在设置中配置 API Key"
            }
            isProcessing = false
            return
        }

        do {
            if configuration.isStreaming {
                try await processConversationLoopStreaming(aiService: aiService)
            } else {
                try await processConversationLoop(aiService: aiService)
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
        
        /export  - 导出当前对话为 Markdown 文件
                  保存到用户选择的位置
        
        /help    - 显示此帮助信息
                  查看所有可用命令
        
        💡 提示:
        - 命令必须以 / 开头
        - 命令不区分大小写
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

    // MARK: - Tool Call Loop Limit

    /// Maximum number of tool call iterations to prevent infinite loops
    private static let maxToolCallIterations = 9999
    /// Maximum consecutive errors before aborting
    private static let maxConsecutiveErrors = 5

    // MARK: - Streaming Single Agent Processing

    private func processConversationLoopStreaming(aiService: AIService) async throws {
        let model = configuration.model
        let toolDefinitions = toolRegistry.getToolDefinitions()
        var iterationCount = 0
        var consecutiveErrors = 0

        while true {
            // Check for cancellation
            guard !isCancelled else { break }

            iterationCount += 1

            // Prevent infinite tool call loops
            guard iterationCount <= Self.maxToolCallIterations else {
                let warningMsg = Message.system("⚠️ 已达到最大工具调用次数上限（\(Self.maxToolCallIterations) 次），已自动停止。如需继续，请直接描述下一步操作。")
                messages.append(warningMsg)
                break
            }
            let contextMessages = getContextMessages()
            let streamingMessage = Message.streamingAssistant()
            messages.append(streamingMessage)
            let streamingIndex = messages.count - 1
            let messageId = streamingMessage.id

            var thinkingStartTime: Date?
            var hasThinkingContent = false
            // Buffer to coalesce rapid streaming chunks into fewer UI updates
            // 使用更大的缓冲区和更长的间隔来减少UI更新频率
            let buffer = StreamBuffer(interval: 0.05, maxCharsBeforeFlush: 100)

            let response: AIResponse
            do {
                response = try await aiService.sendMessageStreaming(
                    contextMessages,
                    tools: toolDefinitions,
                    model: model,
                    maxTokens: configuration.maxTokens,
                    onChunk: { [weak self] chunk in
                        buffer.appendContent(chunk)
                        await buffer.flushIfNeeded { content, thinking in
                            guard let self = self, streamingIndex < self.messages.count else { return }
                            if !content.isEmpty {
                                self.messages[streamingIndex].content += content
                            }
                            if !thinking.isEmpty {
                                let current = self.messages[streamingIndex].thinkingContent ?? ""
                                self.messages[streamingIndex].thinkingContent = current + thinking
                            }
                        }
                    },
                    onThinkingChunk: { [weak self] chunk in
                        if !hasThinkingContent {
                            hasThinkingContent = true
                            thinkingStartTime = Date()
                        }
                        buffer.appendThinking(chunk)
                        await buffer.flushIfNeeded { content, thinking in
                            guard let self = self, streamingIndex < self.messages.count else { return }
                            if !content.isEmpty {
                                self.messages[streamingIndex].content += content
                            }
                            if !thinking.isEmpty {
                                let current = self.messages[streamingIndex].thinkingContent ?? ""
                                self.messages[streamingIndex].thinkingContent = current + thinking
                                if let start = thinkingStartTime {
                                    self.messages[streamingIndex].thinkingDuration = Date().timeIntervalSince(start)
                                }
                            }
                        }
                    }
                )
            } catch {
                if streamingIndex < messages.count {
                    messages.remove(at: streamingIndex)
                }
                throw error
            }

            // Flush any remaining buffered content
            await buffer.flush { content, thinking in
                guard streamingIndex < messages.count else { return }
                if !content.isEmpty {
                    messages[streamingIndex].content += content
                }
                if !thinking.isEmpty {
                    let current = messages[streamingIndex].thinkingContent ?? ""
                    messages[streamingIndex].thinkingContent = current + thinking
                }
            }

            guard streamingIndex < messages.count else { break }

            if hasThinkingContent, let start = thinkingStartTime {
                messages[streamingIndex].thinkingDuration = Date().timeIntervalSince(start)
            }

            let hasReasoning = hasThinkingContent && (messages[streamingIndex].thinkingContent?.isEmpty == false)
            if let content = response.content, !content.isEmpty {
                messages[streamingIndex].content = content
                messages[streamingIndex].isStreaming = false
            } else if response.toolCalls == nil {
                if hasReasoning {
                    messages[streamingIndex].isStreaming = false
                    break
                }
                if streamingIndex < messages.count {
                    messages.remove(at: streamingIndex)
                }
            }

            guard streamingIndex < messages.count else { break }

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                if let content = response.content, !content.isEmpty {
                    messages[streamingIndex].content = content
                    messages[streamingIndex].isStreaming = false
                    messages[streamingIndex].toolCalls = toolCalls
                } else {
                    let existingThinking = messages[streamingIndex].thinkingContent
                    let existingDuration = messages[streamingIndex].thinkingDuration
                    messages[streamingIndex] = Message(
                        id: messageId,
                        role: .assistant,
                        content: response.content ?? "",
                        thinkingContent: existingThinking,
                        thinkingDuration: existingDuration,
                        toolCalls: toolCalls
                    )
                }

                let results = await executeToolCalls(toolCalls)

                // Track consecutive errors to abort if stuck
                let hasErrors = results.contains { $0.status == .error }
                if hasErrors {
                    consecutiveErrors += 1
                    if consecutiveErrors >= Self.maxConsecutiveErrors {
                        let warningMsg = Message.system("⚠️ 连续 \(consecutiveErrors) 次工具执行错误，已自动停止。请检查错误信息后重试。")
                        messages.append(warningMsg)
                        break
                    }
                } else {
                    consecutiveErrors = 0
                }

                // Inject error reflection into tool results for AI to learn from
                var reflectionContent = ""
                for (index, toolCall) in toolCalls.enumerated() {
                    if index < results.count && results[index].status == .error {
                        reflectionContent += generateErrorReflection(toolCall: toolCall, result: results[index])
                    }
                }

                let resultMessage = Message(
                    role: .user,
                    content: reflectionContent.isEmpty ? "" : "[Tool Execution Results with Analysis]",
                    toolResults: results
                )
                messages.append(resultMessage)

                continue
            }

            break
        }
    }

    // MARK: - Non-streaming Single Agent Processing

    private func processConversationLoop(aiService: AIService) async throws {
        let model = configuration.model
        let toolDefinitions = toolRegistry.getToolDefinitions()
        var iterationCount = 0
        var consecutiveErrors = 0

        while true {
            // Get context messages inside the loop to reflect new tool results
            let contextMessages = getContextMessages()

            // Check for cancellation
            guard !isCancelled else { break }

            iterationCount += 1
            guard iterationCount <= Self.maxToolCallIterations else {
                let warningMsg = Message.system("⚠️ 已达到最大工具调用次数上限（\(Self.maxToolCallIterations) 次），已自动停止。如需继续，请直接描述下一步操作。")
                messages.append(warningMsg)
                break
            }

            let response = try await aiService.sendMessage(
                contextMessages,
                tools: toolDefinitions,
                model: model,
                maxTokens: configuration.maxTokens
            )

            // Track actual token usage from API response
            trackUsage(response.usage)

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                let toolCallMessage = Message(
                    role: .assistant,
                    content: response.content ?? "",
                    toolCalls: toolCalls
                )
                messages.append(toolCallMessage)

                let results = await executeToolCalls(toolCalls)

                // Track consecutive errors to abort if stuck
                let hasErrors = results.contains { $0.status == .error }
                if hasErrors {
                    consecutiveErrors += 1
                    if consecutiveErrors >= Self.maxConsecutiveErrors {
                        let warningMsg = Message.system("⚠️ 连续 \(consecutiveErrors) 次工具执行错误，已自动停止。请检查错误信息后重试。")
                        messages.append(warningMsg)
                        break
                    }
                } else {
                    consecutiveErrors = 0
                }

                // Inject error reflection into tool results for AI to learn from
                var reflectionContent = ""
                for (index, toolCall) in toolCalls.enumerated() {
                    if index < results.count && results[index].status == .error {
                        reflectionContent += generateErrorReflection(toolCall: toolCall, result: results[index])
                    }
                }

                let resultMessage = Message(
                    role: .user,
                    content: reflectionContent.isEmpty ? "" : "[Tool Execution Results with Analysis]",
                    toolResults: results
                )
                messages.append(resultMessage)

                continue
            }

            // No tool calls — append assistant content and exit loop
            if let content = response.content, !content.isEmpty {
                let assistantMessage = Message.assistant(content)
                messages.append(assistantMessage)
            }

            break
        }
    }

    // MARK: - Token Tracking

    /// Accumulated token usage from actual API responses
    private var accumulatedUsage: (promptTokens: Int, completionTokens: Int) = (0, 0)

    // MARK: - Context Management

    private func estimateTokens(_ text: String) -> Int {
        // 粗略估算: 中文约 1.5 字符/token, 英文约 4 字符/token
        var cjkCount = 0
        var asciiCount = 0
        for char in text {
            if char.isASCII {
                asciiCount += 1
            } else {
                cjkCount += 1
            }
        }
        return cjkCount / 2 + asciiCount / 4 + 1
    }

    private func estimateMessageTokens(_ message: Message) -> Int {
        var total = estimateTokens(message.content)
        if let thinking = message.thinkingContent {
            total += estimateTokens(thinking)
        }
        if let toolResults = message.toolResults {
            for tr in toolResults {
                total += estimateTokens(tr.output)
            }
        }
        if let toolCalls = message.toolCalls {
            for tc in toolCalls {
                total += estimateTokens(tc.name)
                total += estimateTokens("\(tc.arguments)")
            }
        }
        return total
    }

    /// Track usage from an API response for more accurate token counting
    private func trackUsage(_ usage: AIResponse.Usage?) {
        guard let usage = usage else { return }
        accumulatedUsage.promptTokens += usage.promptTokens
        accumulatedUsage.completionTokens += usage.completionTokens
    }

    /// Get the estimated total tokens used in this conversation
    func getTotalTokensUsed() -> Int {
        // If we have actual usage data, prefer it
        let actualTotal = accumulatedUsage.promptTokens + accumulatedUsage.completionTokens
        if actualTotal > 0 { return actualTotal }
        // Otherwise estimate from messages
        return messages.reduce(0) { $0 + estimateMessageTokens($1) }
    }

    private func getContextMessages() -> [Message] {
        var systemMsg = buildSystemMessage()
        
        // Get the latest user message for tool recommendation
        if let lastUserMessage = messages.last(where: { $0.role == .user }),
           !lastUserMessage.content.isEmpty {
            let toolHint = ToolRecommender.generateHintWithMemory(
                for: lastUserMessage.content, 
                memory: memory, 
                config: intelligentConfig.config
            )
            if !toolHint.isEmpty {
                // Append tool hint to system message
                systemMsg = Message.system(systemMsg.content + toolHint)
            }
        }
        
        let contextWindow = AIProvider.contextWindow(for: configuration.model)
        let threshold = Int(Double(contextWindow) * 0.85)

        var totalTokens = estimateTokens(systemMsg.content)
        var keptMessages: [Message] = []

        // 估算所有消息的 token，从最新往最旧遍历
        // 先把所有消息倒序（最新在前），保留直到达到 85% 阈值
        let reversedMessages = messages.reversed()
        var keepCount = 0
        for msg in reversedMessages {
            let msgTokens = estimateMessageTokens(msg)
            if totalTokens + msgTokens > threshold, keepCount >= 4 {
                break
            }
            totalTokens += msgTokens
            keptMessages.append(msg)
            keepCount += 1
        }

        // 恢复正序
        return [systemMsg] + keptMessages.reversed()
    }

    private func buildSystemMessage() -> Message {
        var prompt = """
You are Rio Agent, an AI assistant with tool-calling capabilities for software engineering tasks. Always respond in the same language the user uses.

## Reasoning Strategy (Chain-of-Thought)

**ALWAYS think step-by-step before acting:**

1. **Understand**: Clarify the user's intent. Ask for clarification if ambiguous.
2. **Plan**: Break complex tasks into concrete steps. Consider edge cases.
3. **Verify**: Before executing, check if your plan makes sense. Will this actually solve the problem?
4. **Execute**: Carry out the plan methodically, one step at a time.
5. **Reflect**: After each tool call, evaluate the result. Did it work as expected? Should you adjust?

For complex tasks, explicitly state your reasoning:
```
Thinking: The user wants X. To achieve this, I need to:
1. First do Y to understand the current state
2. Then do Z to make the change
3. Finally verify with W
```

## Available Tools

- read_file: Read file content. Read-only, no confirmation needed. Always prefer this over execute_command for reading files.
- write_file: Write file content (complete overwrite, NOT append). Auto-executes within working directory; writes outside working directory require user confirmation.
- edit_file: Edit a file by searching for specific text and replacing it (search/replace). Safer than write_file for targeted modifications. The old_text must appear exactly once in the file.
- apply_patch: Apply a multi-file patch using diff format. Supports adding, updating, and deleting files in a single operation. Use for coordinated changes across multiple files.
- search_files: Search file contents by regex pattern (like grep). Read-only, no confirmation needed. Returns matching lines with file paths and line numbers.
- find_files: Find files by name pattern (like glob). Read-only, no confirmation needed. Returns matching file paths.
- list_directory: List directory contents with detailed information. Read-only, no confirmation needed.
- execute_command: Execute shell commands. Safe commands (ls, cat, grep, git status, etc.) auto-execute; dangerous commands (rm, sudo, curl, etc.) always require confirmation.

## Tool Usage Guidelines

**Strategy for choosing tools:**
- **Exploration phase**: Use list_directory, find_files, search_files to understand the codebase structure BEFORE making changes
- **Reading phase**: Use read_file to examine specific files. NEVER use `cat` via execute_command.
- **Modification phase**: Prefer edit_file for targeted changes. Use apply_patch for multi-file changes. Use write_file only for new files or complete rewrites.
- **Verification phase**: After changes, use read_file or search_files to verify the result.

**Critical rules:**
- Each file tool requires ABSOLUTE file paths. When the user mentions a relative path, prepend the working directory.
- Do NOT call tools unnecessarily. When you have enough information, respond directly.
- Prefer edit_file over write_file when modifying existing files — it is safer and more precise.
- For git operations, package management, or other shell tasks → use execute_command

## Error Recovery & Self-Correction

When a tool call fails:

1. **Analyze the error**: What exactly went wrong? Is it a path issue, permission issue, or logic error?
2. **Consider alternatives**: Is there another way to achieve the same goal?
3. **Learn from it**: Don't repeat the same mistake. Adjust your approach.

**Common error patterns and fixes:**
- "File not found" → Check the path, use find_files to locate the correct file
- "Permission denied" → May need user confirmation, or try a different approach
- "Tool execution failed" → Read the error message carefully, it often contains the solution
- If 2-3 attempts fail on the same task, STOP and explain the situation to the user

## Safety & Permissions

Commands are classified into three risk levels:
- **Safe**: ls, cat, grep, git status/log/diff, version checks → auto-execute, no confirmation
- **Normal**: most commands → require user confirmation (can be trusted for the session)
- **Dangerous**: rm, sudo, curl, wget, dd, kill -9 → always require confirmation, cannot be trusted

Writes to files outside the working directory also require user confirmation.

## Behavioral Constraints

- Handle one task at a time. Do not batch unrelated operations.
- When a tool returns an error, analyze the cause before retrying. Do not retry blindly.
- After receiving tool results, provide a meaningful response based on the actual output.
- Do NOT fabricate file contents or command outputs. Only report what the tools actually return.
- Be concise. Avoid unnecessary preamble or postamble.
- If you're unsure about something, say so. Don't guess or hallucinate.
"""

        if let dir = workingDirectory {
            prompt += """

## Working Directory (CRITICAL)

The working directory is: \(dir)

RULES:
- read_file and write_file require FULL ABSOLUTE PATHS. Never use relative paths.
- When the user says "read README.md", use path = "\(dir)/README.md"
- For execute_command, the working directory context is \(dir)
"""
            
            // 尝试加载 AGENT.md 文件作为项目上下文
            let agentMDPath = "\(dir)/AGENT.md"
            if let content = FileManager.default.contents(atPath: agentMDPath),
               let mdString = String(data: content, encoding: .utf8) {
                prompt += "\n\n## Project Context (from AGENT.md)\n\n\(mdString)"
            }
        }
        
        // Inject memory context
        let memoryContext = memory.generateMemoryContext()
        if !memoryContext.isEmpty {
            prompt += "\n\n## Agent Memory\n\(memoryContext)"
        }
        
        // Inject project-specific knowledge if available
        if let dir = workingDirectory {
            let projectContext = memory.generateProjectContext(for: dir)
            if !projectContext.isEmpty {
                prompt += projectContext
            }
            
            // Inject context awareness based on recent files
            if let lastFile = memory.session.recentFiles.first {
                let fileContext = ContextAwareness.generateFileContext(for: lastFile)
                prompt += ContextAwareness.generateContextPrompt(for: fileContext)
            }
            
            // Inject project context if we have enough information
            let directoryContents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            if !directoryContents.isEmpty {
                let projectContext = ContextAwareness.generateProjectContext(from: directoryContents, projectPath: dir)
                prompt += ContextAwareness.generateContextPrompt(for: projectContext)
            }
        }

        return Message.system(prompt)
    }

    // MARK: - Tool Execution

    /// Tracks recent tool errors for pattern detection
    private var recentErrors: [(toolName: String, error: String, timestamp: Date)] = []
    
    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        var results: [ToolResult] = []

        for toolCall in toolCalls {
            currentToolExecution = .pending(toolCall: toolCall)

            // Yield to let the UI update before potentially long-running execution
            await Task.yield()

            currentToolExecution = .executing(toolCall: toolCall)

            let result: ToolResult
            do {
                let raw = try await toolRegistry.executeTool(
                    name: toolCall.name,
                    arguments: toolCall.arguments.mapValues { $0.value }
                )
                result = ToolResult(
                    toolCallId: toolCall.id,
                    status: raw.status,
                    output: raw.output,
                    error: raw.error
                )
            } catch {
                result = ToolResult.error(toolCallId: toolCall.id, error: error.localizedDescription)
            }

            // Track errors for pattern detection
            if result.status == .error {
                recentErrors.append((
                    toolName: toolCall.name,
                    error: result.error ?? "Unknown error",
                    timestamp: Date()
                ))
                // Keep only last 10 errors
                if recentErrors.count > 10 {
                    recentErrors.removeFirst()
                }
            }

            currentToolExecution = .completed(toolCall: toolCall, result: result)
            
            // Record tool usage in memory
            memory.recordToolUsage(toolCall.name)
            
            // Record file access if applicable
            if let path = toolCall.arguments["path"]?.value as? String {
                memory.recordFileAccess(path)
            }
            
            // Record successful patterns
            if result.status == .success {
                let taskType = ToolRecommender.classifyTask(memory.session.currentTask ?? "")
                memory.recordSuccessfulPattern(taskType: "\(taskType)", tool: toolCall.name)
            }
            
            // Record error patterns for learning
            if result.status == .error, let error = result.error {
                memory.recordErrorPattern(
                    error: error,
                    context: "Tool: \(toolCall.name), Args: \(toolCall.arguments)",
                    solution: "" // Will be filled when error is resolved
                )
            }
            
            // Record learning event
            let learningEvent = IntelligentLearningSystem.LearningEvent(
                type: result.status == .success ? .successPattern : .errorPattern,
                timestamp: Date(),
                context: [
                    "tool": toolCall.name,
                    "taskType": ToolRecommender.classifyTask(memory.session.currentTask ?? "").description,
                    "success": result.status == .success
                ],
                outcome: result.status == .success ? "Success" : (result.error ?? "Unknown error"),
                success: result.status == .success
            )
            learningSystem.recordEvent(learningEvent)
            
            results.append(result)
        }

        currentToolExecution = nil
        return results
    }

    /// Generate reflection prompt when errors occur
    private func generateErrorReflection(toolCall: ToolCall, result: ToolResult) -> String {
        guard result.status == .error else { return "" }

        var reflection = "\n\n[Error Analysis for \(toolCall.name)]\n"
        reflection += "Error: \(result.error ?? "Unknown")\n"

        // Analyze error patterns
        let errorLowercased = (result.error ?? "").lowercased()

        // Check for similar errors in memory first
        let similarErrors = memory.findSimilarErrors(result.error ?? "")
        if !similarErrors.isEmpty {
            reflection += "💡 Similar errors found in history:\n"
            for error in similarErrors.prefix(2) {
                reflection += "- \(error.errorType): \(error.solution)\n"
            }
        }

        // Provide specific suggestions based on error type
        if errorLowercased.contains("file not found") || errorLowercased.contains("no such file") {
            reflection += "Likely cause: File path is incorrect or file doesn't exist.\n"
            reflection += "Suggestion: Use find_files to locate the correct path, or check if the file exists.\n"
        } else if errorLowercased.contains("permission denied") || errorLowercased.contains("permission") {
            reflection += "Likely cause: Insufficient permissions to perform this operation.\n"
            reflection += "Suggestion: This may require user confirmation, or try a different approach.\n"
        } else if errorLowercased.contains("timeout") {
            reflection += "Likely cause: Operation took too long to complete.\n"
            reflection += "Suggestion: Try a simpler operation, or break the task into smaller steps.\n"
        } else if errorLowercased.contains("network") || errorLowercased.contains("connection") {
            reflection += "Likely cause: Network connectivity issue.\n"
            reflection += "Suggestion: Check if the service is available, or try again later.\n"
        } else if errorLowercased.contains("syntax error") || errorLowercased.contains("parse error") {
            reflection += "Likely cause: Invalid syntax in the code or configuration.\n"
            reflection += "Suggestion: Check the syntax and fix any errors.\n"
        } else if errorLowercased.contains("memory") || errorLowercased.contains("out of memory") {
            reflection += "Likely cause: Insufficient memory to complete the operation.\n"
            reflection += "Suggestion: Try a simpler operation, or free up memory.\n"
        } else if errorLowercased.contains("disk") || errorLowercased.contains("no space") {
            reflection += "Likely cause: Insufficient disk space.\n"
            reflection += "Suggestion: Free up disk space and try again.\n"
        } else if errorLowercased.contains("invalid") || errorLowercased.contains("validation") {
            reflection += "Likely cause: Invalid input or data.\n"
            reflection += "Suggestion: Check the input data and fix any validation errors.\n"
        }

        // Check for repeated errors
        let recentSimilarErrors = recentErrors.filter {
            $0.toolName == toolCall.name &&
            Date().timeIntervalSince($0.timestamp) < 60 // Within last minute
        }

        if recentSimilarErrors.count >= 2 {
            reflection += "⚠️ WARNING: This tool has failed \(recentSimilarErrors.count) times recently.\n"
            reflection += "Suggestion: Consider a different approach or ask the user for help.\n"
        }

        return reflection
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
        md += "模型: \(configuration.model)\n\n---\n\n"

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
    private var updateCount = 0
    private let maxUpdatesPerSecond = 15  // 限制每秒最大更新次数

    init(interval: TimeInterval = 0.15, maxCharsBeforeFlush: Int = 300) {
        self.interval = interval
        self.maxCharsBeforeFlush = maxCharsBeforeFlush
    }

    func appendContent(_ chunk: String) { contentAccumulator += chunk }
    func appendThinking(_ chunk: String) { thinkingAccumulator += chunk }

    private var shouldFlushNow: Bool {
        // 限制更新频率
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFlush)
        
        // 如果距离上次更新时间太短，且累积内容不多，则延迟更新
        if elapsed < 0.02 && contentAccumulator.count < 20 && thinkingAccumulator.count < 20 {
            return false
        }
        
        // 达到最大字符数限制
        if contentAccumulator.count >= maxCharsBeforeFlush { return true }
        if thinkingAccumulator.count >= maxCharsBeforeFlush { return true }
        
        // 达到时间间隔
        return elapsed >= interval
    }

    func flushIfNeeded(update: @MainActor @Sendable (_ content: String, _ thinking: String) async -> Void) async {
        guard shouldFlushNow,
              !contentAccumulator.isEmpty || !thinkingAccumulator.isEmpty else { return }
        let c = contentAccumulator; contentAccumulator = ""
        let t = thinkingAccumulator; thinkingAccumulator = ""
        lastFlush = Date()
        updateCount += 1
        await update(c, t)
    }

    func flush(update: @MainActor @Sendable (_ content: String, _ thinking: String) async -> Void) async {
        guard !contentAccumulator.isEmpty || !thinkingAccumulator.isEmpty else { return }
        let c = contentAccumulator; contentAccumulator = ""
        let t = thinkingAccumulator; thinkingAccumulator = ""
        await update(c, t)
    }
}
