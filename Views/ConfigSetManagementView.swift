import SwiftUI

// MARK: - Config Set Management View

struct ConfigSetManagementView: View {
    @ObservedObject var manager: ConfigSetManager
    @State private var editingConfigSet: ConfigSet?
    @State private var isAddingNew = false
    @State private var pendingDeleteConfigSet: ConfigSet?
    @State private var configurationErrorMessage: String?

    private var configuredCount: Int {
        manager.configSets.filter { $0.isConfigured }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模型配置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("已配置 \(configuredCount) / \(manager.configSets.count) 个端点")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
                
                Spacer()
                
                Button {
                    isAddingNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加模型")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accentPrimary)
            }
            
            if manager.configSets.isEmpty {
                emptyStateView
            } else {
                configSetList
            }
        }
        .sheet(isPresented: $isAddingNew) {
            ConfigSetEditorView(configSet: nil) { newSet in
                try manager.addConfigSet(newSet)
            }
        }
        .sheet(item: $editingConfigSet) { configSet in
            ConfigSetEditorView(configSet: configSet) { updated in
                try manager.updateConfigSet(updated)
            }
        }
        .alert("删除模型配置？", isPresented: deleteConfirmationBinding) {
            Button("取消", role: .cancel) {
                pendingDeleteConfigSet = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDeleteConfigSet {
                    do {
                        try manager.deleteConfigSet(id: pendingDeleteConfigSet.id)
                    } catch {
                        configurationErrorMessage = storageErrorMessage(error)
                    }
                }
                pendingDeleteConfigSet = nil
            }
        } message: {
            Text("删除后会同时移除该配置保存的 API Key，并解除所有引用它的选择。")
        }
        .alert("模型配置操作失败", isPresented: configurationErrorBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(configurationErrorMessage ?? "安全存储暂时不可用，请稍后重试。")
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteConfigSet != nil },
            set: { if !$0 { pendingDeleteConfigSet = nil } }
        )
    }

    private var configurationErrorBinding: Binding<Bool> {
        Binding(
            get: { configurationErrorMessage != nil },
            set: { if !$0 { configurationErrorMessage = nil } }
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28))
                .foregroundColor(Theme.textTertiary)
            
            Text("暂无模型配置")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            
            Text("点击「添加模型」来配置你的第一个 AI 模型")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.bgTertiary)
        .cornerRadius(Theme.radiusMD)
    }
    
    private var configSetList: some View {
        VStack(spacing: 6) {
            ForEach(manager.configSets) { configSet in
                configSetRow(configSet)
            }
        }
    }
    
    private func configSetRow(_ configSet: ConfigSet) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(Theme.bgTertiary)
                    .frame(width: 32, height: 32)
                Image(systemName: configSet.provider.icon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accentPrimary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(configSet.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(configSet.name)
                
                HStack(spacing: 6) {
                    Text(configSet.provider.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                    
                    if !configSet.model.isEmpty {
                        Text(configSet.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(configSet.model)
                    }
                }

                if let readinessHint = readinessHint(for: configSet) {
                    Text(readinessHint)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(readinessHint)
                }
            }
            
            Spacer()
            
            Circle()
                .fill(configSet.isConfigured ? Theme.statusSuccess : Theme.textTertiary)
                .frame(width: 6, height: 6)
            
            Text(configSet.isConfigured ? "可用" : "待配置")
                .font(.system(size: 10))
                .foregroundColor(configSet.isConfigured ? Theme.statusSuccess : Theme.textTertiary)
            
            Button {
                editingConfigSet = configSet
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            
            if canDeleteConfigSet(configSet) {
                Button {
                    pendingDeleteConfigSet = configSet
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.statusError.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("删除模型配置")
            } else {
                Image(systemName: "lock.circle")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textTertiary.opacity(0.65))
                    .help(deleteDisabledReason(for: configSet))
            }
        }
        .padding(10)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func readinessHint(for configSet: ConfigSet) -> String? {
        configSet.readinessIssue
    }

    private func canDeleteConfigSet(_ configSet: ConfigSet) -> Bool {
        guard manager.configSets.count > 1 else { return false }
        return !configSet.isConfigured || configuredCount > 1
    }

    private func deleteDisabledReason(for configSet: ConfigSet) -> String {
        if configSet.isConfigured && configuredCount <= 1 {
            return "至少保留一个可用模型配置；如需替换，请先添加并保存新的可用配置。"
        }
        return "至少保留一个模型配置，避免设置页失去可选项。"
    }

    private func storageErrorMessage(_ error: Error) -> String {
        "模型配置无法保存，或 API Key 无法写入/移除安全存储：\(error.localizedDescription)"
    }
}

// MARK: - Config Set Editor View

struct ConfigSetEditorView: View {
    @Environment(\.dismiss) var dismiss
    let configSet: ConfigSet?
    var onSave: (ConfigSet) throws -> Void
    
    @State private var name: String
    @State private var provider: AIProvider
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var showingDiscardConfirmation = false
    @State private var saveErrorMessage: String?

    private let originalName: String
    private let originalProvider: AIProvider
    private let originalBaseURL: String
    private let originalAPIKey: String
    private let originalModel: String
    
    init(configSet: ConfigSet?, onSave: @escaping (ConfigSet) throws -> Void) {
        self.configSet = configSet
        self.onSave = onSave

        let initialName = configSet?.name ?? ""
        let initialProvider = configSet?.provider ?? .openAICompatible
        let initialBaseURL = configSet?.baseURL ?? ""
        let initialAPIKey = configSet?.loadAPIKey() ?? ""
        let initialModel = configSet?.model ?? ""

        self.originalName = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalProvider = initialProvider
        self.originalBaseURL = initialBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalAPIKey = initialAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalModel = initialModel.trimmingCharacters(in: .whitespacesAndNewlines)

        _name = State(initialValue: initialName)
        _provider = State(initialValue: initialProvider)
        _baseURL = State(initialValue: initialBaseURL)
        _apiKey = State(initialValue: initialAPIKey)
        _model = State(initialValue: initialModel)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(configSet == nil ? "添加模型" : "编辑模型")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(canSave ? Theme.statusSuccess : Theme.statusWarning)
                                .frame(width: 6, height: 6)
                            Text(canSave ? "当前配置填写完整，保存后可立即使用" : readinessMessage)
                                .font(.system(size: 11))
                                .foregroundColor(canSave ? Theme.statusSuccess : Theme.textSecondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((canSave ? Theme.statusSuccess : Theme.statusWarning).opacity(0.08))
                        .cornerRadius(Theme.radiusMD)
                    }

                    // 名称
                    fieldGroup(label: "模型名称") {
                        TextField("例如: GPT-4o, Claude Sonnet", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.bgInput)
                            .cornerRadius(Theme.radiusMD)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMD)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            )
                    }
                    
                    // Provider 类型
                    fieldGroup(label: "提供商") {
                        Picker("", selection: $provider) {
                            ForEach(AIProvider.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    
                    // API 端点
                    fieldGroup(label: "API 端点") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(placeholderURL, text: $baseURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Theme.bgInput)
                                .cornerRadius(Theme.radiusMD)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                                        .stroke(Theme.borderSubtle, lineWidth: 1)
                                )

                            Text(endpointHelpText)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // API Key
                    fieldGroup(label: "API Key") {
                        SecureField("输入 API Key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.bgInput)
                            .cornerRadius(Theme.radiusMD)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMD)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            )
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(apiKeyStatusColor)
                                .frame(width: 5, height: 5)
                            Text(apiKeyStatusText)
                                .font(.system(size: 10))
                                .foregroundColor(apiKeyStatusColor)
                        }
                        .help(apiKeyStatusHelp)
                    }
                    
                    // 模型名称
                    fieldGroup(label: "模型标识") {
                        TextField(placeholderModel, text: $model)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.bgInput)
                            .cornerRadius(Theme.radiusMD)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMD)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("取消") {
                    requestDismiss()
                }
                .buttonStyle(.bordered)
                .help(hasUnsavedChanges ? "有未保存更改，取消前需要确认" : "关闭编辑器")
                
                Spacer()
                
                Button("保存") {
                    if save() {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
                .disabled(!canSave)
                .help(canSave ? "保存模型配置" : readinessMessage)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .alert("放弃未保存的模型配置？", isPresented: $showingDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃更改", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("当前模型配置还有未保存更改，关闭后这些修改不会保存。")
        }
        .alert("保存模型配置失败", isPresented: saveErrorBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "安全存储暂时不可用，请稍后重试。")
        }
    }
    
    private var placeholderURL: String {
        switch provider {
        case .claude: return AIProvider.claude.defaultBaseURL ?? "https://api.anthropic.com"
        case .openAI: return AIProvider.openAI.defaultBaseURL ?? "https://api.openai.com"
        case .openAICompatible: return "https://your-endpoint.com/v1"
        }
    }

    private var endpointHelpText: String {
        switch provider {
        case .claude, .openAI:
            return "留空使用官方默认端点：\(provider.resolvedBaseURL(""))"
        case .openAICompatible:
            return "自定义 OpenAI 兼容端点必填，例如本地 vLLM、Ollama 网关或第三方聚合服务。"
        }
    }
    
    private var placeholderModel: String {
        switch provider {
        case .claude: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        case .openAICompatible: return "your-model-name"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedChanges: Bool {
        trimmedName != originalName ||
            provider != originalProvider ||
            trimmedBaseURL != originalBaseURL ||
            trimmedAPIKey != originalAPIKey ||
            trimmedModel != originalModel
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && isConfigurationComplete
    }

    private var isConfigurationComplete: Bool {
        switch provider {
        case .claude, .openAI:
            return !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty
        case .openAICompatible:
            return !trimmedBaseURL.isEmpty && !trimmedModel.isEmpty
        }
    }

    private var readinessMessage: String {
        var missingFields: [String] = []
        if trimmedName.isEmpty {
            missingFields.append("模型名称")
        }

        switch provider {
        case .claude, .openAI:
            if trimmedAPIKey.isEmpty {
                missingFields.append("API Key")
            }
        case .openAICompatible:
            if trimmedBaseURL.isEmpty {
                missingFields.append("API 端点")
            }
        }

        if trimmedModel.isEmpty {
            missingFields.append("模型标识")
        }

        guard !missingFields.isEmpty else {
            return "当前配置填写完整，保存后可立即使用"
        }

        return "还需要填写：" + missingFields.joined(separator: "、")
    }

    private var apiKeyStatusText: String {
        if !trimmedAPIKey.isEmpty {
            return "已配置"
        }
        switch provider {
        case .openAICompatible:
            return "可选"
        case .claude, .openAI:
            return "未配置"
        }
    }

    private var apiKeyStatusColor: Color {
        if !trimmedAPIKey.isEmpty {
            return Theme.statusSuccess
        }
        switch provider {
        case .openAICompatible:
            return Theme.textTertiary
        case .claude, .openAI:
            return Theme.statusError
        }
    }

    private var apiKeyStatusHelp: String {
        switch provider {
        case .openAICompatible:
            return "OpenAI Compatible 端点可按服务需要选择是否填写 API Key。"
        case .claude, .openAI:
            return "该提供商需要 API Key 才能保存为可用配置。"
        }
    }
    
    @ViewBuilder
    private func fieldGroup(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            content()
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }
    
    private func save() -> Bool {
        let id = configSet?.id ?? UUID()
        let newSet = ConfigSet(
            id: id,
            name: trimmedName,
            provider: provider,
            baseURL: trimmedBaseURL,
            model: trimmedModel
        )

        do {
            try newSet.saveAPIKey(trimmedAPIKey)
            try onSave(newSet)
        } catch {
            saveErrorMessage = "模型配置或 API Key 无法保存：\(error.localizedDescription)"
            return false
        }

        return true
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
