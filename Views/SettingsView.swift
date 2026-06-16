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
    @ObservedObject private var configSetManager = ConfigSetManager.shared

    // Local state
    @State private var planningConfigSetId: UUID?
    @State private var executionConfigSetId: UUID?
    @State private var enableStreaming: Bool
    @State private var maxContextMessages: Int

    init(configuration: Binding<AIConfiguration>, multiAgentConfig: Binding<MultiAgentConfig>? = nil) {
        self._configuration = configuration
        self._multiAgentConfig = multiAgentConfig ?? .constant(MultiAgentConfig())
        let cfg = configuration.wrappedValue
        self._planningConfigSetId = State(initialValue: cfg.planningConfigSetId)
        self._executionConfigSetId = State(initialValue: cfg.executionConfigSetId)
        self._enableStreaming = State(initialValue: cfg.enableStreaming)
        self._maxContextMessages = State(initialValue: cfg.maxContextMessages)
    }

    private func saveConfiguration() {
        // Update configuration
        configuration.planningConfigSetId = planningConfigSetId
        configuration.executionConfigSetId = executionConfigSetId
        configuration.enableStreaming = enableStreaming
        configuration.maxContextMessages = maxContextMessages

        let pName = planningConfigSet?.name ?? "未设置"
        let eName = executionConfigSet?.name ?? "未设置"
        RioLogger.config.info("💾 设置已保存 (规划: \(pName, privacy: .public), 执行: \(eName, privacy: .public))")
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
        .onAppear {
            if executionConfigSetId == nil, let first = configSetManager.configSets.first {
                executionConfigSetId = first.id
                planningConfigSetId = first.id
            }
        }
        .onChange(of: configSetManager.configSets.count) {
            // Auto-select first config set if current selection is invalid
            if !configSetManager.configSets.contains(where: { $0.id == executionConfigSetId }) {
                executionConfigSetId = configSetManager.configSets.first?.id
                planningConfigSetId = executionConfigSetId
            }
        }
    }

    private var currentAIConfigInfo: AIConfigInfo {
        let sets = configSetManager.configSets
        
        // Find first configured model for each provider type
        let claudeSet = sets.first { $0.provider == .claude }
        let openAISet = sets.first { $0.provider == .openAI }
        let customSet = sets.first { $0.provider == .openAICompatible }
        
        return AIConfigInfo(
            hasClaudeKey: claudeSet?.loadAPIKey().isEmpty == false,
            hasOpenAIKey: openAISet?.loadAPIKey().isEmpty == false,
            hasCompatibleEndpoint: customSet?.baseURL.isEmpty == false,
            claudeApiKey: claudeSet?.loadAPIKey() ?? "",
            openAIApiKey: openAISet?.loadAPIKey() ?? "",
            compatibleApiKey: customSet?.loadAPIKey() ?? "",
            currentClaudeModel: claudeSet?.model ?? "",
            currentOpenAIModel: openAISet?.model ?? "",
            currentCompatibleModel: customSet?.model ?? "",
            allConfigSets: sets  // 传递所有配置集
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
                ForEach(configSetManager.configSets) { cs in
                    ProviderHealthRow(
                        name: cs.name,
                        isReady: cs.isConfigured
                    )
                }
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
                title: "规划模型",
                value: planningModelName,
                icon: planningConfigSet?.provider.icon ?? "cpu",
                tone: planningConfigSet?.isConfigured == true ? Theme.statusSuccess : Theme.statusWarning
            )
            SettingsMetric(
                title: "执行模型",
                value: executionModelName,
                icon: executionConfigSet?.provider.icon ?? "cpu",
                tone: executionConfigSet?.isConfigured == true ? Theme.statusSuccess : Theme.statusWarning
            )
            SettingsMetric(
                title: "Multi-Agent",
                value: "\(multiAgentConfig.workers.count) 个子 Agent",
                icon: "person.3.fill",
                tone: Theme.statusSuccess
            )
        }
    }

    private var planningConfigSet: ConfigSet? {
        configSetManager.configSet(for: planningConfigSetId)
    }

    private var executionConfigSet: ConfigSet? {
        configSetManager.configSet(for: executionConfigSetId)
    }

    private var planningModelName: String {
        planningConfigSet?.name ?? "未设置"
    }

    private var executionModelName: String {
        executionConfigSet?.name ?? "未设置"
    }

    // MARK: - AI Config Section

    @ViewBuilder
    private var darkAIConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. 配置集管理（先配模型）
            ConfigSetManagementView(manager: configSetManager)

            // 2. 规划调用 - 选择配置集
            // 3. 执行调用 - 选择配置集
            HStack(alignment: .top, spacing: 14) {
                ConfigSetPickerSection(
                    title: "规划调用",
                    detail: "用于任务拆解、复杂度判断和对话压缩",
                    selectedId: $planningConfigSetId,
                    configSets: configSetManager.configSets
                )

                ConfigSetPickerSection(
                    title: "执行调用",
                    detail: "用于对话回复、工具调用和文件操作",
                    selectedId: $executionConfigSetId,
                    configSets: configSetManager.configSets
                )
            }

            DarkSettingsSection(title: "全局设置", icon: "slider.horizontal.3") {
                HStack(spacing: 18) {
                    HStack {
                        SettingsFieldLabel("流式输出", detail: "执行调用边生成边显示")
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

struct RoleProviderSection: View {
    let title: String
    let detail: String
    @Binding var selectedProvider: AIProvider
    let modelName: (AIProvider) -> String
    let isConfigured: (AIProvider) -> Bool

    var body: some View {
        DarkSettingsSection(title: title, icon: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                ForEach(AIProvider.allCases, id: \.self) { provider in
                    ProviderSelectionRow(
                        provider: provider,
                        model: modelName(provider),
                        isSelected: selectedProvider == provider,
                        isConfigured: isConfigured(provider)
                    ) {
                        selectedProvider = provider
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProviderConfigPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        DarkSettingsSection(title: title, icon: icon) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

// (RoleConfigSetSection and ProviderConfigSetRow removed - replaced by ConfigSetPickerSection)

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

// MARK: - ConfigSet Picker Section (for planning / execution role)

struct ConfigSetPickerSection: View {
    let title: String
    let detail: String
    @Binding var selectedId: UUID?
    let configSets: [ConfigSet]

    var body: some View {
        DarkSettingsSection(title: title, icon: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                if configSets.isEmpty {
                    Text("暂无可用模型，请先在上方添加模型配置")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(configSets) { cs in
                        ConfigSetPickerRow(
                            configSet: cs,
                            isSelected: selectedId == cs.id
                        ) {
                            selectedId = cs.id
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConfigSetPickerRow: View {
    let configSet: ConfigSet
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .fill(isSelected ? Theme.accentPrimary.opacity(0.18) : Theme.bgTertiary)
                        .frame(width: 34, height: 34)
                    Image(systemName: configSet.provider.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(configSet.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Circle()
                            .fill(configSet.isConfigured ? Theme.statusSuccess : Theme.statusWarning)
                            .frame(width: 6, height: 6)
                    }
                    Text(configSet.model.isEmpty ? "未设置模型" : configSet.model)
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
    let allConfigSets: [ConfigSet]  // 新增：所有配置集

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
    
    // 新增：获取指定提供商的所有配置集
    func configSets(for provider: AIProvider) -> [ConfigSet] {
        return allConfigSets.filter { $0.provider == provider }
    }
    
    // 新增：获取指定提供商的所有可用模型
    func availableModels(for provider: AIProvider) -> [String] {
        let sets = configSets(for: provider)
        return sets.map { $0.model }.filter { !$0.isEmpty }
    }
}

// (ProviderSelectionSection and SimpleProviderRow removed - replaced by ConfigSetPickerSection)
