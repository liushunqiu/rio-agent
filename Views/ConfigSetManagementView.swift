import SwiftUI

// MARK: - Config Set Management View

struct ConfigSetManagementView: View {
    @ObservedObject var manager: ConfigSetManager
    @State private var editingConfigSet: ConfigSet?
    @State private var isAddingNew = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("模型配置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                
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
                manager.addConfigSet(newSet)
            }
        }
        .sheet(item: $editingConfigSet) { configSet in
            ConfigSetEditorView(configSet: configSet) { updated in
                manager.updateConfigSet(updated)
            }
        }
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
                
                HStack(spacing: 6) {
                    Text(configSet.provider.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                    
                    if !configSet.model.isEmpty {
                        Text(configSet.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
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
            
            if manager.configSets.count > 0 {
                Button {
                    manager.deleteConfigSet(id: configSet.id)
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.statusError.opacity(0.7))
                }
                .buttonStyle(.plain)
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
}

// MARK: - Config Set Editor View

struct ConfigSetEditorView: View {
    @Environment(\.dismiss) var dismiss
    let configSet: ConfigSet?
    var onSave: (ConfigSet) -> Void
    
    @State private var name: String
    @State private var provider: AIProvider
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    
    init(configSet: ConfigSet?, onSave: @escaping (ConfigSet) -> Void) {
        self.configSet = configSet
        self.onSave = onSave
        
        _name = State(initialValue: configSet?.name ?? "")
        _provider = State(initialValue: configSet?.provider ?? .openAICompatible)
        _baseURL = State(initialValue: configSet?.baseURL ?? "")
        _apiKey = State(initialValue: configSet?.loadAPIKey() ?? "")
        _model = State(initialValue: configSet?.model ?? "")
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
                                .fill(apiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                                .frame(width: 5, height: 5)
                            Text(apiKey.isEmpty ? "未配置" : "已配置")
                                .font(.system(size: 10))
                                .foregroundColor(apiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                        }
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
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }
    
    private var placeholderURL: String {
        switch provider {
        case .claude: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com"
        case .openAICompatible: return "https://your-endpoint.com/v1"
        }
    }
    
    private var placeholderModel: String {
        switch provider {
        case .claude: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        case .openAICompatible: return "your-model-name"
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
    
    private func save() {
        let id = configSet?.id ?? UUID()
        let newSet = ConfigSet(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: provider,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        newSet.saveAPIKey(apiKey)
        onSave(newSet)
    }
}
