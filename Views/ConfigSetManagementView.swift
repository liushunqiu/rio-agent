import SwiftUI

// MARK: - Config Set Management View

struct ConfigSetManagementView: View {
    @ObservedObject var manager: ConfigSetManager
    @State private var editingConfigSet: ConfigSet?
    @State private var isAddingNew = false
    @State private var newConfigSetName = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("配置集管理")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                
                Spacer()
                
                Button {
                    newConfigSetName = "新配置集 \(manager.configSets.count + 1)"
                    isAddingNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("新建")
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
            addConfigSetSheet
        }
        .sheet(item: $editingConfigSet) { configSet in
            ConfigSetEditorView(configSet: configSet) { updated in
                manager.updateConfigSet(updated)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(Theme.textTertiary)
            
            Text("暂无配置集")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            
            Text("创建配置集来为不同的 AI 提供商配置 API Key 和模型")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Theme.bgTertiary)
        .cornerRadius(Theme.radiusMD)
    }
    
    private var configSetList: some View {
        VStack(spacing: 8) {
            ForEach(manager.configSets) { configSet in
                configSetRow(configSet)
            }
        }
    }
    
    private func configSetRow(_ configSet: ConfigSet) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(configSet.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                
                HStack(spacing: 8) {
                    providerBadge(name: "Claude", config: configSet.claudeConfig)
                    providerBadge(name: "OpenAI", config: configSet.openAIConfig)
                    providerBadge(name: "自定义", config: configSet.customConfig)
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Button {
                    editingConfigSet = configSet
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                
                if manager.configSets.count > 1 {
                    Button {
                        manager.deleteConfigSet(id: configSet.id)
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.statusError)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
    
    private func providerBadge(name: String, config: ProviderConfig) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(config.apiKey.isEmpty ? Theme.textTertiary : Theme.statusSuccess)
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }
    
    private var addConfigSetSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("配置集名称", text: $newConfigSetName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .navigationTitle("新建配置集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isAddingNew = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let newSet = ConfigSet(name: newConfigSetName)
                        manager.addConfigSet(newSet)
                        editingConfigSet = newSet
                        isAddingNew = false
                    }
                    .disabled(newConfigSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 400, height: 200)
    }
}

// MARK: - Config Set Editor View

struct ConfigSetEditorView: View {
    @Environment(\.dismiss) var dismiss
    let configSet: ConfigSet
    var onSave: (ConfigSet) -> Void
    
    @State private var name: String
    @State private var selectedProvider: AIProvider = .claude
    
    @State private var claudeApiKey: String
    @State private var claudeBaseURL: String
    @State private var claudeModel: String
    
    @State private var openAIApiKey: String
    @State private var openAIBaseURL: String
    @State private var openAIModel: String
    
    @State private var customApiKey: String
    @State private var customBaseURL: String
    @State private var customModel: String
    
    init(configSet: ConfigSet, onSave: @escaping (ConfigSet) -> Void) {
        self.configSet = configSet
        self.onSave = onSave
        
        _name = State(initialValue: configSet.name)
        _claudeApiKey = State(initialValue: KeychainManager.loadConfigSetAPIKey(configSetId: configSet.id, provider: .claude) ?? "")
        _claudeBaseURL = State(initialValue: configSet.claudeConfig.baseURL)
        _claudeModel = State(initialValue: configSet.claudeConfig.model)
        
        _openAIApiKey = State(initialValue: KeychainManager.loadConfigSetAPIKey(configSetId: configSet.id, provider: .openAI) ?? "")
        _openAIBaseURL = State(initialValue: configSet.openAIConfig.baseURL)
        _openAIModel = State(initialValue: configSet.openAIConfig.model)
        
        _customApiKey = State(initialValue: KeychainManager.loadConfigSetAPIKey(configSetId: configSet.id, provider: .openAICompatible) ?? "")
        _customBaseURL = State(initialValue: configSet.customConfig.baseURL)
        _customModel = State(initialValue: configSet.customConfig.model)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("配置集名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            HStack(spacing: 0) {
                providerSidebar
                Divider()
                providerContent
            }
        }
        .frame(width: 700, height: 500)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                    dismiss()
                }
            }
        }
    }
    
    private var providerSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                Button {
                    selectedProvider = provider
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: provider.icon)
                            .font(.system(size: 14))
                            .frame(width: 20)
                            .foregroundColor(selectedProvider == provider ? Theme.accentPrimary : Theme.textTertiary)
                        
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: selectedProvider == provider ? .semibold : .regular))
                            .foregroundColor(selectedProvider == provider ? Theme.textPrimary : Theme.textSecondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(selectedProvider == provider ? Theme.bgTertiary : Color.clear)
                    .cornerRadius(Theme.radiusMD)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 160)
        .background(Theme.bgSecondary.opacity(0.5))
    }
    
    @ViewBuilder
    private var providerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedProvider {
                case .claude:
                    claudeSection
                case .openAI:
                    openAISection
                case .openAICompatible:
                    customSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            apiKeyField(label: "Claude API Key", placeholder: "sk-ant-api03-...", text: $claudeApiKey)
            baseURLField(label: "自定义端点 (可选)", placeholder: "https://api.anthropic.com", text: $claudeBaseURL)
            modelField(label: "模型", placeholder: "claude-sonnet-4-20250514", text: $claudeModel)
        }
    }
    
    private var openAISection: some View {
        VStack(alignment: .leading, spacing: 14) {
            apiKeyField(label: "OpenAI API Key", placeholder: "sk-proj-...", text: $openAIApiKey)
            baseURLField(label: "自定义端点 (可选)", placeholder: "https://api.openai.com", text: $openAIBaseURL)
            modelField(label: "模型", placeholder: "gpt-4o", text: $openAIModel)
        }
    }
    
    private var customSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            baseURLField(label: "API 端点", placeholder: "https://api.openrouter.ai 或 http://localhost:11434", text: $customBaseURL)
            apiKeyField(label: "API Key", placeholder: "留空或输入 API Key", text: $customApiKey)
            modelField(label: "模型", placeholder: "例如: llama3, mistral, deepseek-coder", text: $customModel)
        }
    }
    
    private func apiKeyField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            
            SecureField(placeholder, text: text)
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
                    .fill(text.wrappedValue.isEmpty ? Theme.statusError : Theme.statusSuccess)
                    .frame(width: 5, height: 5)
                Text(text.wrappedValue.isEmpty ? "未配置" : "已配置")
                    .font(.system(size: 10))
                    .foregroundColor(text.wrappedValue.isEmpty ? Theme.statusError : Theme.statusSuccess)
            }
        }
    }
    
    private func baseURLField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            
            TextField(placeholder, text: text)
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
    
    private func modelField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            
            TextField(placeholder, text: text)
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
    
    private func save() {
        var updated = configSet
        updated.name = name
        updated.claudeConfig = ProviderConfig(
            apiKey: claudeApiKey,
            baseURL: claudeBaseURL,
            model: claudeModel
        )
        updated.openAIConfig = ProviderConfig(
            apiKey: openAIApiKey,
            baseURL: openAIBaseURL,
            model: openAIModel
        )
        updated.customConfig = ProviderConfig(
            apiKey: customApiKey,
            baseURL: customBaseURL,
            model: customModel
        )
        
        if !claudeApiKey.isEmpty {
            KeychainManager.saveConfigSetAPIKey(claudeApiKey, configSetId: configSet.id, provider: .claude)
        }
        if !openAIApiKey.isEmpty {
            KeychainManager.saveConfigSetAPIKey(openAIApiKey, configSetId: configSet.id, provider: .openAI)
        }
        if !customApiKey.isEmpty {
            KeychainManager.saveConfigSetAPIKey(customApiKey, configSetId: configSet.id, provider: .openAICompatible)
        }
        
        onSave(updated)
    }
}
