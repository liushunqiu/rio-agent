import Foundation

// MARK: - Agent Role

enum AgentRole: String, Codable, CaseIterable {
    case orchestrator
    case worker

    var displayName: String {
        switch self {
        case .orchestrator: return "主 Agent"
        case .worker: return "子 Agent"
        }
    }

    var description: String {
        switch self {
        case .orchestrator: return "负责任务拆分、汇总结果、最终决策"
        case .worker: return "负责执行具体的子任务"
        }
    }
}

// MARK: - Agent Capability

enum AgentCapability: String, Codable, CaseIterable {
    case search
    case code
    case file
    case general
    case custom

    var displayName: String {
        switch self {
        case .search: return "搜索"
        case .code: return "代码"
        case .file: return "文件"
        case .general: return "通用"
        case .custom: return "自定义"
        }
    }

    var description: String {
        switch self {
        case .search: return "信息检索、资料整理、外部上下文收集"
        case .code: return "代码阅读、实现、调试、重构建议"
        case .file: return "文件读写、目录整理、批量文本处理"
        case .general: return "综合分析、写作、规划和普通问答"
        case .custom: return "按该 Agent 的系统提示词执行特定任务"
        }
    }

    var workerType: String {
        rawValue
    }

    init(workerType: String) {
        self = AgentCapability(rawValue: workerType) ?? .general
    }
}

// MARK: - Agent Configuration

struct AgentConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var role: AgentRole
    var capability: AgentCapability
    var configSetId: UUID?
    var provider: AIProvider
    var model: String
    var systemPrompt: String
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, role, capability, configSetId, provider, model, systemPrompt, isEnabled
    }

    init(
        id: UUID = UUID(),
        name: String,
        role: AgentRole,
        capability: AgentCapability? = nil,
        configSetId: UUID? = nil,
        provider: AIProvider,
        model: String,
        systemPrompt: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.capability = capability ?? (role == .orchestrator ? .general : .custom)
        self.configSetId = configSetId
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(AgentRole.self, forKey: .role)
        capability = try container.decodeIfPresent(AgentCapability.self, forKey: .capability)
            ?? AgentConfig.inferCapability(name: name, role: role)
        configSetId = try container.decodeIfPresent(UUID.self, forKey: .configSetId)
        provider = try container.decode(AIProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    private static func inferCapability(name: String, role: AgentRole) -> AgentCapability {
        guard role == .worker else { return .general }
        if name.contains("搜索") { return .search }
        if name.contains("代码") { return .code }
        if name.contains("文件") { return .file }
        return .general
    }

    func resolvedConfigSet(from configSets: [ConfigSet]) -> ConfigSet? {
        if let configSetId,
           let exactConfig = configSets.first(where: { $0.id == configSetId }) {
            return exactConfig
        }

        let providerSets = configSets.filter { $0.provider == provider }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty,
           let modelMatch = providerSets.first(where: {
               $0.model.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedModel
           }) {
            return modelMatch
        }

        return providerSets.first
    }

    mutating func applyConfigSet(_ configSet: ConfigSet?) {
        guard let configSet else {
            configSetId = nil
            return
        }

        configSetId = configSet.id
        provider = configSet.provider
        model = configSet.model
    }
}

// MARK: - Multi-Agent Configuration

struct MultiAgentConfig: Codable {
    var orchestrator: AgentConfig
    var workers: [AgentConfig]
    var maxParallelWorkers: Int
    var taskSplitStrategy: TaskSplitStrategy
    var maxTokens: Int
    var maxRetries: Int
    var enableCritic: Bool
    var router: RouterConfig

    static let legacyDefaultOrchestratorPrompt = "你是一个任务协调者。你的职责是：\n1. 理解用户的任务需求\n2. 将复杂任务拆分为多个子任务\n3. 分配子任务给工作 Agent\n4. 汇总所有结果，给出最终答案"
    static let defaultOrchestratorPrompt = """
    你是任务协调者，负责拆解任务、分配执行者、审计证据并汇总最终答案。

    工作原则：
    - 先给结论，再给支撑细节。
    - 只把有证据支持的内容写进进度汇报和最终结论。证据来自本轮子任务结果与工具输出。
    - 若某部分尚未验证、存在残留错误或依赖失败，必须明确写出“未验证”或“未完成”，不要脑补完成状态。
    - 优先保持回答清晰、自然，避免无意义的格式化堆砌。

    在拆解任务时：
    - 只在确实能并行时拆分，避免为了拆而拆。
    - 给每个子任务足够上下文，使 worker 可以独立执行。
    - 选择最匹配能力的 worker；如果没有完全匹配者，选择最接近者并说明原因。

    在汇总结果时：
    - 区分“已验证完成”“部分完成”“失败/阻塞”三类状态。
    - 若 worker 结果之间存在冲突或空白，优先指出冲突，不要擅自抹平。
    - 最终回答必须忠实反映执行证据，而不是反映预期。
    """
    static let legacyDefaultSearchPrompt = "你是一个搜索助手。负责查找和整理信息。"
    static let defaultSearchPrompt = """
    你是搜索 Agent。负责收集事实、整理证据、输出可核对的信息。

    工作原则：
    - 只陈述你从工具结果中能支持的事实。
    - 不要把猜测写成事实；无法确认时直接说明未验证。
    - 回答先写发现了什么，再补充证据细节。
    - 保持简洁清晰，避免空泛总结。

    执行要求：
    - 优先用搜索、读取、列目录等工具确认信息来源。
    - 若问题依赖当前仓库内容，先读取相关文件再下结论。
    - 输出时尽量保留关键路径、文件名、错误信息、命令结果等可审计线索。
    """
    static let legacyDefaultCodePrompt = "你是一个代码助手。负责代码分析和实现。"
    static let defaultCodePrompt = """
    你是代码 Agent。负责代码阅读、实现、调试和验证。

    工作原则：
    - 先说明改了什么或发现了什么，再解释原因。
    - 声称修复、完成或通过之前，必须先拿到可验证证据，例如读回文件、编译结果、测试结果或命令输出。
    - 不要假设代码行为，不要脑补未运行过的结果。
    - 变更应尽量精确，遵循现有代码风格。

    执行要求：
    - 修改前先阅读相关文件和上下文。
    - 修改后至少做一项验证；若无法验证，明确说明原因和未验证范围。
    - 若同一路径连续失败，停止重复尝试，转而分析根因并给出下一步。
    """
    static let legacyDefaultFilePrompt = "你是一个文件助手。负责文件读写操作。"
    static let defaultFilePrompt = """
    你是文件 Agent。负责精确的文件读写、目录整理和文本变更。

    工作原则：
    - 只根据当前读到的内容修改文件，不要猜测文件结构。
    - 输出先说明实际改动，再说明影响范围。
    - 未读到文件前，不要声明将进行精确替换。

    执行要求：
    - 修改前确认目标路径和当前内容。
    - 修改后读回关键片段，确认结果与预期一致。
    - 如果匹配失败、路径错误或权限不足，直接报告真实错误，不要伪造成功。
    """

    init(
        orchestrator: AgentConfig? = nil,
        workers: [AgentConfig] = [],
        maxParallelWorkers: Int = 3,
        taskSplitStrategy: TaskSplitStrategy = .automatic,
        maxTokens: Int = 0,
        maxRetries: Int = 2,
        enableCritic: Bool = true,
        router: RouterConfig = RouterConfig()
    ) {
        self.router = router
        self.orchestrator = orchestrator ?? AgentConfig(
            name: "主 Agent",
            role: .orchestrator,
            capability: .general,
            provider: .claude,
            model: "claude-sonnet-4-20250514",
            systemPrompt: Self.defaultOrchestratorPrompt
        )
        self.workers = workers.isEmpty ? Self.defaultWorkers : workers
        self.maxParallelWorkers = maxParallelWorkers
        self.taskSplitStrategy = taskSplitStrategy
        self.maxTokens = maxTokens
        self.maxRetries = maxRetries
        self.enableCritic = enableCritic
    }

    var effectiveMaxTokens: Int {
        if maxTokens > 0 { return maxTokens }
        return AIProvider.defaultMaxTokens(for: orchestrator.model)
    }

    mutating func reconcileConfigSets(with configSets: [ConfigSet]) {
        let fallbackOrchestratorConfig = orchestrator.resolvedConfigSet(from: configSets)
            ?? configSets.first(where: { $0.provider == orchestrator.provider })
            ?? configSets.first
        orchestrator.applyConfigSet(fallbackOrchestratorConfig)

        for index in workers.indices {
            let fallbackWorkerConfig = workers[index].resolvedConfigSet(from: configSets)
                ?? configSets.first(where: { $0.provider == workers[index].provider })
                ?? configSets.first
            workers[index].applyConfigSet(fallbackWorkerConfig)
        }

        let resolvedRouterConfig = resolveRouterConfigSet(from: configSets)
        router.configSetId = resolvedRouterConfig?.id
        if let resolvedRouterConfig, router.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            router.model = resolvedRouterConfig.model
        }
    }

    private func resolveRouterConfigSet(from configSets: [ConfigSet]) -> ConfigSet? {
        if let configSetId = router.configSetId,
           let exactConfig = configSets.first(where: { $0.id == configSetId }) {
            return exactConfig
        }

        let trimmedModel = router.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty,
           let modelMatch = configSets.first(where: {
               $0.model.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedModel
           }) {
            return modelMatch
        }

        return configSets.first
    }

    mutating func migrateBuiltInPromptsIfNeeded() {
        if orchestrator.systemPrompt == Self.legacyDefaultOrchestratorPrompt {
            orchestrator.systemPrompt = Self.defaultOrchestratorPrompt
        }

        // 迁移 Router 提示词
        if router.prompt == RouterConfig.previousDefaultPrompt {
            router.prompt = RouterConfig.defaultPrompt
        }

        for index in workers.indices {
            switch workers[index].systemPrompt {
            case Self.legacyDefaultSearchPrompt,
                 "你是一个搜索助手。负责查找和整理信息。使用工具高效搜索，优先返回准确、结构化的结果。":
                workers[index].systemPrompt = Self.defaultSearchPrompt
            case Self.legacyDefaultCodePrompt,
                 "你是一个代码助手。负责代码分析、实现和调试。写出简洁、可维护的代码，遵循项目已有的代码风格。":
                workers[index].systemPrompt = Self.defaultCodePrompt
            case Self.legacyDefaultFilePrompt,
                 "你是一个文件助手。负责文件读写操作。精确匹配文件内容，避免破坏文件结构。":
                workers[index].systemPrompt = Self.defaultFilePrompt
            default:
                continue
            }
        }
    }

    static var defaultWorkers: [AgentConfig] {
        [
            AgentConfig(
                name: "搜索 Agent",
                role: .worker,
                capability: .search,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: Self.defaultSearchPrompt
            ),
            AgentConfig(
                name: "代码 Agent",
                role: .worker,
                capability: .code,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: Self.defaultCodePrompt
            ),
            AgentConfig(
                name: "文件 Agent",
                role: .worker,
                capability: .file,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: Self.defaultFilePrompt
            )
        ]
    }
}

// MARK: - Budget Worker Presets

extension MultiAgentConfig {
    /// 性价比最优 Worker 阵容——灵感来自 OpenRouter Fusion 测试结论：
    /// 平价模型各司其职，整体效果可逼近高端模型，成本降低 80%+
    ///
    /// - 搜索 Agent: Gemini 2.0 Flash（信息检索能力强，极低价格）
    /// - 代码 Agent: DeepSeek V3 / DeepSeek Chat（代码能力强，永久降价后性价比极高）
    /// - 文件 Agent: Gemini 1.5 Flash（百万上下文窗口，文件操作友好）
    static var budgetWorkers: [AgentConfig] {
        [
            AgentConfig(
                name: "搜索 Agent",
                role: .worker,
                capability: .search,
                provider: .openAICompatible,
                model: "gemini-2.0-flash",
                systemPrompt: Self.defaultSearchPrompt
            ),
            AgentConfig(
                name: "代码 Agent",
                role: .worker,
                capability: .code,
                provider: .openAICompatible,
                model: "deepseek-chat",
                systemPrompt: Self.defaultCodePrompt
            ),
            AgentConfig(
                name: "文件 Agent",
                role: .worker,
                capability: .file,
                provider: .openAICompatible,
                model: "gemini-1.5-flash",
                systemPrompt: Self.defaultFilePrompt
            )
        ]
    }

    /// 高性能 Worker 阵容——使用各厂商旗舰模型
    static var premiumWorkers: [AgentConfig] {
        [
            AgentConfig(
                name: "搜索 Agent",
                role: .worker,
                capability: .search,
                provider: .openAICompatible,
                model: "gemini-2.5-pro",
                systemPrompt: Self.defaultSearchPrompt
            ),
            AgentConfig(
                name: "代码 Agent",
                role: .worker,
                capability: .code,
                provider: .claude,
                model: "claude-sonnet-4-20250514",
                systemPrompt: Self.defaultCodePrompt
            ),
            AgentConfig(
                name: "文件 Agent",
                role: .worker,
                capability: .file,
                provider: .openAICompatible,
                model: "gpt-4o",
                systemPrompt: Self.defaultFilePrompt
            )
        ]
    }

    /// 获取预设配置列表（供 UI 展示）
    static var availablePresets: [(name: String, description: String, workers: [AgentConfig])] {
        [
            (
                name: "默认阵容",
                description: "全部使用 Claude 3.5 Haiku，均衡稳定",
                workers: defaultWorkers
            ),
            (
                name: "性价比阵容",
                description: "Gemini Flash + DeepSeek Chat + Gemini 1.5 Flash，成本降低 80%+",
                workers: budgetWorkers
            ),
            (
                name: "高性能阵容",
                description: "Gemini Pro + Claude Sonnet 4 + GPT-4o，最强输出",
                workers: premiumWorkers
            )
        ]
    }
}

extension MultiAgentConfig {
    private static let builtInOrchestratorPromptSet: Set<String> = [
        legacyDefaultOrchestratorPrompt,
        defaultOrchestratorPrompt
    ]

    private static let builtInSearchPromptSet: Set<String> = [
        legacyDefaultSearchPrompt,
        "你是一个搜索助手。负责查找和整理信息。使用工具高效搜索，优先返回准确、结构化的结果。",
        defaultSearchPrompt
    ]

    private static let builtInCodePromptSet: Set<String> = [
        legacyDefaultCodePrompt,
        "你是一个代码助手。负责代码分析、实现和调试。写出简洁、可维护的代码，遵循项目已有的代码风格。",
        defaultCodePrompt
    ]

    private static let builtInFilePromptSet: Set<String> = [
        legacyDefaultFilePrompt,
        "你是一个文件助手。负责文件读写操作。精确匹配文件内容，避免破坏文件结构。",
        defaultFilePrompt
    ]

    static func isBuiltInOrchestratorPrompt(_ prompt: String) -> Bool {
        builtInOrchestratorPromptSet.contains(prompt)
    }

    static func isBuiltInWorkerPrompt(_ prompt: String, capability: AgentCapability) -> Bool {
        switch capability {
        case .search:
            return builtInSearchPromptSet.contains(prompt)
        case .code:
            return builtInCodePromptSet.contains(prompt)
        case .file:
            return builtInFilePromptSet.contains(prompt)
        case .general, .custom:
            return false
        }
    }
}

// MARK: - Router Configuration

struct RouterConfig: Codable {
    var enabled: Bool = false
    var configSetId: UUID?
    var model: String = ""
    var maxTokens: Int = 128
    var prompt: String = Self.defaultPrompt
    
    // Qwen3.5-4B 专用配置
    var enableQwenRouter: Bool = false
    var qwenBaseUrl: String = "http://localhost:8000"
    var qwenModel: String = "Qwen/Qwen3.5-4B"
    var disableThinking: Bool = true  // 路由层必须关闭思考模式
    var temperature: Float = 0.7
    var topP: Float = 0.80
    var topK: Int = 20
    var presencePenalty: Float = 1.5
    
    // 路由目标节点定义
    var routingTargets: [RoutingTarget] = RoutingTarget.defaultTargets

    static let previousDefaultPrompt = """
    你是一个任务路由器。分析用户输入，输出 JSON 决定如何处理。

    {
      "mode": "skip | process",
      "confidence": 0.0-1.0,
      "reasoning": "简短理由"
    }

    规则：
    - skip: 问候、闲聊、身份介绍等无需工具调用的对话，直接简短回复即可
    - process: 需要工具调用的任务（文件操作、代码修改、信息查询等），由后续规划层决定执行策略

    只输出 JSON，不要额外文字。
    """

    static let defaultPrompt = """
    你是一个任务路由器。分析用户输入，输出 JSON 决定如何处理。

    {
      "mode": "skip | process",
      "confidence": 0.0-1.0,
      "reasoning": "简短理由"
    }

    规则：
    - skip: 仅限纯问候或闲聊（如"你好"、"你是谁"、"谢谢"、"再见"），不涉及任何项目、文件、代码或操作
    - process: 其他所有情况，包括但不限于：文件操作、代码修改、项目探索、信息查询、命令执行、文档生成、任何提到"项目""代码""文件""目录""结构""探索""分析""修改""修复"的请求

    重要：宁可误判为 process 也不要误判为 skip。如果不确定，选 process。

    只输出 JSON，不要额外文字。
    """

    static let builtInPrompts: Set<String> = [defaultPrompt, previousDefaultPrompt]
    
    // Qwen3.5-4B 专用路由 Schema
    static let qwenRoutingSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "target_node": [
                "type": "string",
                "enum": ["skip", "code_expert", "search_agent", "data_analyst", "chitchat", "process"]
            ],
            "extracted_params": [
                "type": "object"
            ],
            "confidence": [
                "type": "number",
                "minimum": 0.0,
                "maximum": 1.0
            ],
            "reasoning": [
                "type": "string"
            ]
        ],
        "required": ["target_node"]
    ]
}

// MARK: - 路由目标节点

struct RoutingTarget: Codable, Identifiable {
    let id: UUID
    var name: String
    var displayName: String
    var description: String
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        description: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.isEnabled = isEnabled
    }
    
    static var defaultTargets: [RoutingTarget] = [
        RoutingTarget(
            name: "skip",
            displayName: "跳过",
            description: "问候、闲聊、身份介绍等无需工具调用的对话",
            isEnabled: true
        ),
        RoutingTarget(
            name: "code_expert",
            displayName: "代码专家",
            description: "代码阅读、实现、调试、重构建议",
            isEnabled: true
        ),
        RoutingTarget(
            name: "search_agent",
            displayName: "搜索代理",
            description: "信息检索、资料整理、外部上下文收集",
            isEnabled: true
        ),
        RoutingTarget(
            name: "data_analyst",
            displayName: "数据分析师",
            description: "数据分析、图表生成、统计计算",
            isEnabled: true
        ),
        RoutingTarget(
            name: "chitchat",
            displayName: "闲聊",
            description: "日常对话、情感交流、非任务性交流",
            isEnabled: true
        ),
        RoutingTarget(
            name: "process",
            displayName: "处理",
            description: "需要工具调用的任务，由规划层决定执行策略",
            isEnabled: true
        )
    ]
}

// MARK: - Task Split Strategy

enum TaskSplitStrategy: String, Codable, CaseIterable {
    case automatic
    case manual

    var displayName: String {
        switch self {
        case .automatic: return "自动拆分"
        case .manual: return "手动确认"
        }
    }

    var description: String {
        switch self {
        case .automatic: return "主 Agent 自动判断是否需要拆分任务"
        case .manual: return "拆分前需要用户确认"
        }
    }
}

// MARK: - Task Models

struct SubTask: Identifiable {
    let id: UUID
    var description: String
    var workerId: UUID?
    var workerType: AgentCapability
    var assignedWorker: AgentConfig?
    var assignmentReason: String?
    var status: SubTaskStatus
    var result: String?
    var dependencies: [UUID]
    var retryCount: Int
    var verificationStatus: VerificationStatus
    var verificationSummary: String?

    init(
        id: UUID = UUID(),
        description: String,
        workerId: UUID? = nil,
        workerType: AgentCapability = .general,
        assignedWorker: AgentConfig? = nil,
        assignmentReason: String? = nil,
        status: SubTaskStatus = .pending,
        result: String? = nil,
        dependencies: [UUID] = [],
        retryCount: Int = 0,
        verificationStatus: VerificationStatus = .unverified,
        verificationSummary: String? = nil
    ) {
        self.id = id
        self.description = description
        self.workerId = workerId
        self.workerType = workerType
        self.assignedWorker = assignedWorker
        self.assignmentReason = assignmentReason
        self.status = status
        self.result = result
        self.dependencies = dependencies
        self.retryCount = retryCount
        self.verificationStatus = verificationStatus
        self.verificationSummary = verificationSummary
    }
}

enum SubTaskStatus: String {
    case pending
    case running
    case completed
    case cancelled
    case failed
}

// MARK: - Verification Status

enum VerificationStatus: String {
    case unverified
    case verified
    case needsRetry

    var displayText: String {
        switch self {
        case .unverified: return "未验证"
        case .verified: return "已验证"
        case .needsRetry: return "需重试"
        }
    }
}

// MARK: - Execution Result

struct ExecutionResult {
    let subTaskId: UUID
    let output: String
    let errors: [String]
    let retryCount: Int
    let verificationStatus: VerificationStatus
    let verificationSummary: String?

    var hasErrors: Bool { !errors.isEmpty }
}

struct TaskPlan: Identifiable {
    let id: UUID
    var originalTask: String
    var subTasks: [SubTask]
    var status: TaskPlanStatus

    init(
        id: UUID = UUID(),
        originalTask: String,
        subTasks: [SubTask] = [],
        status: TaskPlanStatus = .planning
    ) {
        self.id = id
        self.originalTask = originalTask
        self.subTasks = subTasks
        self.status = status
    }
}

enum TaskPlanStatus: String {
    case planning
    case executing
    case verifying
    case synthesizing
    case completed
    case cancelled
    case failed
}
