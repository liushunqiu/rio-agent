import SwiftUI

struct MultiAgentSettingsDraft {
    var orchestratorConfigSetId: UUID?
    var orchestratorPrompt: String
    var workers: [AgentConfig]
    var maxParallel: Int
    var taskStrategy: TaskSplitStrategy
    var maxRetries: Int
    var enableCritic: Bool
    var routerEnabled: Bool
    var routerConfigSetId: UUID?
    var routerModel: String
    var routerPrompt: String
    var enableQwenRouter: Bool
    var qwenBaseUrl: String
    var qwenModel: String
    var disableThinking: Bool
    var qwenTemperature: Float
    var qwenTopP: Float
    var qwenTopK: Int
    var qwenPresencePenalty: Float

    func applied(to configuration: MultiAgentConfig, availableConfigSets: [ConfigSet]) -> MultiAgentConfig {
        var updated = configuration
        let readyConfigSets = availableConfigSets.filter(\.isConfigured)
        var orchestrator = updated.orchestrator
        let resolvedOrchestratorConfigSet = readyConfigSets.first(where: { $0.id == orchestratorConfigSetId })
            ?? updated.orchestrator.resolvedConfigSet(from: readyConfigSets)
            ?? readyConfigSets.first

        orchestrator.applyConfigSet(resolvedOrchestratorConfigSet)
        orchestrator.systemPrompt = orchestratorPrompt

        updated.orchestrator = orchestrator
        updated.workers = workers.map { worker in
            var updatedWorker = worker
            let resolvedConfigSet = worker.resolvedConfigSet(from: readyConfigSets)
                ?? readyConfigSets.first
            updatedWorker.applyConfigSet(resolvedConfigSet)
            return updatedWorker
        }
        updated.maxParallelWorkers = maxParallel
        updated.taskSplitStrategy = taskStrategy
        updated.maxRetries = maxRetries
        updated.enableCritic = enableCritic
        updated.router.enabled = routerEnabled
        updated.router.configSetId = readyConfigSets.contains(where: { $0.id == routerConfigSetId })
            ? routerConfigSetId
            : nil
        updated.router.model = routerModel
        updated.router.prompt = routerPrompt
        updated.router.enableQwenRouter = enableQwenRouter
        updated.router.qwenBaseUrl = qwenBaseUrl
        updated.router.qwenModel = qwenModel
        updated.router.disableThinking = disableThinking
        updated.router.temperature = qwenTemperature
        updated.router.topP = qwenTopP
        updated.router.topK = qwenTopK
        updated.router.presencePenalty = qwenPresencePenalty
        updated.reconcileConfigSets(with: readyConfigSets)
        return updated
    }
}

struct MultiAgentSettingsView: View {
    @Binding var config: MultiAgentConfig
    let aiConfig: AIConfigInfo
    let launchContext: SettingsLaunchContext?

    @State private var orchestratorConfigSetId: UUID?
    @State private var orchestratorPrompt: String
    @State private var workers: [AgentConfig]
    @State private var maxParallel: Int
    @State private var taskStrategy: TaskSplitStrategy
    @State private var maxRetries: Int
    @State private var enableCritic: Bool
    @State private var showingAddWorker = false
    @State private var editingWorker: AgentConfig?
    @State private var pendingDeleteWorker: AgentConfig?

    @State private var routerEnabled: Bool
    @State private var routerConfigSetId: UUID?
    @State private var routerModel: String
    @State private var routerPrompt: String
    
    // Qwen3.5-4B 专用配置状态
    @State private var enableQwenRouter: Bool
    @State private var qwenBaseUrl: String
    @State private var qwenModel: String
    @State private var disableThinking: Bool
    @State private var qwenTemperature: Float
    @State private var qwenTopP: Float
    @State private var qwenTopK: Int
    @State private var qwenPresencePenalty: Float
    @State private var draftApplyTask: Task<Void, Never>?

    init(config: Binding<MultiAgentConfig>, aiConfig: AIConfigInfo, launchContext: SettingsLaunchContext? = nil) {
        self._config = config
        self.aiConfig = aiConfig
        self.launchContext = launchContext
        let initial = config.wrappedValue
        let readyConfigSets = aiConfig.allConfigSets.filter(\.isConfigured)
        let fallbackConfigSet = initial.orchestrator.resolvedConfigSet(from: readyConfigSets)
            ?? readyConfigSets.first(where: { $0.provider == initial.orchestrator.provider })
            ?? readyConfigSets.first

        self._orchestratorConfigSetId = State(initialValue: fallbackConfigSet?.id)
        self._orchestratorPrompt = State(initialValue: initial.orchestrator.systemPrompt)
        self._workers = State(initialValue: initial.workers.map { worker in
            var updated = worker
            let resolvedConfigSet = worker.resolvedConfigSet(from: readyConfigSets)
                ?? readyConfigSets.first(where: { $0.provider == worker.provider })
                ?? readyConfigSets.first
            updated.applyConfigSet(resolvedConfigSet)
            return updated
        })
        self._maxParallel = State(initialValue: initial.maxParallelWorkers)
        self._taskStrategy = State(initialValue: initial.taskSplitStrategy)
        self._maxRetries = State(initialValue: initial.maxRetries)
        self._enableCritic = State(initialValue: initial.enableCritic)
        self._routerEnabled = State(initialValue: initial.router.enabled)
        self._routerConfigSetId = State(initialValue: initial.router.configSetId)
        self._routerModel = State(initialValue: initial.router.model)
        self._routerPrompt = State(initialValue: initial.router.prompt)
        
        // Qwen3.5-4B 专用配置初始化
        self._enableQwenRouter = State(initialValue: initial.router.enableQwenRouter)
        self._qwenBaseUrl = State(initialValue: initial.router.qwenBaseUrl)
        self._qwenModel = State(initialValue: initial.router.qwenModel)
        self._disableThinking = State(initialValue: initial.router.disableThinking)
        self._qwenTemperature = State(initialValue: initial.router.temperature)
        self._qwenTopP = State(initialValue: initial.router.topP)
        self._qwenTopK = State(initialValue: initial.router.topK)
        self._qwenPresencePenalty = State(initialValue: initial.router.presencePenalty)
    }

    private func currentDraft() -> MultiAgentSettingsDraft {
        MultiAgentSettingsDraft(
            orchestratorConfigSetId: orchestratorConfigSetId,
            orchestratorPrompt: orchestratorPrompt,
            workers: workers,
            maxParallel: maxParallel,
            taskStrategy: taskStrategy,
            maxRetries: maxRetries,
            enableCritic: enableCritic,
            routerEnabled: routerEnabled,
            routerConfigSetId: routerConfigSetId,
            routerModel: routerModel,
            routerPrompt: routerPrompt,
            enableQwenRouter: enableQwenRouter,
            qwenBaseUrl: qwenBaseUrl,
            qwenModel: qwenModel,
            disableThinking: disableThinking,
            qwenTemperature: qwenTemperature,
            qwenTopP: qwenTopP,
            qwenTopK: qwenTopK,
            qwenPresencePenalty: qwenPresencePenalty
        )
    }

    private func applyDraft() {
        reconcileSelections()
        config = currentDraft().applied(to: config, availableConfigSets: aiConfig.allConfigSets)
    }

    private func scheduleDraftApply() {
        draftApplyTask?.cancel()
        draftApplyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            applyDraft()
        }
    }

    private func reconcileSelections() {
        let configSets = aiConfig.allConfigSets.filter(\.isConfigured)
        let fallbackId = configSets.first?.id

        if orchestratorConfigSetId == nil || aiConfig.configSet(for: orchestratorConfigSetId) == nil {
            let fallback = config.orchestrator.resolvedConfigSet(from: configSets)
                ?? configSets.first(where: { $0.provider == config.orchestrator.provider })
                ?? configSets.first
            orchestratorConfigSetId = fallback?.id ?? fallbackId
        } else if aiConfig.configSet(for: orchestratorConfigSetId)?.isConfigured == false {
            orchestratorConfigSetId = fallbackId
        }

        if routerConfigSetId == nil || aiConfig.configSet(for: routerConfigSetId) == nil {
            let fallback = resolvedRouterConfigSet(from: configSets)
            routerConfigSetId = fallback?.id
            if routerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                routerModel = fallback?.model ?? ""
            }
        } else if aiConfig.configSet(for: routerConfigSetId)?.isConfigured == false {
            let fallback = resolvedRouterConfigSet(from: configSets)
            routerConfigSetId = fallback?.id
            routerModel = fallback?.model ?? routerModel
        }

        workers = workers.map { worker in
            var updated = worker
            let fallback = worker.resolvedConfigSet(from: configSets)
                ?? configSets.first(where: { $0.provider == worker.provider })
                ?? configSets.first
            updated.applyConfigSet(fallback)
            return updated
        }
    }

    private func resolvedRouterConfigSet(from configSets: [ConfigSet]) -> ConfigSet? {
        if let routerConfigSetId,
           let exactConfig = configSets.first(where: { $0.id == routerConfigSetId }) {
            return exactConfig
        }

        let trimmedModel = routerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty,
           let modelMatch = configSets.first(where: {
               $0.model.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedModel
           }) {
            return modelMatch
        }

        return configSets.first
    }

    private var canEnable: Bool {
        aiConfig.hasAnyProvider
    }

    private var orchestratorRecoveryMessage: String? {
        switch launchContext {
        case .planningModel, .multiAgentOrchestratorModel:
            return launchContext?.detail
        default:
            return nil
        }
    }

    private var workersRecoveryMessage: String? {
        switch launchContext {
        case .multiAgentWorkerAssignment, .multiAgentWorkerModel:
            return launchContext?.detail
        default:
            return nil
        }
    }

    private var routerRecoveryMessage: String? {
        launchContext == .routerModel ? launchContext?.detail : nil
    }

    private var qwenRouterReadinessIssue: String? {
        RouterConfig.qwenReadinessIssue(baseUrl: qwenBaseUrl, model: qwenModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MultiAgentMetric(
                    title: "可用提供商",
                    value: "\(aiConfig.availableProviders.count)",
                    detail: availableProviderText,
                    icon: "server.rack",
                    tone: canEnable ? Theme.statusSuccess : Theme.statusWarning
                )
                MultiAgentMetric(
                    title: "工作模式",
                    value: "自动流水线",
                    detail: "由规划层按复杂度自动选择执行策略",
                    icon: "arrow.triangle.branch",
                    tone: Theme.accentPrimary
                )
                MultiAgentMetric(
                    title: "并行上限",
                    value: "\(maxParallel)",
                    detail: "\(workers.filter(\.isEnabled).count) 个启用的子 Agent",
                    icon: "arrow.triangle.branch",
                    tone: Theme.accentSecondary
                )
            }

            SettingsSection(title: "流水线配置", icon: "switch.2") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Router → Planner → Executor → Critic 四层流水线始终启用。简单任务由单 Agent 直接执行（带 Critic 重试），复杂任务自动拆分为 DAG 并行执行。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)

                    ProviderDependencyStrip(aiConfig: aiConfig)

                    if !canEnable {
                        InlineWarning(
                            text: "请先配置 Claude/OpenAI API Key，或填写自定义 OpenAI 兼容端点。"
                        )
                    }
                }
            }

            if canEnable {
                OrchestratorSection(
                    configSetId: $orchestratorConfigSetId,
                    prompt: $orchestratorPrompt,
                    aiConfig: aiConfig,
                    recoveryMessage: orchestratorRecoveryMessage,
                    onChange: applyDraft,
                    onPromptChange: scheduleDraftApply
                )

                WorkersSection(
                    workers: $workers,
                    maxParallel: $maxParallel,
                    aiConfig: aiConfig,
                    recoveryMessage: workersRecoveryMessage,
                    onAdd: { showingAddWorker = true },
                    onEdit: { editingWorker = $0 },
                    onDelete: { worker in
                        pendingDeleteWorker = worker
                    },
                    onChange: applyDraft
                )

                SettingsSection(title: "任务拆分策略", icon: "scissors") {
                    HStack(spacing: 10) {
                        ForEach(TaskSplitStrategy.allCases, id: \.self) { strategy in
                            StrategyButton(
                                strategy: strategy,
                                isSelected: taskStrategy == strategy
                            ) {
                                taskStrategy = strategy
                                applyDraft()
                            }
                        }
                    }
                }

                SettingsSection(title: "PEV 验证闭环", icon: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $enableCritic) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("启用 Critic 审查与自动重试")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text("Worker 执行失败后，Critic 模型会分析错误并给出修复建议，自动重试直到成功")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accentPrimary)
                        .onChange(of: enableCritic) { _, _ in applyDraft() }

                        if enableCritic {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("最大重试次数")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text("每个子任务失败后最多重试的次数")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textTertiary)
                                }

                                Picker("", selection: $maxRetries) {
                                    ForEach(0...5, id: \.self) { count in
                                        Text("\(count)").tag(count)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .onChange(of: maxRetries) { _, _ in applyDraft() }

                                Spacer()
                            }
                        }
                    }
                }

                SettingsSection(title: "路由配置", icon: "arrow.triangle.branch", recoveryMessage: routerRecoveryMessage) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $routerEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("启用路由配置")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text("使用配置的路由模型前置判断任务类型，拦截寒暄、分配单/多 Agent 模式，降低 API 成本")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accentPrimary)
                        .onChange(of: routerEnabled) { _, _ in applyDraft() }

                        if routerEnabled {
                            VStack(alignment: .leading, spacing: 10) {
                                // Qwen 专用路由优先级提示
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.accentSecondary)
                                    Text("支持两种路由模式：① 通用路由（使用已配置的模型端点）；② Qwen3.5-4B 专用路由（需单独部署 vLLM 服务）")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textTertiary)
                                }
                                .padding(8)
                                .background(Theme.accentSecondary.opacity(0.06))
                                .cornerRadius(Theme.radiusSM)

                                // 通用路由配置
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("通用路由配置")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Theme.textPrimary)
                                        if enableQwenRouter {
                                            Text("（已禁用，当前使用 Qwen 专用路由）")
                                                .font(.system(size: 10))
                                                .foregroundColor(Theme.statusWarning)
                                        }
                                    }

                                    let configSets = aiConfig.allConfigSets
                                    let readyConfigSets = configSets.filter(\.isConfigured)
                                    if configSets.isEmpty {
                                        HStack(spacing: 8) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.statusWarning)
                                            Text("暂无模型端点，请先在 AI 配置中添加")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.textTertiary)
                                        }
                                        .padding(8)
                                        .background(Theme.statusWarning.opacity(0.08))
                                        .cornerRadius(Theme.radiusSM)
                                    } else if readyConfigSets.isEmpty {
                                        HStack(spacing: 8) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.statusWarning)
                                            Text("当前模型端点都不可用，请先补全模型、端点或 API Key")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.textTertiary)
                                        }
                                        .padding(8)
                                        .background(Theme.statusWarning.opacity(0.08))
                                        .cornerRadius(Theme.radiusSM)
                                    } else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("模型端点")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(enableQwenRouter ? Theme.textTertiary.opacity(0.5) : Theme.textTertiary)
                                            ForEach(configSets) { cs in
                                                let isSelectedReadyRouterConfig = routerConfigSetId == cs.id && cs.isConfigured
                                                HStack(spacing: 8) {
                                                    Button {
                                                        if !enableQwenRouter && cs.isConfigured {
                                                            routerConfigSetId = cs.id
                                                            routerModel = cs.model
                                                            applyDraft()
                                                        }
                                                    } label: {
                                                        HStack(spacing: 8) {
                                                            Image(systemName: isSelectedReadyRouterConfig ? "circle.fill" : (cs.isConfigured ? "circle" : "exclamationmark.triangle.fill"))
                                                                .font(.system(size: 10))
                                                                .foregroundColor(isSelectedReadyRouterConfig ? Theme.accentPrimary : (cs.isConfigured ? Theme.textTertiary : Theme.statusWarning))
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                HStack(spacing: 6) {
                                                                    Text(cs.name)
                                                                        .font(.system(size: 12))
                                                                        .foregroundColor(Theme.textPrimary)
                                                                    Text(cs.model.isEmpty ? "未设置模型" : cs.model)
                                                                        .font(.system(size: 10, design: .monospaced))
                                                                        .foregroundColor(Theme.textTertiary)
                                                                        .lineLimit(1)
                                                                        .truncationMode(.middle)
                                                                }
                                                                if let readinessIssue = cs.readinessIssue {
                                                                    Text(readinessIssue)
                                                                        .font(.system(size: 10, weight: .medium))
                                                                        .foregroundColor(Theme.statusWarning)
                                                                        .lineLimit(1)
                                                                }
                                                            }
                                                        }
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 7)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .background(isSelectedReadyRouterConfig ? Theme.bgTertiary : Theme.bgInput)
                                                        .cornerRadius(Theme.radiusSM)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                                .stroke(isSelectedReadyRouterConfig ? Theme.accentPrimary.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .disabled(enableQwenRouter || !cs.isConfigured)
                                                    .opacity((enableQwenRouter || !cs.isConfigured) ? 0.5 : 1.0)
                                                    .help(cs.readinessIssue.map { "暂不可选：\($0)" } ?? "")
                                                }
                                            }
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 4) {
                                            Text("模型名称")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(enableQwenRouter ? Theme.textTertiary.opacity(0.5) : Theme.textTertiary)
                                            Text("（可选，自动从端点读取）")
                                                .font(.system(size: 10))
                                                .foregroundColor(Theme.textTertiary.opacity(0.7))
                                        }
                                        TextField("选择端点后自动填充，也可手动覆盖", text: $routerModel)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(Theme.textPrimary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Theme.bgInput)
                                            .cornerRadius(Theme.radiusMD)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: Theme.radiusMD)
                                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                                            )
                                            .disabled(enableQwenRouter)
                                            .opacity(enableQwenRouter ? 0.5 : 1.0)
                                            .onChange(of: routerModel) { _, _ in scheduleDraftApply() }
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("路由提示词")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(enableQwenRouter ? Theme.textTertiary.opacity(0.5) : Theme.textTertiary)
                                        TextEditor(text: $routerPrompt)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(Theme.textPrimary)
                                            .scrollContentBackground(.hidden)
                                            .frame(height: 100)
                                            .padding(8)
                                            .background(Theme.bgInput)
                                            .cornerRadius(Theme.radiusMD)
                                            .disabled(enableQwenRouter)
                                            .opacity(enableQwenRouter ? 0.5 : 1.0)
                                            .onChange(of: routerPrompt) { _, _ in scheduleDraftApply() }
                                    }
                                }


                                // Qwen3.5-4B 专用配置部分
                                Divider()
                                    .padding(.vertical, 8)

                                HStack {
                                    Text("Qwen3.5-4B 专用路由")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                }

                                Toggle(isOn: $enableQwenRouter) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("启用 Qwen3.5-4B 专用路由器")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)
                                        Text("使用 vLLM 部署的 Qwen3.5-4B 作为专用路由层，支持结构化 JSON 输出和多模态路由。启用后将覆盖上述通用路由配置。")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textTertiary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .tint(Theme.accentPrimary)
                                .onChange(of: enableQwenRouter) { _, _ in applyDraft() }
                                
                                if enableQwenRouter {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if let qwenRouterReadinessIssue {
                                            InlineWarning(text: "Qwen 专用路由暂不可用：\(qwenRouterReadinessIssue)。")
                                        }

                                        // vLLM 服务地址
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("vLLM 服务地址")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textTertiary)
                                            TextField("http://localhost:8000", text: $qwenBaseUrl)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(Theme.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(Theme.bgInput)
                                                .cornerRadius(Theme.radiusMD)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                                                        .stroke(Theme.borderSubtle, lineWidth: 1)
                                                )
                                                .onChange(of: qwenBaseUrl) { _, _ in scheduleDraftApply() }
                                        }
                                        
                                        // Qwen 模型名称
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("模型名称")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textTertiary)
                                            TextField("Qwen/Qwen3.5-4B", text: $qwenModel)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(Theme.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(Theme.bgInput)
                                                .cornerRadius(Theme.radiusMD)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                                                        .stroke(Theme.borderSubtle, lineWidth: 1)
                                                )
                                                .onChange(of: qwenModel) { _, _ in scheduleDraftApply() }
                                        }
                                        
                                        // 关闭思考模式开关
                                        Toggle(isOn: $disableThinking) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("关闭思考模式")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Theme.textPrimary)
                                                Text("路由任务不需要深度思考，关闭可大幅提升响应速度并节省 Token")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Theme.textTertiary)
                                            }
                                        }
                                        .toggleStyle(.switch)
                                        .tint(Theme.accentPrimary)
                                        .onChange(of: disableThinking) { _, _ in applyDraft() }
                                        
                                        // 采样参数配置
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("采样参数")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textTertiary)
                                            
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Temperature")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(Theme.textTertiary)
                                                    TextField("0.7", value: $qwenTemperature, format: .number)
                                                        .textFieldStyle(.plain)
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(Theme.textPrimary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(Theme.bgInput)
                                                        .cornerRadius(Theme.radiusSM)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                                .stroke(Theme.borderSubtle, lineWidth: 1)
                                                        )
                                                        .onChange(of: qwenTemperature) { _, _ in scheduleDraftApply() }
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Top P")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(Theme.textTertiary)
                                                    TextField("0.80", value: $qwenTopP, format: .number)
                                                        .textFieldStyle(.plain)
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(Theme.textPrimary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(Theme.bgInput)
                                                        .cornerRadius(Theme.radiusSM)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                                .stroke(Theme.borderSubtle, lineWidth: 1)
                                                        )
                                                        .onChange(of: qwenTopP) { _, _ in scheduleDraftApply() }
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Top K")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(Theme.textTertiary)
                                                    TextField("20", value: $qwenTopK, format: .number)
                                                        .textFieldStyle(.plain)
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(Theme.textPrimary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(Theme.bgInput)
                                                        .cornerRadius(Theme.radiusSM)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                                .stroke(Theme.borderSubtle, lineWidth: 1)
                                                        )
                                                        .onChange(of: qwenTopK) { _, _ in scheduleDraftApply() }
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Presence Penalty")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(Theme.textTertiary)
                                                    TextField("1.5", value: $qwenPresencePenalty, format: .number)
                                                        .textFieldStyle(.plain)
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(Theme.textPrimary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(Theme.bgInput)
                                                        .cornerRadius(Theme.radiusSM)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                                .stroke(Theme.borderSubtle, lineWidth: 1)
                                                        )
                                                        .onChange(of: qwenPresencePenalty) { _, _ in scheduleDraftApply() }
                                                }
                                            }
                                        }
                                        
                                        // 使用说明
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("部署说明")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textTertiary)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("1. 安装 vLLM: `uv pip install vllm --torch-backend=auto`")
                                                Text("2. 启动服务: `vllm serve Qwen/Qwen3.5-4B --port 8000 --max-model-len 262144 --enable-auto-tool-choice --tool-call-parser qwen3_coder`")
                                                Text("3. 路由层会自动关闭思考模式，使用 guided_json 约束输出格式")
                                                Text("4. 支持多模态路由：可直接传入图片进行视觉意图判断")
                                            }
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(Theme.textSecondary)
                                            .padding(8)
                                            .background(Theme.bgTertiary)
                                            .cornerRadius(Theme.radiusSM)
                                        }
                                    }
                                    .padding(.leading, 2)
                                }
                            }
                            .padding(.leading, 2)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddWorker) {
            AddWorkerSheet(aiConfig: aiConfig) { newWorker in
                workers.append(newWorker)
                applyDraft()
            }
        }
        .sheet(item: $editingWorker) { worker in
            EditWorkerSheet(worker: worker, aiConfig: aiConfig) { updated in
                if let index = workers.firstIndex(where: { $0.id == updated.id }) {
                    workers[index] = updated
                    applyDraft()
                }
            }
        }
        .alert("删除子 Agent？", isPresented: deleteWorkerConfirmationBinding) {
            Button("取消", role: .cancel) {
                pendingDeleteWorker = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDeleteWorker {
                    workers.removeAll { $0.id == pendingDeleteWorker.id }
                    applyDraft()
                }
                pendingDeleteWorker = nil
            }
        } message: {
            Text(deleteWorkerConfirmationMessage)
        }
        .onAppear {
            applyDraft()
        }
        .onChange(of: aiConfig.configSetRevision) { _, _ in
            applyDraft()
        }
        .onDisappear {
            draftApplyTask?.cancel()
            applyDraft()
        }
    }

    private var deleteWorkerConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteWorker != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteWorker = nil
                }
            }
        )
    }

    private var deleteWorkerConfirmationMessage: String {
        guard let pendingDeleteWorker else {
            return "这个操作无法撤销。"
        }
        return "将删除子 Agent「\(pendingDeleteWorker.name)」及其能力、模型端点和系统提示词配置。\n\n这个操作无法撤销。"
    }

    private var availableProviderText: String {
        let names = aiConfig.availableProviders.map(\.displayName)
        return names.isEmpty ? "没有可用模型来源" : names.joined(separator: " / ")
    }
}

struct MultiAgentMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tone: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(tone.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tone)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(Theme.textTertiary)
                    .help(detail)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct ProviderDependencyStrip: View {
    let aiConfig: AIConfigInfo

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                HStack(spacing: 6) {
                    Circle()
                        .fill(aiConfig.availableProviders.contains(provider) ? Theme.statusSuccess : Theme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(provider.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.bgInput)
                .cornerRadius(Theme.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            }
            Spacer()
        }
    }
}

struct InlineWarning: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.statusWarning)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(10)
        .background(Theme.statusWarning.opacity(0.08))
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(Theme.statusWarning.opacity(0.2), lineWidth: 1)
        )
    }
}

struct StrategyButton: View {
    let strategy: TaskSplitStrategy
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(strategy.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(strategy.description)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.bgTertiary : Theme.bgInput.opacity(0.7))
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(isSelected ? Theme.accentPrimary.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Orchestrator Section

struct OrchestratorSection: View {
    @Binding var configSetId: UUID?
    @Binding var prompt: String
    let aiConfig: AIConfigInfo
    let recoveryMessage: String?
    let onChange: () -> Void
    let onPromptChange: () -> Void

    var body: some View {
        SettingsSection(title: "编排器", icon: "brain.head.profile", recoveryMessage: recoveryMessage) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .fill(Theme.statusWarning.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.statusWarning)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("主 Agent 负责规划和汇总")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("建议使用更强的推理模型；子 Agent 可以使用更经济的模型")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                }

                Divider().overlay(Theme.borderSubtle)

                AgentConfigSetSelector(
                    title: "模型端点",
                    configSetId: $configSetId,
                    aiConfig: aiConfig,
                    onChange: onChange
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    TextEditor(text: $prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(8)
                        .background(Theme.bgInput)
                        .cornerRadius(Theme.radiusMD)
                        .onChange(of: prompt) { _, _ in onPromptChange() }
                }
            }
        }
    }
}

struct AgentConfigSetSelector: View {
    let title: String
    @Binding var configSetId: UUID?
    let aiConfig: AIConfigInfo
    let onChange: () -> Void

    private var configSets: [ConfigSet] {
        aiConfig.allConfigSets
    }

    private var readyConfigSets: [ConfigSet] {
        configSets.filter(\.isConfigured)
    }

    private var selectedConfigSet: ConfigSet? {
        aiConfig.configSet(for: configSetId)
    }

    private var selectedReadyConfigSet: ConfigSet? {
        selectedConfigSet.flatMap { $0.isConfigured ? $0 : nil }
    }

    private var selectedUnavailableReason: String? {
        guard let selectedConfigSet, !selectedConfigSet.isConfigured else { return nil }
        return selectedConfigSet.readinessIssue ?? "模型配置不可用"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textTertiary)

            if configSets.isEmpty {
                InlineWarning(text: "请先在 AI 配置里添加至少一个模型配置。")
            } else if readyConfigSets.isEmpty {
                InlineWarning(text: "当前模型配置都不可用，请先补全模型、端点或 API Key。")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(configSets) { configSet in
                        let isSelectedReadyConfigSet = configSetId == configSet.id && configSet.isConfigured
                        Button {
                            guard configSet.isConfigured else { return }
                            configSetId = configSet.id
                            onChange()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: iconName(for: configSet))
                                    .font(.system(size: 13))
                                    .foregroundColor(iconColor(for: configSet))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(configSet.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(configSet.name)
                                        Text(configSet.provider.displayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(Theme.textTertiary)
                                    }

                                    Text(configSet.model)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(configSet.model)

                                    if let readinessIssue = configSet.readinessIssue {
                                        Text(readinessIssue)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.statusWarning)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .help(readinessIssue)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelectedReadyConfigSet ? Theme.bgTertiary : Theme.bgInput)
                            .cornerRadius(Theme.radiusSM)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusSM)
                                    .stroke(isSelectedReadyConfigSet ? Theme.accentPrimary.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!configSet.isConfigured)
                        .opacity(configSet.isConfigured ? 1 : 0.68)
                        .help(configSet.readinessIssue.map { "暂不可选：\($0)" } ?? "")
                    }
                }
            }

            if let selectedReadyConfigSet {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accentSecondary)
                    Text("当前绑定: \(selectedReadyConfigSet.provider.displayName) · \(selectedReadyConfigSet.model)")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("当前绑定: \(selectedReadyConfigSet.provider.displayName) · \(selectedReadyConfigSet.model)")
                }
            } else if let selectedUnavailableReason {
                InlineWarning(text: "原绑定已失效：\(selectedUnavailableReason)。请选择一个可用模型端点。")
            }
        }
    }

    private func iconName(for configSet: ConfigSet) -> String {
        if configSetId == configSet.id && configSet.isConfigured { return "checkmark.circle.fill" }
        return configSet.isConfigured ? "circle" : "exclamationmark.triangle.fill"
    }

    private func iconColor(for configSet: ConfigSet) -> Color {
        if configSetId == configSet.id && configSet.isConfigured { return Theme.accentPrimary }
        return configSet.isConfigured ? Theme.textTertiary : Theme.statusWarning
    }
}

// MARK: - Model Selector

struct AgentModelSelector: View {
    let title: String
    let provider: AIProvider
    @Binding var model: String
    let aiConfig: AIConfigInfo
    let onChange: () -> Void

    private var suggestedModels: [ModelChoice] {
        var choices: [ModelChoice] = []
        
        // 获取当前提供商的所有配置集
        let configSets = aiConfig.configSets(for: provider)
        
        // 添加所有配置集中的模型
        for configSet in configSets {
            let modelName = configSet.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelName.isEmpty && !choices.contains(where: { $0.id == modelName }) {
                let label = configSet.name.isEmpty ? modelName : "\(configSet.name): \(modelName)"
                choices.append(ModelChoice(id: modelName, label: label))
            }
        }
        
        // 如果没有找到配置集，回退到当前配置
        if choices.isEmpty {
            let current = aiConfig.currentModel(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty {
                choices.append(ModelChoice(id: current, label: "当前配置: \(current)"))
            }
        }

        if provider != .openAICompatible {
            for info in ModelInfo.availableModels(for: provider) where !choices.contains(where: { $0.id == info.modelId }) {
                choices.append(ModelChoice(id: info.modelId, label: info.displayName))
            }
        }

        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textTertiary)

            HStack(spacing: 8) {
                if !suggestedModels.isEmpty {
                    Picker("", selection: Binding(
                        get: { suggestedModels.contains(where: { $0.id == model }) ? model : "" },
                        set: { selected in
                            guard !selected.isEmpty else { return }
                            model = selected
                            onChange()
                        }
                    )) {
                        if !suggestedModels.contains(where: { $0.id == model }), !model.isEmpty {
                            let shortName = model.count > 20 ? String(model.prefix(20)) + "…" : model
                            Text("自定义: \(shortName)").tag("")
                        }
                        ForEach(suggestedModels) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                TextField("输入模型 ID", text: $model)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.bgInput)
                    .cornerRadius(Theme.radiusMD)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                    .onChange(of: model) { _, _ in onChange() }
            }
        }
    }
}

private struct ModelChoice: Identifiable {
    let id: String
    let label: String
}

// MARK: - Provider Chip

struct DarkProviderChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Text(name)
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.bgTertiary)
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(isSelected ? Theme.accentPrimary : Theme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct ProviderChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        DarkProviderChip(name: name, isSelected: isSelected, action: action)
    }
}

// MARK: - Workers Section

struct WorkersSection: View {
    @Binding var workers: [AgentConfig]
    @Binding var maxParallel: Int
    let aiConfig: AIConfigInfo
    let recoveryMessage: String?
    let onAdd: () -> Void
    let onEdit: (AgentConfig) -> Void
    let onDelete: (AgentConfig) -> Void
    let onChange: () -> Void

    var body: some View {
        SettingsSection(title: "子 Agent 池", icon: "person.2.fill", recoveryMessage: recoveryMessage) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("并行执行上限")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("控制同时启动的子 Agent 数量")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Picker("", selection: $maxParallel) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .onChange(of: maxParallel) { _, _ in onChange() }

                    Spacer()

                    Button(action: onAdd) {
                        Label("添加子 Agent", systemImage: "plus.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accentPrimary)
                }

                if workers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.textTertiary)
                            Text("暂无子 Agent")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 22)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(workers) { worker in
                            DarkWorkerRow(
                                worker: worker,
                                onEdit: { onEdit(worker) },
                                onDelete: { onDelete(worker) }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct DarkWorkerRow: View {
    let worker: AgentConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(Theme.accentSecondary.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: workerIcon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accentSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(worker.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text(worker.provider.displayName)
                    Text("·")
                    Text(worker.capability.displayName)
                    Text("·")
                    Text(modelShortName(worker.model))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.accentSecondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.statusError)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.bgTertiary)
        .cornerRadius(Theme.radiusMD)
    }

    private var workerIcon: String {
        if worker.name.contains("搜索") { return "magnifyingglass" }
        if worker.name.contains("代码") { return "chevron.left.forwardslash.chevron.right" }
        if worker.name.contains("文件") { return "doc.text" }
        return "person.fill"
    }

    private func modelShortName(_ model: String) -> String {
        if model.contains("haiku") { return "Haiku" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("opus") { return "Opus" }
        if model.contains("4o-mini") { return "4o Mini" }
        if model.contains("4o") { return "4o" }
        if model.contains("turbo") { return "Turbo" }
        return model
    }
}

struct WorkerRow: View {
    let worker: AgentConfig
    let onEdit: () -> Void
    let onDelete: () -> Void
    var body: some View {
        DarkWorkerRow(worker: worker, onEdit: onEdit, onDelete: onDelete)
    }
}

// MARK: - Add Worker Sheet

struct AddWorkerSheet: View {
    @Environment(\.dismiss) var dismiss
    let aiConfig: AIConfigInfo
    let onAdd: (AgentConfig) -> Void

    @State private var name = ""
    @State private var configSetId: UUID?
    @State private var capability: AgentCapability = .general
    @State private var systemPrompt = ""

    private var readyConfigSets: [ConfigSet] {
        aiConfig.allConfigSets.filter(\.isConfigured)
    }

    private var selectedReadyConfigSet: ConfigSet? {
        aiConfig.configSet(for: configSetId).flatMap { $0.isConfigured ? $0 : nil }
            ?? readyConfigSets.first
    }

    private var saveDisabledReason: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写子 Agent 名称"
        }
        if selectedReadyConfigSet == nil {
            return "请先选择一个可用的模型端点"
        }
        return nil
    }

    init(aiConfig: AIConfigInfo, onAdd: @escaping (AgentConfig) -> Void) {
        self.aiConfig = aiConfig
        self.onAdd = onAdd
        self._configSetId = State(initialValue: aiConfig.allConfigSets.first(where: { $0.isConfigured })?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加子 Agent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(16)

            Divider().overlay(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("名称").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    TextField("例如: 搜索 Agent", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                        .padding(8)
                        .background(Theme.bgInput)
                        .cornerRadius(Theme.radiusMD)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("能力").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    Picker("", selection: $capability) {
                        ForEach(AgentCapability.allCases, id: \.self) { capability in
                            Text("\(capability.displayName) - \(capability.description)").tag(capability)
                        }
                    }
                    .pickerStyle(.menu)
                }

                AgentConfigSetSelector(
                    title: "模型端点",
                    configSetId: $configSetId,
                    aiConfig: aiConfig,
                    onChange: {}
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    TextEditor(text: $systemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(8)
                        .background(Theme.bgInput)
                        .cornerRadius(Theme.radiusMD)
                }
            }
            .padding(16)

            Divider().overlay(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("添加") {
                    guard let selectedConfigSet = selectedReadyConfigSet else { return }
                    let worker = AgentConfig(
                        name: name.isEmpty ? "子 Agent" : name,
                        role: .worker,
                        capability: capability,
                        configSetId: selectedConfigSet.id,
                        provider: selectedConfigSet.provider,
                        model: selectedConfigSet.model,
                        systemPrompt: systemPrompt
                    )
                    onAdd(worker)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
                .disabled(saveDisabledReason != nil)
                .help(saveDisabledReason ?? "添加子 Agent")
            }
            .padding(16)
        }
        .frame(width: 500, height: 480)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Edit Worker Sheet

struct EditWorkerSheet: View {
    @Environment(\.dismiss) var dismiss
    let worker: AgentConfig
    let aiConfig: AIConfigInfo
    let onSave: (AgentConfig) -> Void

    @State private var name: String
    @State private var configSetId: UUID?
    @State private var capability: AgentCapability
    @State private var systemPrompt: String

    private var readyConfigSets: [ConfigSet] {
        aiConfig.allConfigSets.filter(\.isConfigured)
    }

    private var selectedReadyConfigSet: ConfigSet? {
        aiConfig.configSet(for: configSetId).flatMap { $0.isConfigured ? $0 : nil }
            ?? readyConfigSets.first
    }

    private var saveDisabledReason: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写子 Agent 名称"
        }
        if selectedReadyConfigSet == nil {
            return "请先选择一个可用的模型端点"
        }
        return nil
    }

    init(worker: AgentConfig, aiConfig: AIConfigInfo, onSave: @escaping (AgentConfig) -> Void) {
        self.worker = worker
        self.aiConfig = aiConfig
        self.onSave = onSave
        self._name = State(initialValue: worker.name)
        let readyConfigSets = aiConfig.allConfigSets.filter(\.isConfigured)
        let resolvedConfigSet = worker.resolvedConfigSet(from: readyConfigSets) ?? readyConfigSets.first
        self._configSetId = State(initialValue: resolvedConfigSet?.id)
        self._capability = State(initialValue: worker.capability)
        self._systemPrompt = State(initialValue: worker.systemPrompt)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑子 Agent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(16)

            Divider().overlay(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("名称").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                        .padding(8)
                        .background(Theme.bgInput)
                        .cornerRadius(Theme.radiusMD)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("能力").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    Picker("", selection: $capability) {
                        ForEach(AgentCapability.allCases, id: \.self) { capability in
                            Text("\(capability.displayName) - \(capability.description)").tag(capability)
                        }
                    }
                    .pickerStyle(.menu)
                }

                AgentConfigSetSelector(
                    title: "模型端点",
                    configSetId: $configSetId,
                    aiConfig: aiConfig,
                    onChange: {}
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    TextEditor(text: $systemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(8)
                        .background(Theme.bgInput)
                        .cornerRadius(Theme.radiusMD)
                }
            }
            .padding(16)

            Divider().overlay(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("保存") {
                    guard let selectedConfigSet = selectedReadyConfigSet else { return }
                    var updated = worker
                    updated.name = name
                    updated.applyConfigSet(selectedConfigSet)
                    updated.capability = capability
                    updated.systemPrompt = systemPrompt
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
                .disabled(saveDisabledReason != nil)
                .help(saveDisabledReason ?? "保存子 Agent")
            }
            .padding(16)
        }
        .frame(width: 500, height: 480)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }
}
