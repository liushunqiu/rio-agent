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
    var provider: AIProvider
    var model: String
    var systemPrompt: String
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, role, capability, provider, model, systemPrompt, isEnabled
    }

    init(
        id: UUID = UUID(),
        name: String,
        role: AgentRole,
        capability: AgentCapability? = nil,
        provider: AIProvider,
        model: String,
        systemPrompt: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.capability = capability ?? (role == .orchestrator ? .general : .custom)
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
}

// MARK: - Multi-Agent Configuration

struct MultiAgentConfig: Codable {
    var isEnabled: Bool
    var orchestrator: AgentConfig
    var workers: [AgentConfig]
    var maxParallelWorkers: Int
    var taskSplitStrategy: TaskSplitStrategy
    var maxTokens: Int
    var maxRetries: Int
    var enableCritic: Bool

    init(
        isEnabled: Bool = false,
        orchestrator: AgentConfig? = nil,
        workers: [AgentConfig] = [],
        maxParallelWorkers: Int = 3,
        taskSplitStrategy: TaskSplitStrategy = .automatic,
        maxTokens: Int = 0,
        maxRetries: Int = 2,
        enableCritic: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.orchestrator = orchestrator ?? AgentConfig(
            name: "主 Agent",
            role: .orchestrator,
            capability: .general,
            provider: .claude,
            model: "claude-sonnet-4-20250514",
            systemPrompt: "你是一个任务协调者。你的职责是：\n1. 理解用户的任务需求\n2. 将复杂任务拆分为多个子任务\n3. 分配子任务给工作 Agent\n4. 汇总所有结果，给出最终答案"
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

    static var defaultWorkers: [AgentConfig] {
        [
            AgentConfig(
                name: "搜索 Agent",
                role: .worker,
                capability: .search,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: "你是一个搜索助手。负责查找和整理信息。"
            ),
            AgentConfig(
                name: "代码 Agent",
                role: .worker,
                capability: .code,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: "你是一个代码助手。负责代码分析和实现。"
            ),
            AgentConfig(
                name: "文件 Agent",
                role: .worker,
                capability: .file,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: "你是一个文件助手。负责文件读写操作。"
            )
        ]
    }
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
        verificationStatus: VerificationStatus = .unverified
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
    }
}

enum SubTaskStatus: String {
    case pending
    case running
    case completed
    case failed
}

// MARK: - Verification Status

enum VerificationStatus: String {
    case unverified
    case verified
    case needsRetry
}

// MARK: - Execution Result

struct ExecutionResult {
    let subTaskId: UUID
    let output: String
    let errors: [String]
    let retryCount: Int
    let verificationStatus: VerificationStatus

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
    case failed
}
