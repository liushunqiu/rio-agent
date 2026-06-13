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

// MARK: - Agent Configuration

struct AgentConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var role: AgentRole
    var provider: AIProvider
    var model: String
    var systemPrompt: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        role: AgentRole,
        provider: AIProvider,
        model: String,
        systemPrompt: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.isEnabled = isEnabled
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

    init(
        isEnabled: Bool = false,
        orchestrator: AgentConfig? = nil,
        workers: [AgentConfig] = [],
        maxParallelWorkers: Int = 3,
        taskSplitStrategy: TaskSplitStrategy = .automatic,
        maxTokens: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.orchestrator = orchestrator ?? AgentConfig(
            name: "主 Agent",
            role: .orchestrator,
            provider: .claude,
            model: "claude-sonnet-4-20250514",
            systemPrompt: "你是一个任务协调者。你的职责是：\n1. 理解用户的任务需求\n2. 将复杂任务拆分为多个子任务\n3. 分配子任务给工作 Agent\n4. 汇总所有结果，给出最终答案"
        )
        self.workers = workers.isEmpty ? Self.defaultWorkers : workers
        self.maxParallelWorkers = maxParallelWorkers
        self.taskSplitStrategy = taskSplitStrategy
        self.maxTokens = maxTokens
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
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: "你是一个搜索助手。负责查找和整理信息。"
            ),
            AgentConfig(
                name: "代码 Agent",
                role: .worker,
                provider: .claude,
                model: "claude-3-5-haiku-20241022",
                systemPrompt: "你是一个代码助手。负责代码分析和实现。"
            ),
            AgentConfig(
                name: "文件 Agent",
                role: .worker,
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
    var assignedWorker: AgentConfig?
    var status: SubTaskStatus
    var result: String?

    init(
        id: UUID = UUID(),
        description: String,
        assignedWorker: AgentConfig? = nil,
        status: SubTaskStatus = .pending,
        result: String? = nil
    ) {
        self.id = id
        self.description = description
        self.assignedWorker = assignedWorker
        self.status = status
        self.result = result
    }
}

enum SubTaskStatus: String {
    case pending
    case running
    case completed
    case failed
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
    case synthesizing
    case completed
    case failed
}
