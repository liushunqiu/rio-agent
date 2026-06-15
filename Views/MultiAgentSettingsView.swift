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
        let canUseMultiAgent = aiConfig.hasAnyProvider

        self._isEnabled = State(initialValue: initial.isEnabled && canUseMultiAgent)
        let validProvider = aiConfig.availableProviders.contains(initial.orchestrator.provider)
            ? initial.orchestrator.provider
            : aiConfig.availableProviders.first ?? .claude

        self._orchestratorProvider = State(initialValue: validProvider)
        let initialOrchestratorModel = initial.orchestrator.provider == validProvider
            ? initial.orchestrator.model
            : aiConfig.currentModel(for: validProvider)
        self._orchestratorModel = State(initialValue: initialOrchestratorModel)
        self._orchestratorPrompt = State(initialValue: initial.orchestrator.systemPrompt)
        self._workers = State(initialValue: initial.workers.map { worker in
            guard aiConfig.availableProviders.contains(worker.provider) else {
                var updated = worker
                updated.provider = validProvider
                updated.model = aiConfig.currentModel(for: validProvider)
                return updated
            }
            return worker
        })
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
        aiConfig.hasAnyProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !canEnable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.statusWarning)
                        .font(.system(size: 13))
                    Text("请先在 AI 配置页面配置 Claude/OpenAI API Key，或配置自定义端点")
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
                                    model = aiConfig.currentModel(for: p)
                                    onChange()
                                }
                            }
                        }
                    }
                }

                AgentModelSelector(
                    title: "模型",
                    provider: provider,
                    model: $model,
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
                        .onChange(of: prompt) { _, _ in onChange() }
                }
            }
        }
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
        let current = aiConfig.currentModel(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)

        if !current.isEmpty {
            choices.append(ModelChoice(id: current, label: "当前配置: \(current)"))
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
                        if !suggestedModels.contains(where: { $0.id == model }) {
                            Text("自定义").tag("")
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
    @State private var provider: AIProvider
    @State private var model: String
    @State private var capability: AgentCapability = .general
    @State private var systemPrompt = ""

    init(aiConfig: AIConfigInfo, onAdd: @escaping (AgentConfig) -> Void) {
        self.aiConfig = aiConfig
        self.onAdd = onAdd
        let defaultProvider = aiConfig.availableProviders.first ?? .claude
        self._provider = State(initialValue: defaultProvider)
        self._model = State(initialValue: aiConfig.currentModel(for: defaultProvider))
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
                                    model = aiConfig.currentModel(for: p)
                                }
                            }
                        }
                    }
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

                AgentModelSelector(
                    title: "模型",
                    provider: provider,
                    model: $model,
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
                    let worker = AgentConfig(
                        name: name.isEmpty ? "子 Agent" : name,
                        role: .worker,
                        capability: capability,
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
    @State private var capability: AgentCapability
    @State private var systemPrompt: String

    init(worker: AgentConfig, aiConfig: AIConfigInfo, onSave: @escaping (AgentConfig) -> Void) {
        self.worker = worker
        self.aiConfig = aiConfig
        self.onSave = onSave
        let validProvider = aiConfig.availableProviders.contains(worker.provider)
            ? worker.provider
            : aiConfig.availableProviders.first ?? .claude
        self._name = State(initialValue: worker.name)
        self._provider = State(initialValue: validProvider)
        self._model = State(initialValue: worker.provider == validProvider ? worker.model : aiConfig.currentModel(for: validProvider))
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

                if aiConfig.availableProviders.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提供商").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(aiConfig.availableProviders, id: \.self) { p in
                                DarkProviderChip(name: p.displayName, isSelected: provider == p) {
                                    provider = p
                                    model = aiConfig.currentModel(for: p)
                                }
                            }
                        }
                    }
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

                AgentModelSelector(
                    title: "模型",
                    provider: provider,
                    model: $model,
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
                    var updated = worker
                    updated.name = name
                    updated.provider = provider
                    updated.model = model
                    updated.capability = capability
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
