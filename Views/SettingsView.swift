import SwiftUI

enum SettingsTab: CaseIterable {
    case ai
    case multiAgent
    case about

    var title: String {
        switch self {
        case .ai: return "AI 配置"
        case .multiAgent: return "Multi-Agent"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .ai: return "选择默认模型、端点和上下文行为"
        case .multiAgent: return "配置编排器、子 Agent 和任务拆分策略"
        case .about: return "应用版本与能力概览"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "cpu"
        case .multiAgent: return "person.3.fill"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Binding var configuration: AIConfiguration
    @Binding var multiAgentConfig: MultiAgentConfig
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: SettingsTab = .ai

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
    private var hasCompatibleEndpoint: Bool {
        !compatBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)

            VStack(spacing: 0) {
                settingsHeader

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        configurationSummary

                        switch selectedTab {
                        case .ai:
                            darkAIConfigSection
                        case .multiAgent:
                            MultiAgentSettingsView(config: $multiAgentConfig, aiConfig: currentAIConfigInfo)
                        case .about:
                            darkAboutView
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 880, height: 660)
        .background(Theme.bgPrimary)
        .preferredColorScheme(.dark)
    }

    private var currentAIConfigInfo: AIConfigInfo {
        AIConfigInfo(
            hasClaudeKey: hasClaudeApiKey,
            hasOpenAIKey: hasOpenAIApiKey,
            hasCompatibleEndpoint: hasCompatibleEndpoint,
            claudeApiKey: claudeApiKey,
            openAIApiKey: openAIApiKey,
            compatibleApiKey: compatApiKey,
            currentClaudeModel: claudeModel,
            currentOpenAIModel: openAIModel,
            currentCompatibleModel: compatModel
        )
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Rio Agent")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text("模型与协作配置")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            VStack(spacing: 6) {
                SettingsSidebarItem(tab: .ai, selectedTab: $selectedTab)
                SettingsSidebarItem(tab: .multiAgent, selectedTab: $selectedTab)
                SettingsSidebarItem(tab: .about, selectedTab: $selectedTab)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                ProviderHealthRow(name: "Claude", isReady: hasClaudeApiKey)
                ProviderHealthRow(name: "OpenAI", isReady: hasOpenAIApiKey)
                ProviderHealthRow(name: "自定义端点", isReady: hasCompatibleEndpoint)
            }
            .padding(12)
            .background(Theme.bgSecondary)
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 210)
        .background(Theme.bgSecondary.opacity(0.52))
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(selectedTab.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            Button("完成") {
                saveConfiguration()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentPrimary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var configurationSummary: some View {
        HStack(spacing: 12) {
            SettingsMetric(
                title: "当前提供商",
                value: activeProvider.displayName,
                icon: activeProvider.icon,
                tone: isProviderConfigured(activeProvider) ? Theme.statusSuccess : Theme.statusWarning
            )
            SettingsMetric(
                title: "当前模型",
                value: currentModelName,
                icon: "cpu",
                tone: Theme.accentSecondary
            )
            SettingsMetric(
                title: "Multi-Agent",
                value: multiAgentConfig.isEnabled ? "\(multiAgentConfig.workers.count) 个子 Agent" : "未启用",
                icon: "person.3.fill",
                tone: multiAgentConfig.isEnabled ? Theme.statusSuccess : Theme.textTertiary
            )
        }
    }

    private var currentModelName: String {
        switch activeProvider {
        case .claude: return claudeModel
        case .openAI: return openAIModel
        case .openAICompatible: return compatModel
        }
    }

    // MARK: - AI Config Section

    @ViewBuilder
    private var darkAIConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DarkSettingsSection(title: "默认提供商", icon: "cpu") {
                    VStack(spacing: 9) {
                        ForEach(AIProvider.allCases, id: \.self) { p in
                            ProviderSelectionRow(
                                provider: p,
                                model: modelName(for: p),
                                isSelected: activeProvider == p,
                                isConfigured: isProviderConfigured(p)
                            ) {
                                activeProvider = p
                            }
                        }
                    }
                }
                .frame(width: 245)

                VStack(spacing: 12) {
                    switch activeProvider {
                    case .claude:
                        claudeConfigView
                    case .openAI:
                        openAIConfigView
                    case .openAICompatible:
                        compatibleConfigView
                    }
                }
                .frame(maxWidth: .infinity)
            }

            DarkSettingsSection(title: "全局设置", icon: "slider.horizontal.3") {
                HStack(spacing: 18) {
                    HStack {
                        SettingsFieldLabel("流式输出", detail: "回复边生成边显示")
                        Spacer()
                        Toggle("", isOn: $enableStreaming)
                            .toggleStyle(.switch)
                            .tint(Theme.accentPrimary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(width: 1, height: 34)

                    HStack {
                        SettingsFieldLabel("上下文保留", detail: "达到窗口阈值时自动压缩")
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
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func modelName(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return claudeModel
        case .openAI: return openAIModel
        case .openAICompatible: return compatModel
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

struct SettingsSidebarItem: View {
    let tab: SettingsTab
    @Binding var selectedTab: SettingsTab

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textTertiary)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.bgTertiary : Color.clear)
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(isSelected ? Theme.borderDefault : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

struct SettingsMetric: View {
    let title: String
    let value: String
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
                Text(value.isEmpty ? "未设置" : value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(Theme.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct ProviderHealthRow: View {
    let name: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isReady ? Theme.statusSuccess : Theme.textTertiary)
                .frame(width: 7, height: 7)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Text(isReady ? "可用" : "待配置")
                .font(.system(size: 10))
                .foregroundColor(isReady ? Theme.statusSuccess : Theme.textTertiary)
        }
    }
}

struct ProviderSelectionRow: View {
    let provider: AIProvider
    let model: String
    let isSelected: Bool
    let isConfigured: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .fill(isSelected ? Theme.accentPrimary.opacity(0.18) : Theme.bgTertiary)
                        .frame(width: 34, height: 34)
                    Image(systemName: provider.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Circle()
                            .fill(isConfigured ? Theme.statusSuccess : Theme.statusWarning)
                            .frame(width: 6, height: 6)
                    }
                    Text(model.isEmpty ? "未设置模型" : model)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentPrimary)
                }
            }
            .padding(9)
            .background(isSelected ? Theme.bgTertiary : Theme.bgInput.opacity(0.72))
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(isSelected ? Theme.accentPrimary.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsFieldLabel: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }
}

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
    let hasCompatibleEndpoint: Bool
    let claudeApiKey: String
    let openAIApiKey: String
    let compatibleApiKey: String
    let currentClaudeModel: String
    let currentOpenAIModel: String
    let currentCompatibleModel: String

    var availableProviders: [AIProvider] {
        var providers: [AIProvider] = []
        if hasClaudeKey { providers.append(.claude) }
        if hasOpenAIKey { providers.append(.openAI) }
        if hasCompatibleEndpoint { providers.append(.openAICompatible) }
        return providers
    }

    var hasAnyProvider: Bool {
        !availableProviders.isEmpty
    }

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return claudeApiKey
        case .openAI: return openAIApiKey
        case .openAICompatible: return compatibleApiKey
        }
    }

    func currentModel(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return currentClaudeModel
        case .openAI: return currentOpenAIModel
        case .openAICompatible: return currentCompatibleModel
        }
    }
}
