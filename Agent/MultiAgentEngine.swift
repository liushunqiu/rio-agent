import Foundation
import Combine

@MainActor
class MultiAgentEngine: ObservableObject {
    @Published var currentPlan: TaskPlan?
    @Published var isProcessing = false
    @Published var error: String?

    private let toolRegistry: ToolRegistry
    private var services: [UUID: AIService] = [:]
    private var config: MultiAgentConfig
    private var apiKeyStore: [AIProvider: String] = [:]
    private var baseURLStore: [AIProvider: String] = [:]

    init(config: MultiAgentConfig, toolRegistry: ToolRegistry = .shared) {
        self.config = config
        self.toolRegistry = toolRegistry
        setupServices()
    }

    /// Store API keys for providers so services can be created
    func configureAPIKeys(_ keys: [AIProvider: String], baseUrls: [AIProvider: String] = [:]) {
        apiKeyStore = keys
        baseURLStore = baseUrls
        setupServices()
    }

    private func setupServices() {
        // Setup orchestrator service
        if canCreateService(for: config.orchestrator.provider) {
            let apiKey = apiKeyStore[config.orchestrator.provider] ?? ""
            let baseURL = baseURLStore[config.orchestrator.provider] ?? ""
            services[config.orchestrator.id] = AIServiceFactory.createService(
                provider: config.orchestrator.provider,
                apiKey: apiKey,
                baseURL: baseURL
            )
        }

        // Setup worker services
        for worker in config.workers {
            if canCreateService(for: worker.provider) {
                let apiKey = apiKeyStore[worker.provider] ?? ""
                let baseURL = baseURLStore[worker.provider] ?? ""
                services[worker.id] = AIServiceFactory.createService(
                    provider: worker.provider,
                    apiKey: apiKey,
                    baseURL: baseURL
                )
            }
        }
    }

    private func canCreateService(for provider: AIProvider) -> Bool {
        switch provider {
        case .openAICompatible:
            return !(baseURLStore[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .claude, .openAI:
            return !(apiKeyStore[provider] ?? "").isEmpty
        }
    }

    func updateConfig(_ newConfig: MultiAgentConfig) {
        config = newConfig
        setupServices()
    }

    // MARK: - Main Processing

    func processTask(_ task: String) async -> String {
        guard config.isEnabled else {
            return await processSingleAgent(task)
        }

        isProcessing = true
        error = nil

        // Create task plan
        var plan = TaskPlan(originalTask: task)
        currentPlan = plan

        do {
            // Step 1: Orchestrator analyzes and splits the task
            plan.status = .planning
            currentPlan = plan

            let subTasks = try await splitTask(task)
            plan.subTasks = subTasks

            if subTasks.isEmpty {
                let finalResult = try await synthesizeResults(originalTask: task, subResults: [:])
                plan.status = .completed
                currentPlan = plan
                isProcessing = false
                return finalResult
            }

            // Step 2: Execute sub-tasks in parallel
            plan.status = .executing
            currentPlan = plan

            let results = try await executeSubTasks(subTasks)

            // Step 3: Orchestrator synthesizes results
            plan.status = .synthesizing
            currentPlan = plan

            let finalResult = try await synthesizeResults(originalTask: task, subResults: results)

            plan.status = .completed
            currentPlan = plan
            isProcessing = false

            return finalResult

        } catch {
            plan.status = .failed
            currentPlan = plan
            self.error = error.localizedDescription
            isProcessing = false
            return "处理失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Single Agent Fallback

    private func processSingleAgent(_ task: String) async -> String {
        // Use the original single agent logic
        return "单 Agent 模式: \(task)"
    }

    // MARK: - Task Splitting

    private func splitTask(_ task: String) async throws -> [SubTask] {
        guard let orchestratorService = services[config.orchestrator.id] else {
            throw MultiAgentError.serviceNotAvailable(config.orchestrator.name)
        }

        let availableWorkers = config.workers.filter { $0.isEnabled }
        let workerCatalog = availableWorkers.map { worker in
            """
            - worker_id: \(worker.id.uuidString)
              name: \(worker.name)
              capability: \(worker.capability.workerType)
              capability_description: \(worker.capability.description)
              model: \(worker.model)
              system_prompt: \(worker.systemPrompt.isEmpty ? "无" : worker.systemPrompt)
            """
        }.joined(separator: "\n")

        let splitPrompt = """
        你是一个任务协调专家。请分析以下用户任务，并将其拆分为可并行执行的子任务，然后从可用子 Agent 中选择最合适的执行者。

        用户任务: \(task)

        可用子 Agent:
        \(workerCatalog.isEmpty ? "无可用子 Agent" : workerCatalog)

        请以 JSON 格式返回子任务列表，格式如下:
        {
            "sub_tasks": [
                {
                    "description": "子任务描述",
                    "worker_id": "从可用子 Agent 中选择的 UUID",
                    "worker_type": "search/code/file/general/custom",
                    "reason": "选择该子 Agent 的简短原因"
                }
            ]
        }

        注意:
        1. 每个子任务应该是独立可执行的
        2. 子任务之间不应有依赖关系
        3. 如果任务简单不需要拆分，返回空数组
        4. 优先使用 worker_id 精确指定执行者
        5. worker_type 必须匹配所选子 Agent 的 capability
        6. 不要选择不存在的 worker_id
        """

        let messages = [Message.system(splitPrompt), Message.user(task)]
        let response = try await orchestratorService.sendMessage(messages, tools: [], model: config.orchestrator.model, maxTokens: config.effectiveMaxTokens)

        guard let content = response.content else {
            throw MultiAgentError.taskSplitFailed("无法获取拆分结果")
        }

        return parseSubTasks(from: content)
    }

    private func parseSubTasks(from response: String) -> [SubTask] {
        // Try to parse JSON response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subTasksArray = json["sub_tasks"] as? [[String: Any]] else {
            // If parsing fails, create a single sub-task with the original response
            return [SubTask(description: response, assignedWorker: fallbackWorker(for: .general))]
        }

        return subTasksArray.compactMap { taskDict in
            guard let description = taskDict["description"] as? String else { return nil }

            let workerId = (taskDict["worker_id"] as? String).flatMap(UUID.init(uuidString:))
            let workerType = AgentCapability(workerType: taskDict["worker_type"] as? String ?? "general")
            let worker = selectWorker(id: workerId, capability: workerType)

            return SubTask(
                description: description,
                workerId: workerId,
                workerType: workerType,
                assignedWorker: worker
            )
        }
    }

    private func selectWorker(id: UUID?, capability: AgentCapability) -> AgentConfig? {
        let enabledWorkers = config.workers.filter { $0.isEnabled }

        if let id, let exactMatch = enabledWorkers.first(where: { $0.id == id }) {
            return exactMatch
        }

        if let capabilityMatch = enabledWorkers.first(where: { $0.capability == capability }) {
            return capabilityMatch
        }

        return fallbackWorker(for: capability)
    }

    private func fallbackWorker(for capability: AgentCapability) -> AgentConfig? {
        let enabledWorkers = config.workers.filter { $0.isEnabled }

        if capability != .general,
           let generalWorker = enabledWorkers.first(where: { $0.capability == .general }) {
            return generalWorker
        }

        return enabledWorkers.first
    }

    // MARK: - Parallel Execution

    private func executeSubTasks(_ subTasks: [SubTask]) async throws -> [UUID: String] {
        var results: [UUID: String] = [:]

        // Execute in parallel with concurrency limit
        try await withThrowingTaskGroup(of: (UUID, String).self) { group in
            var activeCount = 0

            for subTask in subTasks {
                guard let worker = subTask.assignedWorker,
                      let service = services[worker.id] else {
                    continue
                }

                // Respect max parallel workers limit
                if activeCount >= config.maxParallelWorkers {
                    let result = try await group.next()!
                    results[result.0] = result.1
                    activeCount -= 1
                }

                group.addTask { [self] in
                    let result = try await self.executeSubTask(subTask, service: service, worker: worker)
                    return (subTask.id, result)
                }
                activeCount += 1
            }

            // Collect remaining results
            for try await (taskId, result) in group {
                results[taskId] = result
            }
        }

        return results
    }

    private static let maxToolCallIterations = 9999

    private func executeSubTask(_ subTask: SubTask, service: AIService, worker: AgentConfig) async throws -> String {
        var allResults: [String] = []
        var currentMessages: [Message] = [
            Message.system(worker.systemPrompt),
            Message.user(subTask.description)
        ]

        let toolDefinitions = toolRegistry.getToolDefinitions()
        var iterationCount = 0

        // Multi-round tool call loop (same pattern as AgentEngine)
        while iterationCount < Self.maxToolCallIterations {
            iterationCount += 1

            let response = try await service.sendMessage(
                currentMessages,
                tools: toolDefinitions,
                model: worker.model,
                maxTokens: config.effectiveMaxTokens
            )

            if let content = response.content, !content.isEmpty {
                allResults.append(content)
            }

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Add assistant message with tool calls
                currentMessages.append(Message(
                    role: .assistant,
                    content: response.content ?? "",
                    toolCalls: toolCalls
                ))

                // Execute tools and collect results
                var toolResults: [ToolResult] = []
                for toolCall in toolCalls {
                    let result = try await toolRegistry.executeTool(
                        name: toolCall.name,
                        arguments: toolCall.arguments.mapValues { $0.value }
                    )
                    toolResults.append(result)
                    allResults.append("工具 \(toolCall.name): \(String(result.output.prefix(200)))")
                }

                // Add tool results as next message for the AI to continue
                currentMessages.append(Message(
                    role: .user,
                    content: "",
                    toolResults: toolResults
                ))

                continue
            }

            break
        }

        return allResults.isEmpty ? "无结果" : allResults.joined(separator: "\n\n")
    }

    // MARK: - Result Synthesis

    private func synthesizeResults(originalTask: String, subResults: [UUID: String]) async throws -> String {
        guard let orchestratorService = services[config.orchestrator.id] else {
            throw MultiAgentError.serviceNotAvailable(config.orchestrator.name)
        }

        let resultsText = subResults.values.enumerated().map { index, result in
            "=== 子任务 \(index + 1) 结果 ===\n\(result)"
        }.joined(separator: "\n\n")

        let synthesizePrompt: String
        if subResults.isEmpty {
            synthesizePrompt = """
            你是一个任务协调者。你判断该任务不需要拆分给子 Agent。请直接回答用户的原始任务。

            原始用户任务: \(originalTask)
            """
        } else {
            synthesizePrompt = """
            你是一个任务协调者。请根据以下信息，给出最终的完整回答。

            原始用户任务: \(originalTask)

            子任务执行结果:
            \(resultsText)

            请综合所有信息，给出一个完整、准确、有条理的最终回答。
            """
        }

        let messages = [
            Message.system(config.orchestrator.systemPrompt),
            Message.user(synthesizePrompt)
        ]

        let response = try await orchestratorService.sendMessage(messages, tools: [], model: config.orchestrator.model, maxTokens: config.effectiveMaxTokens)

        return response.content ?? "无法生成最终结果"
    }
}

// MARK: - Errors

enum MultiAgentError: LocalizedError {
    case serviceNotAvailable(String)
    case taskSplitFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable(let name):
            return "服务不可用: \(name)"
        case .taskSplitFailed(let reason):
            return "任务拆分失败: \(reason)"
        case .executionFailed(let reason):
            return "执行失败: \(reason)"
        }
    }
}
