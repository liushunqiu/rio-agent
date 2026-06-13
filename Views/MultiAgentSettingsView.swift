import SwiftUI

struct MultiAgentSettingsView: View {
    @Binding var config: MultiAgentConfig
    let aiConfig: AIConfigInfo

    @State private var isEnabled: Bool
    @State private var orchestratorProvider: AIProvider
    @State private var orchestratorModel: String
    @State private var orchestratorPrompt: String
    @State private var workers: [AgentConfig]
    @State private var maxParallel: Int
    @State private var taskStrategy: TaskSplitStrategy
    @State private var showingAddWorker = false
    @State private var editingWorker: AgentConfig?

    init(config: Binding<MultiAgentConfig>, aiConfig: AIConfigInfo) {
        self._config = config
        self.aiConfig = aiConfig
        let initial = config.wrappedValue
        let hasAnyKey = aiConfig.hasClaudeKey || aiConfig.hasOpenAIKey

        self._isEnabled = State(initialValue: initial.isEnabled && hasAnyKey)
        let validProvider = aiConfig.availableProviders.contains(initial.orchestrator.provider)
            ? initial.orchestrator.provider
            : aiConfig.availableProviders.first ?? .claude

        self._orchestratorProvider = State(initialValue: validProvider)
        self._orchestratorModel = State(initialValue: initial.orchestrator.model)
        self._orchestratorPrompt = State(initialValue: initial.orchestrator.systemPrompt)
        self._workers = State(initialValue: initial.workers)
        self._maxParallel = State(initialValue: initial.maxParallelWorkers)
        self._taskStrategy = State(initialValue: initial.taskSplitStrategy)
    }

    private func syncToConfig() {
        config.isEnabled = isEnabled
        config.orchestrator.provider = orchestratorProvider
        config.orchestrator.model = orchestratorModel
        config.orchestrator.systemPrompt = orchestratorPrompt
        config.workers = workers
        config.maxParallelWorkers = maxParallel
        config.taskSplitStrategy = taskStrategy
    }

    private var canEnable: Bool {
        aiConfig.hasClaudeKey || aiConfig.hasOpenAIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !canEnable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.statusWarning)
                        .font(.system(size: 13))
                    Text("请先在 AI 配置页面配置至少一个 API Key")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.statusWarning.opacity(0.08))
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.statusWarning.opacity(0.2), lineWidth: 1)
                )
            }

            SettingsSection(title: "Multi-Agent 模式", icon: "person.3.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $isEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("启用 Multi-Agent")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("将复杂任务拆分给多个 Agent 并行处理")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accentPrimary)
                    .disabled(!canEnable)
                    .onChange(of: isEnabled) { _, _ in syncToConfig() }

                    if isEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text("主 Agent 使用强模型，子 Agent 使用经济模型")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Theme.textTertiary)
                    }
                }
            }

            if isEnabled && canEnable {
                OrchestratorSection(
                    provider: $orchestratorProvider,
                    model: $orchestratorModel,
                    prompt: $orchestratorPrompt,
                    aiConfig: aiConfig,
                    onChange: syncToConfig
                )

                WorkersSection(
                    workers: $workers,
                    maxParallel: $maxParallel,
                    aiConfig: aiConfig,
                    onAdd: { showingAddWorker = true },
                    onEdit: { editingWorker = $0 },
                    onDelete: { worker in
                        workers.removeAll { $0.id == worker.id }
                        syncToConfig()
                    },
                    onChange: syncToConfig
                )

                SettingsSection(title: "任务拆分策略", icon: "scissors") {
                    Picker("", selection: $taskStrategy) {
                        ForEach(TaskSplitStrategy.allCases, id: \.self) { strategy in
                            VStack(alignment: .leading) {
                                Text(strategy.displayName)
                                Text(strategy.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(strategy)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: taskStrategy) { _, _ in syncToConfig() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .sheet(isPresented: $showingAddWorker) {
            AddWorkerSheet(aiConfig: aiConfig) { newWorker in
                workers.append(newWorker)
                syncToConfig()
            }
        }
        .sheet(item: $editingWorker) { worker in
            EditWorkerSheet(worker: worker, aiConfig: aiConfig) { updated in
                if let index = workers.firstIndex(where: { $0.id == updated.id }) {
                    workers[index] = updated
                    syncToConfig()
                }
            }
        }
    }
}

// MARK: - Orchestrator Section

struct OrchestratorSection: View {
    @Binding var provider: AIProvider
    @Binding var model: String
    @Binding var prompt: String
    let aiConfig: AIConfigInfo
    let onChange: () -> Void

    private var availableModels: [(String, String, String)] {
        switch provider {
        case .claude:
            return [
                ("claude-opus-4-20250514", "Claude Opus 4", "star.fill"),
                ("claude-sonnet-4-20250514", "Claude Sonnet 4", "bolt.fill"),
                ("claude-3-5-haiku-20241022", "Claude Haiku 3.5", "hare.fill")
            ]
        case .openAI, .openAICompatible:
            return [
                ("gpt-4o", "GPT-4o", "star.fill"),
                ("gpt-4-turbo", "GPT-4 Turbo", "brain.head.profile"),
                ("gpt-4o-mini", "GPT-4o Mini", "bolt.fill")
            ]
        }
    }

    var body: some View {
        SettingsSection(title: "主 Agent (Orchestrator)", icon: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.statusWarning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("主 Agent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("负责任务拆分、汇总结果（建议使用强模型）")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                }

                Divider().overlay(Theme.borderSubtle)

                if aiConfig.availableProviders.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提供商")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                        HStack(spacing: 8) {
                            ForEach(aiConfig.availableProviders, id: \.self) { p in
                                DarkProviderChip(
                                    name: p.displayName,
                                    isSelected: provider == p
                                ) {
                                    provider = p
                                    model = p == .claude ? "claude-sonnet-4-20250514" : "gpt-4o"
                                    onChange()
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    Picker("", selection: $model) {
                        ForEach(availableModels, id: \.0) { modelId, modelName, icon in
                            Label(modelName, systemImage: icon).tag(modelId)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model) { _, _ in onChange() }
                }

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
                        .onChange(of: prompt) { _, _ in onChange() }
                }
            }
        }
    }
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
    let onAdd: () -> Void
    let onEdit: (AgentConfig) -> Void
    let onDelete: (AgentConfig) -> Void
    let onChange: () -> Void

    var body: some View {
        SettingsSection(title: "子 Agents (Workers)", icon: "person.2.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最大并行数")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)

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
                        Label("添加", systemImage: "plus.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accentPrimary)
                }

                if workers.isEmpty {
                    HStack {
                        Spacer()
                        Text("暂无子 Agent")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
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
    @State private var provider: AIProvider
    @State private var model: String
    @State private var systemPrompt = ""

    init(aiConfig: AIConfigInfo, onAdd: @escaping (AgentConfig) -> Void) {
        self.aiConfig = aiConfig
        self.onAdd = onAdd
        let defaultProvider = aiConfig.availableProviders.first ?? .claude
        self._provider = State(initialValue: defaultProvider)
        self._model = State(initialValue: defaultProvider == .claude ? "claude-3-5-haiku-20241022" : "gpt-4o-mini")
    }

    private var availableModels: [(String, String)] {
        switch provider {
        case .claude:
            return [("claude-3-5-haiku-20241022", "Claude Haiku 3.5 (推荐)"), ("claude-sonnet-4-20250514", "Claude Sonnet 4")]
        case .openAI, .openAICompatible:
            return [("gpt-4o-mini", "GPT-4o Mini (推荐)"), ("gpt-4o", "GPT-4o")]
        }
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

                if aiConfig.availableProviders.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提供商").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(aiConfig.availableProviders, id: \.self) { p in
                                DarkProviderChip(name: p.displayName, isSelected: provider == p) {
                                    provider = p
                                    model = p == .claude ? "claude-3-5-haiku-20241022" : "gpt-4o-mini"
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型 (建议使用经济模型)").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    Picker("", selection: $model) {
                        ForEach(availableModels, id: \.0) { modelId, modelName in
                            Text(modelName).tag(modelId)
                        }
                    }
                    .pickerStyle(.menu)
                }

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
                    let worker = AgentConfig(
                        name: name.isEmpty ? "子 Agent" : name,
                        role: .worker,
                        provider: provider,
                        model: model,
                        systemPrompt: systemPrompt
                    )
                    onAdd(worker)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
                .disabled(name.isEmpty)
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
    @State private var provider: AIProvider
    @State private var model: String
    @State private var systemPrompt: String

    init(worker: AgentConfig, aiConfig: AIConfigInfo, onSave: @escaping (AgentConfig) -> Void) {
        self.worker = worker
        self.aiConfig = aiConfig
        self.onSave = onSave
        self._name = State(initialValue: worker.name)
        self._provider = State(initialValue: worker.provider)
        self._model = State(initialValue: worker.model)
        self._systemPrompt = State(initialValue: worker.systemPrompt)
    }

    private var availableModels: [(String, String)] {
        switch provider {
        case .claude:
            return [("claude-3-5-haiku-20241022", "Claude Haiku 3.5"), ("claude-sonnet-4-20250514", "Claude Sonnet 4")]
        case .openAI, .openAICompatible:
            return [("gpt-4o-mini", "GPT-4o Mini"), ("gpt-4o", "GPT-4o")]
        }
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

                if aiConfig.availableProviders.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提供商").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(aiConfig.availableProviders, id: \.self) { p in
                                DarkProviderChip(name: p.displayName, isSelected: provider == p) {
                                    provider = p
                                    model = p == .claude ? "claude-3-5-haiku-20241022" : "gpt-4o-mini"
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                    Picker("", selection: $model) {
                        ForEach(availableModels, id: \.0) { modelId, modelName in
                            Text(modelName).tag(modelId)
                        }
                    }
                    .pickerStyle(.menu)
                }

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
                    var updated = worker
                    updated.name = name
                    updated.provider = provider
                    updated.model = model
                    updated.systemPrompt = systemPrompt
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
            }
            .padding(16)
        }
        .frame(width: 500, height: 480)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }
}
