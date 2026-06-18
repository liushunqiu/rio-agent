import Foundation
import Combine

// MARK: - Multi-Agent Engine (Layers 2-4)

@MainActor
class MultiAgentEngine: ObservableObject {
    @Published var currentPlan: TaskPlan?
    @Published var isProcessing = false
    @Published var error: String?
    @Published var errorRecoveryContext: ErrorRecoveryContext?

    private let toolRegistry: ToolRegistry
    private let memory: AgentMemory?
    private var services: [UUID: AIService] = [:]
    private var config: MultiAgentConfig
    private var configSetStore: [ConfigSet] = []
    private let criticService: CriticService?
    private let verifierService: VerifierService?
    private var routerPreferredCapability: AgentCapability?

    /// Cached project context injected into every Worker
    private var projectContext: String = ""

    init(
        config: MultiAgentConfig,
        toolRegistry: ToolRegistry = .shared,
        criticService: CriticService? = nil,
        verifierService: VerifierService? = nil,
        memory: AgentMemory? = nil
    ) {
        self.config = config
        self.toolRegistry = toolRegistry
        self.criticService = criticService
        self.verifierService = verifierService
        self.memory = memory
        setupServices()
    }

    // MARK: - Service Setup

    func configureConfigSets(_ configSets: [ConfigSet]) {
        configSetStore = configSets
        setupServices()
    }

    private func setupServices() {
        services.removeAll()

        if let service = createService(for: config.orchestrator) {
            services[config.orchestrator.id] = service
        }
        for worker in config.workers {
            if let service = createService(for: worker) {
                services[worker.id] = service
            }
        }
    }

    private func createService(for agent: AgentConfig) -> AIService? {
        guard let configSet = agent.resolvedConfigSet(from: configSetStore) else {
            return nil
        }

        guard configSet.readinessIssue == nil else {
            return nil
        }

        let provider = configSet.provider
        let apiKey = configSet.loadAPIKey()
        let baseURL = configSet.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAICompatible:
            guard !baseURL.isEmpty else { return nil }
        case .claude, .openAI:
            guard !apiKey.isEmpty else { return nil }
        }

        return AIServiceFactory.createService(provider: provider, apiKey: apiKey, baseURL: baseURL)
    }

    func serviceUnavailableState(for agent: AgentConfig?) -> (message: String, recoveryContext: ErrorRecoveryContext) {
        guard let agent else {
            return ("未分配执行 Agent。请在 设置 → Multi-Agent 启用并选择一个 Worker。", .multiAgentWorkerAssignment)
        }

        guard let configSet = agent.resolvedConfigSet(from: configSetStore) else {
            return ("\(agent.name) 未选择可用模型配置。请前往 设置 → Multi-Agent 为该 Agent 选择模型配置。", .multiAgentWorkerModel)
        }

        if let readinessIssue = configSet.readinessIssue {
            return ("\(agent.name) 使用的模型配置「\(configSet.name)」不可用：\(readinessIssue)。请前往 设置 → AI 配置 → 模型配置补全。", .multiAgentWorkerModel)
        }

        return ("\(agent.name) 使用的模型配置「\(configSet.name)」未能创建服务。请检查提供商、端点地址和 API Key 是否匹配。", .multiAgentWorkerModel)
    }

    func serviceUnavailableMessage(for agent: AgentConfig?) -> String {
        serviceUnavailableState(for: agent).message
    }

    func serviceUnavailableResult(for subTask: SubTask) -> ExecutionResult {
        let state = serviceUnavailableState(for: subTask.assignedWorker)
        return ExecutionResult(
            subTaskId: subTask.id,
            output: "",
            errors: [state.message],
            retryCount: 0,
            verificationStatus: .needsRetry,
            verificationSummary: "\(state.message) 当前子任务无法验证。",
            recoveryContext: state.recoveryContext
        )
    }

    private func composedPrompt(for agent: AgentConfig) -> String {
        let scope: SystemPromptScope = agent.role == .orchestrator
            ? .orchestrator
            : .worker(agent.capability)
        return SystemPromptComposer.compose(
            basePrompt: agent.systemPrompt,
            scope: scope,
            availableTools: toolRegistry.getAllTools()
        )
    }

    func updateConfig(_ newConfig: MultiAgentConfig) {
        config = newConfig
        setupServices()
    }

    var currentConfig: MultiAgentConfig {
        config
    }

    var currentRouterPreferredCapability: AgentCapability? {
        routerPreferredCapability
    }

    func setRouterPreferredCapability(_ capability: AgentCapability?) {
        routerPreferredCapability = capability
    }

    func clearRouterPreferredCapability() {
        routerPreferredCapability = nil
    }

    func cancelProcessing() {
        isProcessing = false
        error = nil
        errorRecoveryContext = nil

        guard var plan = currentPlan else { return }
        plan.status = .cancelled
        for index in plan.subTasks.indices where plan.subTasks[index].status == .pending || plan.subTasks[index].status == .running {
            plan.subTasks[index].status = .cancelled
            plan.subTasks[index].result = "已取消"
            plan.subTasks[index].verificationStatus = .unverified
        }
        currentPlan = plan
    }

    func executionBatches(for wave: [SubTask]) -> [[SubTask]] {
        let batchSize = max(config.maxParallelWorkers, 1)
        guard !wave.isEmpty else { return [] }

        var batches: [[SubTask]] = []
        var start = 0
        while start < wave.count {
            let end = min(start + batchSize, wave.count)
            batches.append(Array(wave[start..<end]))
            start = end
        }
        return batches
    }

    // MARK: - Main Processing Pipeline

    func processTask(_ task: String) async -> String {
        isProcessing = true
        error = nil
        errorRecoveryContext = nil

        var plan = TaskPlan(originalTask: task)
        currentPlan = plan

        do {
            try Task.checkCancellation()

            // ── Layer 2: Planner — Orchestrator generates DAG ──
            plan.status = .planning
            currentPlan = plan

            // Build project context once for all workers
            projectContext = buildProjectContext()

            let subTasks = try await splitTask(task)
            plan.subTasks = subTasks

            if subTasks.isEmpty {
                try Task.checkCancellation()
                let finalResult = try await synthesizeResults(originalTask: task, results: [:])
                plan.status = .completed
                currentPlan = plan
                isProcessing = false
                routerPreferredCapability = nil
                return finalResult
            }

            // ── Layer 3: Execution Guild — DAG wave-based execution ──
            plan.status = .executing
            currentPlan = plan

            let results = try await executeSubTasksDAG(plan: &plan)

            // ── Layer 4: Critic & Verification ──
            try Task.checkCancellation()
            plan.status = .verifying
            currentPlan = plan

            // Verify results — mark verified / needsRetry status on each sub-task
            for subTask in plan.subTasks {
                if let idx = plan.subTasks.firstIndex(where: { $0.id == subTask.id }) {
                    if let result = results[subTask.id] {
                        plan.subTasks[idx].verificationStatus = result.verificationStatus
                        plan.subTasks[idx].verificationSummary = result.verificationSummary
                    }
                }
            }
            currentPlan = plan

            // ── Synthesis — Orchestrator produces final answer ──
            try Task.checkCancellation()
            plan.status = .synthesizing
            currentPlan = plan

            let finalResult = try await synthesizeResults(originalTask: task, results: results)

            plan.status = .completed
            currentPlan = plan
            isProcessing = false
            routerPreferredCapability = nil

            return finalResult

        } catch is CancellationError {
            cancelProcessing()
            routerPreferredCapability = nil
            return "任务已取消"
        } catch {
            plan.status = .failed
            currentPlan = plan
            self.error = error.localizedDescription
            self.errorRecoveryContext = recoveryContext(for: error)
            isProcessing = false
            routerPreferredCapability = nil
            return "处理失败: \(error.localizedDescription)"
        }
    }

    private func recoveryContext(for error: Error) -> ErrorRecoveryContext? {
        guard case MultiAgentError.serviceNotAvailable(let name) = error else {
            return nil
        }

        if name == config.orchestrator.name {
            return .multiAgentOrchestratorModel
        }

        return .multiAgentWorkerModel
    }

    // MARK: - Layer 2: Planner — Project Context Builder

    /// Builds a rich context string injected into every Worker so they are NOT blind.
    func buildProjectContext() -> String {
        var parts: [String] = []

        let memoryContext = memory?.generateMemoryContext().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !memoryContext.isEmpty {
            parts.append("## Verified Memory\n\(memoryContext)")
        }

        // Working directory
        if let dir = toolRegistry.workingDirectory {
            parts.append("## 工作目录\n\(dir)")

            // AGENT.md — project-level context
            let agentMDPath = "\(dir)/AGENT.md"
            if let content = FileManager.default.contents(atPath: agentMDPath),
               let mdString = String(data: content, encoding: .utf8) {
                parts.append("## 项目上下文 (from AGENT.md)\n\(mdString)")
            }

            // Top-level directory listing (shallow, fast)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                let filtered = items
                    .filter { !$0.hasPrefix(".") }
                    .sorted()
                    .prefix(50)
                let listing = filtered.joined(separator: "\n")
                parts.append("## 项目顶层结构\n\(listing)")
            }
        }

        if parts.isEmpty {
            return "（无项目上下文）"
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Layer 2: Planner — Enhanced DAG Task Splitting

    private func splitTask(_ task: String) async throws -> [SubTask] {
        guard let orchestratorService = services[config.orchestrator.id] else {
            throw MultiAgentError.serviceNotAvailable(config.orchestrator.name)
        }
        let memoryContext = normalizedMemoryContext()

        let availableWorkers = config.workers.filter { $0.isEnabled }
        let workerCatalog = availableWorkers.map { worker in
            """
            - worker_id: \(worker.id.uuidString)
              name: \(worker.name)
              capability: \(worker.capability.workerType)
              capability_description: \(worker.capability.description)
              model: \(worker.model)
            """
        }.joined(separator: "\n")
        let routingPreference = routerPreferredCapability.map { capability in
            """

            Router 预选能力: \(capability.workerType)
            优先将核心子任务分配给 capability 为 \(capability.workerType) 的子 Agent；只有当任务明显需要其他能力时才改派。
            """
        } ?? ""

        let splitPrompt = """
        你是一个任务协调专家。请分析以下用户任务，将其拆分为带有依赖关系的子任务 DAG（有向无环图），并从可用子 Agent 中选择最合适的执行者。

        用户任务: \(task)

        已验证长期记忆:
        \(memoryContext)

        可用子 Agent:
        \(workerCatalog.isEmpty ? "无可用子 Agent" : workerCatalog)
        \(routingPreference)

        请以 JSON 格式返回子任务列表:
        {
            "sub_tasks": [
                {
                    "task_id": "唯一标识符 (UUID 格式)",
                    "description": "子任务的详细描述，包含足够信息让执行者独立完成任务",
                    "worker_id": "从可用子 Agent 中选择的 UUID",
                    "worker_type": "search/code/file/general/custom",
                    "reason": "选择该子 Agent 的简短原因",
                    "depends_on": ["依赖的 task_id 列表，无依赖则为空数组"]
                }
            ]
        }

        关键原则:
        1. 如果子任务 B 需要子任务 A 的输出才能开始，则 B 的 depends_on 必须包含 A 的 task_id
        2. 没有依赖的子任务会被并行执行，有依赖的子任务会等待前置任务完成
        3. 每个子任务的 description 必须足够详细，让执行者无需额外上下文即可工作
        4. 如果任务简单不需要拆分，返回空的 sub_tasks 数组
        5. 优先使用 worker_id 精确指定执行者；不要选择不存在的 worker_id
        6. 不要创建循环依赖
        """

        let messages = [Message.system(splitPrompt), Message.user(task)]
        let response = try await orchestratorService.sendMessage(
            messages, tools: [], model: config.orchestrator.model, maxTokens: config.effectiveMaxTokens
        )

        guard let content = response.content else {
            throw MultiAgentError.taskSplitFailed("无法获取拆分结果")
        }

        return parseSubTasks(from: content)
    }

    func parseSubTasks(from response: String) -> [SubTask] {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subTasksArray = json["sub_tasks"] as? [[String: Any]] else {
            return []
        }

        // First pass: build task_id -> UUID mapping
        var taskIdMap: [String: UUID] = [:]
        for taskDict in subTasksArray {
            if let taskId = taskDict["task_id"] as? String,
               let uuid = UUID(uuidString: taskId) {
                taskIdMap[taskId] = uuid
            } else {
                // Generate a UUID if task_id is missing or invalid
                taskIdMap[taskDict["task_id"] as? String ?? ""] = UUID()
            }
        }

        // Second pass: create SubTasks with resolved dependencies
        return subTasksArray.compactMap { taskDict in
            guard let description = taskDict["description"] as? String else { return nil }

            let rawTaskId = taskDict["task_id"] as? String ?? ""
            let subTaskId = taskIdMap[rawTaskId] ?? UUID()
            let workerId = (taskDict["worker_id"] as? String).flatMap(UUID.init(uuidString:))
            let workerType = AgentCapability(workerType: taskDict["worker_type"] as? String ?? routerPreferredCapability?.workerType ?? "general")
            let reason = taskDict["reason"] as? String
            let worker = selectWorker(id: workerId, capability: workerType)

            // Resolve dependency UUIDs
            let dependsOnStrings = taskDict["depends_on"] as? [String] ?? []
            let dependencies = dependsOnStrings.compactMap { taskIdMap[$0] }

            return SubTask(
                id: subTaskId,
                description: description,
                workerId: workerId,
                workerType: workerType,
                assignedWorker: worker,
                assignmentReason: reason,
                dependencies: dependencies
            )
        }
    }

    // MARK: - Worker Selection

    private func selectWorker(id: UUID?, capability: AgentCapability) -> AgentConfig? {
        let enabledWorkers = config.workers.filter { $0.isEnabled }
        if let id, let exactMatch = enabledWorkers.first(where: { $0.id == id }) { return exactMatch }
        if let capMatch = enabledWorkers.first(where: { $0.capability == capability }) { return capMatch }
        return fallbackWorker(for: capability)
    }

    private func fallbackWorker(for capability: AgentCapability) -> AgentConfig? {
        let enabledWorkers = config.workers.filter { $0.isEnabled }
        if capability != .general, let generalWorker = enabledWorkers.first(where: { $0.capability == .general }) {
            return generalWorker
        }
        return enabledWorkers.first
    }

    // MARK: - Layer 3: Execution Guild — DAG Wave-Based Execution

    /// Execute sub-tasks respecting dependency DAG — independent tasks run in parallel waves.
    private func executeSubTasksDAG(plan: inout TaskPlan) async throws -> [UUID: ExecutionResult] {
        var allResults: [UUID: ExecutionResult] = [:]
        var finishedIds: Set<UUID> = []
        var successfulIds: Set<UUID> = []

        while finishedIds.count < plan.subTasks.count {
            try Task.checkCancellation()

            let wave = getNextWave(plan: plan, finishedIds: finishedIds, successfulIds: successfulIds)

            if wave.isEmpty {
                // Remaining tasks are blocked by failed/unverified dependencies or an invalid DAG.
                for subTask in plan.subTasks where !finishedIds.contains(subTask.id) {
                    let result = dependencyBlockedResult(
                        for: subTask,
                        plan: plan,
                        finishedIds: finishedIds,
                        successfulIds: successfulIds
                    )
                    updateSubTask(
                        subTask.id,
                        in: &plan,
                        status: .failed,
                        result: subTaskDisplayResult(for: result, status: .failed),
                        recoveryContext: result.recoveryContext
                    )
                    finishedIds.insert(subTask.id)
                    allResults[subTask.id] = result
                }
                break
            }

            // Execute the current wave in limited parallel batches
            for batch in executionBatches(for: wave) {
                try Task.checkCancellation()

                try await withThrowingTaskGroup(of: (UUID, ExecutionResult).self) { group in
                    for subTask in batch {
                        guard let worker = subTask.assignedWorker,
                              let service = services[worker.id] else {
                            let result = serviceUnavailableResult(for: subTask)
                            updateSubTask(
                                subTask.id,
                                in: &plan,
                                status: .failed,
                                result: subTaskDisplayResult(for: result, status: .failed),
                                recoveryContext: result.recoveryContext
                            )
                            finishedIds.insert(subTask.id)
                            allResults[subTask.id] = result
                            continue
                        }

                        updateSubTask(subTask.id, in: &plan, status: .running)

                        // Build context with results from completed dependency tasks
                        let dependencyResults = subTask.dependencies.compactMap { allResults[$0] }
                        let context = buildWorkerContext(
                            for: subTask, dependencyResults: dependencyResults
                        )

                        group.addTask { [self] in
                            try Task.checkCancellation()
                            let result = try await self.executeSingleSubTask(
                                subTask: subTask, service: service, worker: worker, context: context
                            )
                            return (subTask.id, result)
                        }
                    }

                    for try await (taskId, result) in group {
                        allResults[taskId] = result
                        finishedIds.insert(taskId)

                        let status: SubTaskStatus = (result.hasErrors || result.verificationStatus == .needsRetry) ? .failed : .completed
                        if status == .completed {
                            successfulIds.insert(taskId)
                        }
                        updateSubTask(
                            taskId,
                            in: &plan,
                            status: status,
                            result: subTaskDisplayResult(for: result, status: status),
                            recoveryContext: result.recoveryContext
                        )

                        if let idx = plan.subTasks.firstIndex(where: { $0.id == taskId }) {
                            plan.subTasks[idx].retryCount = result.retryCount
                            plan.subTasks[idx].verificationStatus = result.verificationStatus
                            plan.subTasks[idx].verificationSummary = result.verificationSummary
                        }
                        currentPlan = plan
                    }
                }
            }
        }

        return allResults
    }

    /// Compute the next wave: tasks whose dependencies are ALL satisfied.
    private func getNextWave(plan: TaskPlan, finishedIds: Set<UUID>, successfulIds: Set<UUID>) -> [SubTask] {
        plan.subTasks.filter { subTask in
            guard !finishedIds.contains(subTask.id) else { return false }
            return subTask.dependencies.allSatisfy { successfulIds.contains($0) }
        }
    }

    func dependencyBlockedResult(
        for subTask: SubTask,
        plan: TaskPlan,
        finishedIds: Set<UUID>,
        successfulIds: Set<UUID>
    ) -> ExecutionResult {
        let failedDependencies = subTask.dependencies.filter { dependencyId in
            finishedIds.contains(dependencyId) && !successfulIds.contains(dependencyId)
        }
        let pendingDependencies = subTask.dependencies.filter { !finishedIds.contains($0) }
        let nameById = Dictionary(uniqueKeysWithValues: plan.subTasks.map { ($0.id, $0.description) })

        var details: [String] = []
        if !failedDependencies.isEmpty {
            let descriptions = failedDependencies.map { nameById[$0] ?? $0.uuidString }.joined(separator: "；")
            details.append("失败或未验证的前置任务：\(descriptions)")
        }
        if !pendingDependencies.isEmpty {
            let descriptions = pendingDependencies.map { nameById[$0] ?? $0.uuidString }.joined(separator: "；")
            details.append("未完成的前置任务：\(descriptions)")
        }

        let reason = details.isEmpty ? "依赖无法满足" : details.joined(separator: "\n")
        return ExecutionResult(
            subTaskId: subTask.id,
            output: "",
            errors: ["前置依赖未成功完成，当前子任务已阻塞。\n\(reason)"],
            retryCount: 0,
            verificationStatus: .needsRetry,
            verificationSummary: "当前子任务依赖失败或未完成的前置任务，因此未执行，不能视为完成。",
            recoveryContext: nil
        )
    }

    /// Build context for a Worker including project info, dependency results, and instructions.
    func buildWorkerContext(for subTask: SubTask, dependencyResults: [ExecutionResult]) -> String {
        var context = projectContext

        if !dependencyResults.isEmpty {
            context += "\n\n## 前置任务结果\n"
            context += "以下是你依赖的已完成任务的输出，请在此基础上继续工作：\n\n"
            for (i, dep) in dependencyResults.enumerated() {
                context += "### 前置任务 \(i + 1) 输出\n"
                context += truncatedDependencySummary(for: dep) + "\n\n"
            }
        }

        return context
    }

    func subTaskDisplayResult(for result: ExecutionResult, status: SubTaskStatus) -> String? {
        let output = meaningfulText(result.output)
        let errors = result.errors.compactMap(meaningfulText)
        let summary = result.verificationSummary.flatMap(meaningfulText)

        switch status {
        case .completed, .running, .pending:
            return output ?? summary
        case .cancelled:
            return errors.first ?? summary ?? output ?? "任务已取消"
        case .failed:
            var parts: [String] = []
            if let output {
                parts.append(output)
            }
            if !errors.isEmpty {
                parts.append("错误:\n" + errors.joined(separator: "\n"))
            }
            if let summary, !parts.contains(summary) {
                parts.append("验证:\n\(summary)")
            }
            return parts.isEmpty ? "执行失败，但未返回具体原因。" : parts.joined(separator: "\n\n")
        }
    }

    private func truncatedDependencySummary(for result: ExecutionResult) -> String {
        let status: SubTaskStatus = (result.hasErrors || result.verificationStatus == .needsRetry) ? .failed : .completed
        let summary = subTaskDisplayResult(for: result, status: status) ?? "（无可用输出）"

        let maxLength = 5000
        guard summary.count > maxLength else { return summary }
        return String(summary.prefix(4000))
            + "\n\n[... 已截断 \(summary.count - 4500) 字符 ...]\n\n"
            + String(summary.suffix(500))
    }

    private func meaningfulText(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "无结果" else { return nil }
        return text
    }

    // MARK: - Layer 3+4: Single Worker Execution with PEV Loop

    private static let maxToolCallIterations = 200

    /// Execute a single sub-task with the PEV (Plan-Execute-Verify) retry loop.
    private func executeSingleSubTask(
        subTask: SubTask,
        service: AIService,
        worker: AgentConfig,
        context: String
    ) async throws -> ExecutionResult {
        var currentSubTask = subTask
        var allErrors: [String] = []
        var lastOutput = ""
        var totalRetries = 0
        var lastEvidence: [String] = []

        for attempt in 0...(config.enableCritic ? config.maxRetries : 0) {
            try Task.checkCancellation()

            let executionResult = try await runWorkerToolLoop(
                subTask: currentSubTask, service: service, worker: worker, context: context
            )

            lastOutput = executionResult.output
            let errors = executionResult.errors
            lastEvidence = executionResult.evidence

            if errors.isEmpty {
                let verification = await verifyResult(
                    subTask: subTask,
                    output: lastOutput,
                    errors: [],
                    evidence: lastEvidence,
                    worker: worker
                )

                return ExecutionResult(
                    subTaskId: subTask.id,
                    output: lastOutput,
                    errors: verification.status == .needsRetry ? [verification.summary] : [],
                    retryCount: totalRetries,
                    verificationStatus: verification.status,
                    verificationSummary: verification.summary,
                    recoveryContext: nil
                )
            }

            allErrors = errors
            totalRetries += 1

            // If retries exhausted, return with errors
            if attempt >= (config.enableCritic ? config.maxRetries : 0) {
                break
            }

            // ── Layer 4: Critic — analyze failure, generate fix suggestions ──
            let criticFeedback = await analyzeAndRetry(
                subTask: subTask, errors: errors, output: lastOutput, worker: worker
            )

            // Inject critic feedback into the task description for the next attempt
            currentSubTask = SubTask(
                id: subTask.id,
                description: """
                \(subTask.description)

                ---
                ⚠️ 上一次执行遇到问题（第 \(attempt + 1) 次尝试），请根据以下反馈修正：

                \(criticFeedback)
                """,
                workerId: subTask.workerId,
                workerType: subTask.workerType,
                assignedWorker: subTask.assignedWorker,
                assignmentReason: subTask.assignmentReason,
                dependencies: subTask.dependencies
            )

            // Update plan to show retry
            if let plan = currentPlan,
               let idx = plan.subTasks.firstIndex(where: { $0.id == subTask.id }) {
                var updatedPlan = plan
                updatedPlan.subTasks[idx].retryCount = totalRetries
                updatedPlan.subTasks[idx].status = .running
                currentPlan = updatedPlan
            }
        }

        return ExecutionResult(
            subTaskId: subTask.id,
            output: lastOutput,
            errors: allErrors,
            retryCount: totalRetries,
            verificationStatus: .needsRetry,
            verificationSummary: lastEvidence.isEmpty ? "执行失败，且未形成可验证证据。" : "执行失败，已有证据显示任务未完成。",
            recoveryContext: nil
        )
    }

    /// Run the Worker's tool-call loop for a single attempt (no retry logic here).
    private func runWorkerToolLoop(
        subTask: SubTask,
        service: AIService,
        worker: AgentConfig,
        context: String
    ) async throws -> (output: String, errors: [String], evidence: [String]) {
        var allResults: [String] = []
        var collectedErrors: [String] = []
        var evidenceLog: [String] = []

        // Build messages with structured XML context
        var currentMessages: [Message] = [
            Message.system(composedPrompt(for: worker)),
            Message.user("""
            <project_context>
            \(context)
            </project_context>

            <task>
            \(subTask.description)
            </task>

            请使用提供的工具完成任务。如果遇到错误，请分析原因并尝试修复。
            """)
        ]

        let toolDefinitions = toolRegistry.getToolDefinitions()
        var iterationCount = 0

        while iterationCount < Self.maxToolCallIterations {
            try Task.checkCancellation()
            iterationCount += 1

            let response = try await service.sendMessage(
                currentMessages, tools: toolDefinitions,
                model: worker.model, maxTokens: config.effectiveMaxTokens
            )

            if let content = response.content, !content.isEmpty {
                allResults.append(content)
            }

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                currentMessages.append(Message(
                    role: .assistant, content: response.content ?? "", toolCalls: toolCalls
                ))

                var toolResults: [ToolResult] = []
                for toolCall in toolCalls {
                    try Task.checkCancellation()
                    let result = try await toolRegistry.executeTool(
                        name: toolCall.name, arguments: toolCall.arguments.mapValues { $0.value }
                    )
                    toolResults.append(result)
                    evidenceLog.append(formatEvidence(toolCall: toolCall, result: result))

                    // Collect errors for PEV
                    if result.status == .error, let errorMsg = result.error {
                        collectedErrors.append("[\(toolCall.name)] \(errorMsg)")
                    } else if result.status == .cancelled, let reason = result.error {
                        collectedErrors.append("[\(toolCall.name)] 已取消：\(reason)")
                    }
                }

                currentMessages.append(Message(role: .user, content: "", toolResults: toolResults))
                continue
            }

            break
        }

        let output = allResults.isEmpty ? "无结果" : allResults.joined(separator: "\n\n")
        return (output: output, errors: collectedErrors, evidence: evidenceLog)
    }

    // MARK: - Layer 4: Critic — Error Analysis & Fix Suggestions

    /// The Critic analyzes execution errors and generates actionable fix suggestions.
    private func analyzeAndRetry(
        subTask: SubTask,
        errors: [String],
        output: String,
        worker: AgentConfig
    ) async -> String {
        guard let criticService else {
            return CriticService(aiService: nil, model: "").fallbackFeedback(errors: errors)
        }
        return await criticService.analyze(
            task: subTask.description,
            errors: errors,
            output: output,
            systemPrompt: composedPrompt(for: worker)
        )
    }

    private func verifyResult(
        subTask: SubTask,
        output: String,
        errors: [String],
        evidence: [String],
        worker: AgentConfig
    ) async -> VerifierService.VerificationOutcome {
        guard let verifierService else {
            return await VerifierService(aiService: nil, model: "").verify(
                task: subTask.description,
                output: output,
                errors: errors,
                evidence: evidence,
                systemPrompt: composedPrompt(for: worker)
            )
        }

        return await verifierService.verify(
            task: subTask.description,
            output: output,
            errors: errors,
            evidence: evidence,
            systemPrompt: composedPrompt(for: worker)
        )
    }

    private func formatEvidence(toolCall: ToolCall, result: ToolResult) -> String {
        let maxLength = 500
        let payload: String
        if result.status == .error || result.status == .cancelled {
            payload = result.error ?? "未知错误"
        } else {
            payload = result.output
        }

        let normalized = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = normalized.count > maxLength
            ? String(normalized.prefix(maxLength)) + " ...[truncated]"
            : normalized

        return """
        tool=\(toolCall.name)
        status=\(result.status.rawValue.uppercased())
        evidence=\(truncated.isEmpty ? "（空输出）" : truncated)
        """
    }

    private func normalizedMemoryContext() -> String {
        let content = memory?.generateMemoryContext().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return content.isEmpty ? "（无）" : content
    }

    // MARK: - Result Synthesis (enhanced with execution metadata)

    private func synthesizeResults(originalTask: String, results: [UUID: ExecutionResult]) async throws -> String {
        try Task.checkCancellation()

        guard let orchestratorService = services[config.orchestrator.id] else {
            throw MultiAgentError.serviceNotAvailable(config.orchestrator.name)
        }
        let memoryContext = normalizedMemoryContext()

        if results.isEmpty {
            let messages = [
                Message.system(composedPrompt(for: config.orchestrator)),
                Message.user("""
                你是一个任务协调者。你判断该任务不需要拆分给子 Agent。请直接回答用户的原始任务。

                已验证长期记忆:
                \(memoryContext)

                原始用户任务: \(originalTask)
                """)
            ]
            let response = try await orchestratorService.sendMessage(
                messages, tools: [], model: config.orchestrator.model, maxTokens: config.effectiveMaxTokens
            )
            return response.content ?? "无法生成最终结果"
        }

        // Build rich results text including errors and retry info
        let resultsText = results.values.enumerated().map { index, result in
            var text = "=== 子任务 \(index + 1) ===\n"
            if result.retryCount > 0 {
                text += "（经过 \(result.retryCount) 次重试）\n"
            }
            text += "验证状态: \(result.verificationStatus.displayText)\n"
            if let summary = result.verificationSummary, !summary.isEmpty {
                text += "验证摘要: \(summary)\n"
            }
            text += result.output
            if result.hasErrors {
                text += "\n\n⚠️ 残留错误:\n" + result.errors.joined(separator: "\n")
            }
            return text
        }.joined(separator: "\n\n")

        let synthesizePrompt = """
        你是一个任务协调者。请根据以下信息，给出最终的完整回答。

        原始用户任务: \(originalTask)

        已验证长期记忆:
        \(memoryContext)

        子任务执行结果:
        \(resultsText)

        请综合所有信息，给出一个完整、准确、有条理的最终回答。
        如果有子任务失败，请说明哪些部分完成了、哪些未完成，以及可能的原因。
        """

        let messages = [
            Message.system(composedPrompt(for: config.orchestrator)),
            Message.user(synthesizePrompt)
        ]

        let response = try await orchestratorService.sendMessage(
            messages, tools: [], model: config.orchestrator.model, maxTokens: config.effectiveMaxTokens
        )

        return response.content ?? "无法生成最终结果"
    }

    // MARK: - Plan Update Helpers

    private func updateSubTask(
        _ id: UUID,
        in plan: inout TaskPlan,
        status: SubTaskStatus,
        result: String? = nil,
        recoveryContext: ErrorRecoveryContext? = nil
    ) {
        guard let index = plan.subTasks.firstIndex(where: { $0.id == id }) else { return }
        plan.subTasks[index].status = status
        if let result { plan.subTasks[index].result = result }
        plan.subTasks[index].recoveryContext = recoveryContext
        currentPlan = plan
    }
}

// MARK: - Errors

enum MultiAgentError: LocalizedError {
    case serviceNotAvailable(String)
    case taskSplitFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable(let name): return "服务不可用: \(name)"
        case .taskSplitFailed(let reason): return "任务拆分失败: \(reason)"
        case .executionFailed(let reason): return "执行失败: \(reason)"
        }
    }
}
