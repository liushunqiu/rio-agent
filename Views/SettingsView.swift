import SwiftUI

struct SettingsView: View {
    @Binding var configuration: AIConfiguration
    @Binding var multiAgentConfig: MultiAgentConfig
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0

    // Local state
    @State private var activeProvider: AIProvider
    @State private var claudeApiKey: String
    @State private var claudeBaseURL: String
    @State private var claudeModel: String
    @State private var claudeStreaming: Bool
    @State private var openAIApiKey: String
    @State private var openAIBaseURL: String
    @State private var openAIModel: String
    @State private var openAIStreaming: Bool
    @State private var compatApiKey: String
    @State private var compatBaseURL: String
    @State private var compatModel: String
    @State private var compatStreaming: Bool
    @State private var enableStreaming: Bool
    @State private var maxContextMessages: Int

    init(configuration: Binding<AIConfiguration>, multiAgentConfig: Binding<MultiAgentConfig>? = nil) {
        self._configuration = configuration
        self._multiAgentConfig = multiAgentConfig ?? .constant(MultiAgentConfig())
        let cfg = configuration.wrappedValue
        self._activeProvider = State(initialValue: cfg.activeProvider)
        self._claudeBaseURL = State(initialValue: cfg.claudeConfig.baseURL)
        self._claudeModel = State(initialValue: cfg.claudeConfig.model)
        self._claudeStreaming = State(initialValue: cfg.claudeConfig.isStreaming)
        self._openAIBaseURL = State(initialValue: cfg.openAIConfig.baseURL)
        self._openAIModel = State(initialValue: cfg.openAIConfig.model)
        self._openAIStreaming = State(initialValue: cfg.openAIConfig.isStreaming)
        self._compatBaseURL = State(initialValue: cfg.compatibleConfig.baseURL)
        self._compatModel = State(initialValue: cfg.compatibleConfig.model)
        self._compatStreaming = State(initialValue: cfg.compatibleConfig.isStreaming)
        self._enableStreaming = State(initialValue: cfg.enableStreaming)
        self._maxContextMessages = State(initialValue: cfg.maxContextMessages)
        
        // Load API keys from Keychain
        self._claudeApiKey = State(initialValue: cfg.getAPIKey(for: .claude) ?? "")
        self._openAIApiKey = State(initialValue: cfg.getAPIKey(for: .openAI) ?? "")
        self._compatApiKey = State(initialValue: cfg.getAPIKey(for: .openAICompatible) ?? "")
    }

    private var hasClaudeApiKey: Bool { !claudeApiKey.isEmpty }
    private var hasOpenAIApiKey: Bool { !openAIApiKey.isEmpty }

    private func saveConfiguration() {
        // Save API keys to Keychain first
        if !claudeApiKey.isEmpty {
            try? KeychainManager.saveAPIKey(claudeApiKey, for: .claude)
        } else {
            try? KeychainManager.deleteAPIKey(for: .claude)
        }
        
        if !openAIApiKey.isEmpty {
            try? KeychainManager.saveAPIKey(openAIApiKey, for: .openAI)
        } else {
            try? KeychainManager.deleteAPIKey(for: .openAI)
        }
        
        if !compatApiKey.isEmpty {
            try? KeychainManager.saveAPIKey(compatApiKey, for: .openAICompatible)
        } else {
            try? KeychainManager.deleteAPIKey(for: .openAICompatible)
        }
        
        // Update configuration (API keys are stored separately in Keychain)
        configuration.activeProvider = activeProvider
        configuration.claudeConfig = ProviderConfig(baseURL: claudeBaseURL, model: claudeModel, isStreaming: claudeStreaming)
        configuration.openAIConfig = ProviderConfig(baseURL: openAIBaseURL, model: openAIModel, isStreaming: openAIStreaming)
        configuration.compatibleConfig = ProviderConfig(baseURL: compatBaseURL, model: compatModel, isStreaming: compatStreaming)
        configuration.enableStreaming = enableStreaming
        configuration.maxContextMessages = maxContextMessages
        
        // Update in-memory API keys
        configuration.setAPIKey(claudeApiKey, for: .claude)
        configuration.setAPIKey(openAIApiKey, for: .openAI)
        configuration.setAPIKey(compatApiKey, for: .openAICompatible)

        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: "ai_configuration")
            RioLogger.config.info("💾 设置已保存 (端点: \(compatBaseURL, privacy: .public), 模型: \(compatModel, privacy: .public))")
        } else {
            RioLogger.config.error("❌ 设置保存失败: 编码出错")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("设置")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button("完成") {
                    saveConfiguration()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Tab bar
            HStack(spacing: 0) {
                DarkTabButton(title: "AI 配置", icon: "cpu", isSelected: selectedTab == 0) { selectedTab = 0 }
                DarkTabButton(title: "Multi-Agent", icon: "person.3.fill", isSelected: selectedTab == 1) { selectedTab = 1 }
                DarkTabButton(title: "智能助手", icon: "brain.head.profile", isSelected: selectedTab == 2) { selectedTab = 2 }
                DarkTabButton(title: "关于", icon: "info.circle", isSelected: selectedTab == 3) { selectedTab = 3 }
            }
            .padding(.horizontal, 16)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
                .padding(.top, 8)

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case 0:
                        darkAIConfigSection
                    case 1:
                        MultiAgentSettingsView(
                            config: $multiAgentConfig,
                            aiConfig: AIConfigInfo(
                                hasClaudeKey: hasClaudeApiKey,
                                hasOpenAIKey: hasOpenAIApiKey,
                                claudeApiKey: claudeApiKey,
                                openAIApiKey: openAIApiKey,
                                currentClaudeModel: claudeModel,
                                currentOpenAIModel: openAIModel
                            )
                        )
                    case 2:
                        IntelligentAssistantSettingsView()
                    case 3:
                        darkAboutView
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 600)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }

    // MARK: - AI Config Section

    @ViewBuilder
    private var darkAIConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider selector
            DarkSettingsSection(title: "AI 提供商", icon: "cpu") {
                HStack(spacing: 10) {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        DarkProviderCard(
                            title: p.displayName,
                            icon: p.icon,
                            isSelected: activeProvider == p,
                            isConfigured: isProviderConfigured(p)
                        ) {
                            activeProvider = p
                        }
                    }
                }
            }

            // Provider-specific config
            switch activeProvider {
            case .claude:
                claudeConfigView
            case .openAI:
                openAIConfigView
            case .openAICompatible:
                compatibleConfigView
            }

            // Global settings
            DarkSettingsSection(title: "全局设置", icon: "slider.horizontal.3") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("流式输出")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("AI 回复逐字显示，无需等待完整响应")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $enableStreaming)
                            .toggleStyle(.switch)
                            .tint(Theme.accentPrimary)
                    }

                    Divider().overlay(Theme.borderSubtle)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最大消息数")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("安全上限（达到 85% 上下文窗口时自动压缩旧消息）")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        Picker("", selection: $maxContextMessages) {
                            Text("20").tag(20)
                            Text("50").tag(50)
                            Text("100").tag(100)
                            Text("无限制").tag(999)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                }
            }
        }
    }

    private var claudeConfigView: some View {
        VStack(spacing: 12) {
            DarkSettingsSection(title: "Claude API Key", icon: "key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-ant-api03-...", text: $claudeApiKey)
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

                    HStack(spacing: 6) {
                        Circle()
                            .fill(claudeApiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                            .frame(width: 6, height: 6)
                        Text(claudeApiKey.isEmpty ? "未配置" : "已配置")
                            .font(.system(size: 11))
                            .foregroundColor(claudeApiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("访问 console.anthropic.com 获取 API Key")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.textTertiary)
                }
            }

            DarkSettingsSection(title: "自定义端点 (可选)", icon: "server.rack") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://api.anthropic.com", text: $claudeBaseURL)
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

                    Text("留空使用官方 API，或填入代理/中转站地址")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            DarkSettingsSection(title: "模型", icon: "cpu") {
                Picker("", selection: $claudeModel) {
                    Label("Claude Sonnet 4", systemImage: "bolt.fill").tag("claude-sonnet-4-20250514")
                    Label("Claude Opus 4", systemImage: "star.fill").tag("claude-opus-4-20250514")
                    Label("Claude Haiku 3.5", systemImage: "hare.fill").tag("claude-3-5-haiku-20241022")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var openAIConfigView: some View {
        VStack(spacing: 12) {
            DarkSettingsSection(title: "OpenAI API Key", icon: "key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-proj-...", text: $openAIApiKey)
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

                    HStack(spacing: 6) {
                        Circle()
                            .fill(openAIApiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                            .frame(width: 6, height: 6)
                        Text(openAIApiKey.isEmpty ? "未配置" : "已配置")
                            .font(.system(size: 11))
                            .foregroundColor(openAIApiKey.isEmpty ? Theme.statusError : Theme.statusSuccess)
                    }
                }
            }

            DarkSettingsSection(title: "自定义端点 (可选)", icon: "server.rack") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://api.openai.com", text: $openAIBaseURL)
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

                    Text("留空使用官方 API，或填入代理地址")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            DarkSettingsSection(title: "模型", icon: "cpu") {
                Picker("", selection: $openAIModel) {
                    Label("GPT-4o", systemImage: "star.fill").tag("gpt-4o")
                    Label("GPT-4o Mini", systemImage: "bolt.fill").tag("gpt-4o-mini")
                    Label("GPT-4 Turbo", systemImage: "brain.head.profile").tag("gpt-4-turbo")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var compatibleConfigView: some View {
        VStack(spacing: 12) {
            DarkSettingsSection(title: "API 端点", icon: "server.rack") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://api.openrouter.ai/api 或 http://localhost:11434", text: $compatBaseURL)
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

                    Text("支持 OpenAI 兼容格式的服务：OpenRouter、Ollama、LM Studio 等")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            DarkSettingsSection(title: "API Key", icon: "key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("留空或输入 API Key", text: $compatApiKey)
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

                    Text("本地模型（如 Ollama）通常不需要 API Key")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            DarkSettingsSection(title: "模型名称", icon: "cpu") {
                TextField("例如: llama3, mistral, deepseek-coder", text: $compatModel)
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
    }

    private func isProviderConfigured(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claude: return hasClaudeApiKey
        case .openAI: return hasOpenAIApiKey
        case .openAICompatible: return !compatBaseURL.isEmpty
        }
    }

    // MARK: - About View

    @ViewBuilder
    private var darkAboutView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusXL)
                        .fill(Theme.bgTertiary)
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusXL)
                                .stroke(Theme.borderDefault, lineWidth: 1)
                        )

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accentGradient)
                }

                Text("Rio Agent")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Text("AI 智能助手")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
            }

            Divider().overlay(Theme.borderSubtle)

            VStack(spacing: 8) {
                DarkInfoRow(label: "版本", value: "2.0.0")
                DarkInfoRow(label: "平台", value: "macOS 14.0+")
                DarkInfoRow(label: "Swift", value: "5.9+")
                DarkInfoRow(label: "功能", value: "Streaming + 自定义端点")
            }

            Divider().overlay(Theme.borderSubtle)

            Text("支持 Claude、OpenAI 和自定义 OpenAI 兼容端点。具备工具调用、流式输出、Multi-Agent 协作能力。")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Dark Theme Components

struct DarkTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                VStack {
                    Spacer()
                    if isSelected {
                        Rectangle()
                            .fill(Theme.accentPrimary)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

struct DarkSettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accentPrimary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            content()
        }
        .padding(14)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct DarkProviderCard: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isConfigured: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(isSelected ? Theme.accentPrimary.opacity(0.15) : Theme.bgTertiary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(isSelected ? Theme.accentPrimary.opacity(0.4) : Theme.borderSubtle, lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)
            }

            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

            if isConfigured {
                Circle()
                    .fill(Theme.statusSuccess)
                    .frame(width: 5, height: 5)
            } else {
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(isSelected ? Theme.accentPrimary.opacity(0.5) : Theme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct DarkInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

// Keep legacy components for compatibility
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accentPrimary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            content()
        }
        .padding(14)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        DarkTabButton(title: title, icon: icon, isSelected: isSelected, action: action)
    }
}

struct ProviderCard: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        DarkProviderCard(
            title: title,
            icon: icon,
            isSelected: isSelected,
            isConfigured: false,
            action: action
        )
    }
}

struct AIConfigInfo {
    let hasClaudeKey: Bool
    let hasOpenAIKey: Bool
    let claudeApiKey: String
    let openAIApiKey: String
    let currentClaudeModel: String
    let currentOpenAIModel: String

    var availableProviders: [AIProvider] {
        var providers: [AIProvider] = []
        if hasClaudeKey { providers.append(.claude) }
        if hasOpenAIKey { providers.append(.openAI) }
        return providers
    }

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return claudeApiKey
        case .openAI, .openAICompatible: return openAIApiKey
        }
    }

    func currentModel(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return currentClaudeModel
        case .openAI, .openAICompatible: return currentOpenAIModel
        }
    }
}
