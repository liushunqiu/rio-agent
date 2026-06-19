import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var agentEngine = AgentEngine()
    @StateObject private var conversationManager = ConversationManager()
    @State private var showingSettings = false
    @State private var settingsInitialTab: SettingsTab = .ai
    @State private var settingsLaunchContext: SettingsLaunchContext?
    @State private var showingConfirmation = false
    @State private var confirmationTitle = ""
    @State private var confirmationMessage = ""
    @State private var confirmationAllowsTrustForSession = true
    @State private var confirmationContinuation: CheckedContinuation<ConfirmationResult, Never>?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(
                conversationManager: conversationManager,
                onSelect: { conversation in
                    prepareForConversationContextChange()
                    conversationManager.selectConversation(conversation)
                    agentEngine.loadConversation(conversation)
                },
                onDelete: { conversation in
                    let deletesCurrentConversation = conversationManager.currentConversation?.id == conversation.id
                    if deletesCurrentConversation {
                        prepareForConversationContextChange()
                    }

                    conversationManager.deleteConversation(conversation)

                    guard deletesCurrentConversation else { return }

                    if let current = conversationManager.currentConversation {
                        agentEngine.loadConversation(current)
                    } else {
                        agentEngine.clearConversation()
                    }
                },
                onNewConversation: {
                    prepareForConversationContextChange()
                    let newConversation = conversationManager.createNewConversation(
                        workingDirectory: agentEngine.workingDirectory
                    )
                    agentEngine.loadConversation(newConversation)
                },
                onOpenSettings: {
                    settingsInitialTab = .ai
                    settingsLaunchContext = nil
                    showingSettings = true
                }
            )
            .frame(width: 260)

            // Divider
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.8))
                .frame(width: 1)

            // Main content
            MainContentView(
                agentEngine: agentEngine,
                inputText: conversationDraftBinding,
                showingSettings: $showingSettings,
                settingsInitialTab: $settingsInitialTab,
                settingsLaunchContext: $settingsLaunchContext,
                onSubmit: {
                    let text = conversationManager.currentConversation?.draftInput ?? ""
                    let accepted = agentEngine.submitUserInput(text) {
                        conversationManager.updateCurrentConversation(
                            messages: agentEngine.messages,
                            workingDirectory: .set(agentEngine.workingDirectory),
                            pendingDecision: .set(agentEngine.persistedPendingDecision)
                        )
                    }
                    if accepted {
                        conversationManager.updateDraftInput("")
                    }
                    return accepted
                },
                onNewChatSubmit: { text in
                    // 如果没有当前对话，创建新对话
                    if conversationManager.currentConversation == nil {
                        let newConversation = conversationManager.createNewConversation(
                            workingDirectory: agentEngine.workingDirectory
                        )
                        agentEngine.loadConversation(newConversation)
                    }
                    let accepted = agentEngine.submitUserInput(text) {
                        conversationManager.updateCurrentConversation(
                            messages: agentEngine.messages,
                            workingDirectory: .set(agentEngine.workingDirectory),
                            pendingDecision: .set(agentEngine.persistedPendingDecision)
                        )
                    }
                    if accepted {
                        conversationManager.updateDraftInput("")
                    }
                    return accepted
                }
            )

            // Divider
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.8))
                .frame(width: 1)

            // Context panel (right sidebar)
            ContextPanel(
                singleAgentPlan: agentEngine.currentSingleAgentPlan,
                taskPlan: agentEngine.currentTaskPlan,
                pipeline: agentEngine.currentPipeline,
                singleAgentVerification: agentEngine.singleAgentVerificationSummary,
                pendingUserDecision: agentEngine.pendingUserDecision,
                runtimeRoles: agentEngine.runtimeModelRoles,
                messageCount: agentEngine.messages.filter(\.isVisibleInTranscript).count,
                workingDirectory: agentEngine.workingDirectory,
                estimatedTokens: agentEngine.getTotalTokensUsed(),
                contextWindow: AIProvider.contextWindow(for: agentEngine.primaryDisplayModelName),
                recentFiles: agentEngine.memory.session.recentFiles
            )
            .frame(width: 260)
        }
        .background(AppBackgroundView())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings, onDismiss: {
            // 兜底持久化；设置面板内部已即时应用更改。
            agentEngine.saveConfiguration()
        }) {
            SettingsView(
                configuration: Binding(
                    get: { agentEngine.configuration },
                    set: { agentEngine.updateConfiguration($0) }
                ),
                multiAgentConfig: Binding(
                    get: { agentEngine.multiAgentConfig },
                    set: { agentEngine.updateMultiAgentConfig($0) }
                ),
                memory: agentEngine.memory,
                initialTab: settingsInitialTab,
                launchContext: settingsLaunchContext
            )
        }
        .alert(confirmationTitle, isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {
                resolveConfirmation(.denied)
            }
            Button("执行") {
                resolveConfirmation(.approved)
            }
            if confirmationAllowsTrustForSession {
                Button("信任本会话") {
                    resolveConfirmation(.trustedForSession)
                }
            }
        } message: {
            Text(confirmationMessage)
        }
        .onChange(of: showingConfirmation) { _, isShowing in
            if !isShowing {
                resolveConfirmation(.denied)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showConfirmation)) { notification in
            if let title = notification.userInfo?["title"] as? String,
               let message = notification.userInfo?["message"] as? String,
               let continuation = notification.userInfo?["continuation"] as? CheckedContinuation<ConfirmationResult, Never> {
                resolveConfirmation(.denied)
                confirmationTitle = title
                confirmationMessage = message
                confirmationAllowsTrustForSession = notification.userInfo?["allowsTrustForSession"] as? Bool ?? true
                confirmationContinuation = continuation
                showingConfirmation = true
            }
        }
        .onAppear {
            // 启动时加载已保存的当前对话，避免新消息覆盖旧对话
            if let current = conversationManager.currentConversation {
                agentEngine.loadConversation(current)
            }
            // Immediately update conversation title when first user message is added
            agentEngine.onUserMessageAdded = { [weak conversationManager] in
                conversationManager?.updateCurrentConversation(
                    messages: agentEngine.messages,
                    workingDirectory: .set(agentEngine.workingDirectory),
                    pendingDecision: .set(agentEngine.persistedPendingDecision)
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewConversation)) { _ in
            prepareForConversationContextChange()
            let newConversation = conversationManager.createNewConversation(
                workingDirectory: agentEngine.workingDirectory
            )
            agentEngine.loadConversation(newConversation)
        }
        .onChange(of: agentEngine.workingDirectory) { _, newValue in
            conversationManager.updateWorkingDirectory(newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                flushConversationPersistence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushConversationPersistence()
        }
        .onDisappear {
            flushConversationPersistence()
        }
    }

    private func resolveConfirmation(_ result: ConfirmationResult) {
        guard let continuation = confirmationContinuation else { return }
        confirmationContinuation = nil
        showingConfirmation = false
        continuation.resume(returning: result)
    }

    private func prepareForConversationContextChange() {
        resolveConfirmation(.denied)
        persistCurrentConversationState()
    }

    private func persistCurrentConversationState() {
        guard conversationManager.currentConversation != nil else { return }
        conversationManager.updateCurrentConversation(
            messages: agentEngine.messages,
            workingDirectory: .set(agentEngine.workingDirectory),
            pendingDecision: .set(agentEngine.persistedPendingDecision)
        )
    }

    private func flushConversationPersistence() {
        persistCurrentConversationState()
        conversationManager.flushPendingSave()
    }

    private var conversationDraftBinding: Binding<String> {
        Binding(
            get: { conversationManager.currentConversation?.draftInput ?? "" },
            set: { conversationManager.updateDraftInput($0) }
        )
    }
}

// MARK: - Background

struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            Theme.bgPrimary

            LinearGradient(
                colors: [
                    Theme.accentSoft.opacity(0.16),
                    Color.clear,
                    Theme.accentPrimary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var conversationManager: ConversationManager
    let onSelect: (Conversation) -> Void
    let onDelete: (Conversation) -> Void
    let onNewConversation: () -> Void
    let onOpenSettings: () -> Void

    @State private var hoveredConversation: UUID?
    @State private var pendingDeleteConversation: Conversation?

    private var draftCount: Int {
        conversationManager.conversations.filter {
            !$0.draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .fill(Theme.bgGlass)
                            .frame(width: 34, height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMD)
                                    .stroke(Theme.borderDefault, lineWidth: 1)
                            )
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accentGradient)
                    }

                    Text("Rio Agent")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()
                }

                HStack(alignment: .center, spacing: 10) {
                    Text("最近会话")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)

                    Spacer()

                    Button(action: onNewConversation) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("新建")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.bgGlass.opacity(0.7))
                        .cornerRadius(Theme.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMD)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    SidebarMetric(
                        value: "\(conversationManager.conversations.count)",
                        label: "对话",
                        isEmphasized: conversationManager.conversations.count > 0
                    )
                    SidebarMetric(
                        value: draftCount == 0 ? "0" : "\(draftCount)",
                        label: "草稿",
                        isEmphasized: draftCount > 0
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)

            // Divider
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            // Conversation list
            if conversationManager.conversations.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textTertiary)
                    Text("暂无对话")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                    Text("从左上角新建一个任务，或在首页直接输入需求开始。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conversationManager.conversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversationManager.currentConversation?.id == conversation.id,
                                isHovered: hoveredConversation == conversation.id
                            )
                            .onTapGesture {
                                onSelect(conversation)
                            }
                            .onHover { hovering in
                                hoveredConversation = hovering ? conversation.id : nil
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    pendingDeleteConversation = conversation
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Footer
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                Button(action: onOpenSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                        Text("设置")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("v2.0")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.bgGlass.opacity(0.5))
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
        }
        .background(
            LinearGradient(
                colors: [Theme.bgSecondary.opacity(0.96), Theme.bgPrimary.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .alert("删除对话？", isPresented: deleteConfirmationBinding) {
            Button("取消", role: .cancel) {
                pendingDeleteConversation = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDeleteConversation {
                    onDelete(pendingDeleteConversation)
                }
                pendingDeleteConversation = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteConversation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteConversation = nil
                }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        guard let conversation = pendingDeleteConversation else {
            return "这个操作无法撤销。"
        }

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "未命名对话" : title
        let messageCount = conversation.visibleMessageCount
        let draft = conversation.draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftSuffix = draft.isEmpty ? "" : "，并包含未发送草稿"
        return "将删除「\(displayTitle)」及其中 \(messageCount) 条可见消息\(draftSuffix)。这个操作无法撤销。"
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isSelected ? Theme.accentPrimary.opacity(0.13) : Color.clear)
                    )

                Text(conversation.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .help(conversation.title)

                Spacer(minLength: 8)

                Text(conversation.updatedAt, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            if let previewText {
                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(2)
                    .help(previewText)
            }

            HStack(spacing: 10) {
                if let pendingDecisionLabel {
                    MetaPill(
                        icon: "questionmark.circle",
                        text: pendingDecisionLabel,
                        isSelected: isSelected,
                        tone: Theme.statusWarning
                    )
                }

                if let messageMetaLabel {
                    MetaPill(
                        icon: "text.bubble",
                        text: messageMetaLabel,
                        isSelected: isSelected
                    )
                }

                if conversation.workingDirectory != nil {
                    MetaPill(
                        icon: "folder",
                        text: folderName,
                        isSelected: isSelected,
                        helpText: conversation.workingDirectory
                    )
                }

                if !conversation.draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MetaPill(
                        icon: "square.and.pencil",
                        text: "草稿",
                        isSelected: isSelected
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(isSelected ? Theme.bgGlass : (isHovered ? Theme.bgGlass.opacity(0.55) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(isSelected ? Theme.accentPrimary.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var visibleMessageCount: Int {
        conversation.visibleMessageCount
    }

    private var hasDraft: Bool {
        !conversation.draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewText: String? {
        conversation.latestPreviewContent
    }

    private var folderName: String {
        guard let path = conversation.workingDirectory else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var messageMetaLabel: String? {
        if visibleMessageCount > 0 {
            return "\(visibleMessageCount) 条消息"
        }
        if pendingDecisionLabel != nil || hasDraft {
            return nil
        }
        return "未开始"
    }

    private var pendingDecisionLabel: String? {
        guard let pendingDecision = conversation.pendingDecision else { return nil }

        switch pendingDecision {
        case .overwriteAgentFile:
            return "等待覆盖确认"
        case .chooseExecutionModeForTask:
            return "等待模式确认"
        }
    }
}

// MARK: - Main Content

struct MainContentView: View {
    @ObservedObject var agentEngine: AgentEngine
    @Binding var inputText: String
    @Binding var showingSettings: Bool
    @Binding var settingsInitialTab: SettingsTab
    @Binding var settingsLaunchContext: SettingsLaunchContext?
    let onSubmit: () -> Bool
    let onNewChatSubmit: ((String) -> Bool)?

    @FocusState private var isInputFocused: Bool

    init(
        agentEngine: AgentEngine,
        inputText: Binding<String>,
        showingSettings: Binding<Bool>,
        settingsInitialTab: Binding<SettingsTab>,
        settingsLaunchContext: Binding<SettingsLaunchContext?>,
        onSubmit: @escaping () -> Bool,
        onNewChatSubmit: ((String) -> Bool)? = nil
    ) {
        self._agentEngine = ObservedObject(wrappedValue: agentEngine)
        self._inputText = inputText
        self._showingSettings = showingSettings
        self._settingsInitialTab = settingsInitialTab
        self._settingsLaunchContext = settingsLaunchContext
        self.onSubmit = onSubmit
        self.onNewChatSubmit = onNewChatSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            TopBar(
                showingSettings: $showingSettings,
                settingsInitialTab: $settingsInitialTab,
                settingsLaunchContext: $settingsLaunchContext,
                pipeline: agentEngine.currentPipeline,
                singleAgentPlan: agentEngine.currentSingleAgentPlan,
                singleAgentVerification: agentEngine.singleAgentVerificationSummary,
                currentTaskPlan: agentEngine.currentTaskPlan,
                pendingUserDecision: agentEngine.pendingUserDecision,
                currentProvider: agentEngine.configuration.executionProvider,
                currentModelName: agentEngine.primaryDisplayModelName,
                currentWorkingDirectory: agentEngine.workingDirectory,
                messageCount: agentEngine.messages.filter(\.isVisibleInTranscript).count,
                prefersCompactRuntimeChrome: hasVisibleTranscript && (
                    agentEngine.currentPipeline != nil ||
                    agentEngine.pendingUserDecision != nil ||
                    agentEngine.singleAgentVerificationSummary != nil
                )
            )

            // Chat area
            if hasVisibleTranscript {
                EnhancedChatView(
                    messages: agentEngine.messages,
                    isProcessing: agentEngine.isProcessing,
                    currentToolCallId: agentEngine.currentToolCallId,
                    currentPipeline: agentEngine.currentPipeline,
                    singleAgentVerification: agentEngine.singleAgentVerificationSummary,
                    currentTaskPlan: agentEngine.currentTaskPlan,
                    pendingUserDecision: agentEngine.pendingUserDecision
                )
                .transition(.opacity)
            } else if hasInternalActivity {
                InternalActivityView(
                    isProcessing: agentEngine.isProcessing,
                    pendingUserDecision: agentEngine.pendingUserDecision,
                    workingDirectory: agentEngine.workingDirectory,
                    onStop: agentEngine.isProcessing && agentEngine.pendingUserDecision == nil ? {
                        agentEngine.stopProcessing()
                    } : nil
                )
                .transition(.opacity)
            } else {
                NewChatPage(
                    inputText: $inputText,
                    onSubmit: { text in
                        onNewChatSubmit?(text) ?? false
                    },
                    workingDirectory: $agentEngine.workingDirectory,
                    modelName: agentEngine.primaryDisplayModelName,
                    providerName: agentEngine.primaryDisplayProviderName,
                    canAcceptInput: agentEngine.canAcceptUserInput,
                    pendingUserDecision: agentEngine.pendingUserDecision
                )
                .transition(.opacity)
            }

            // Error banner
            if let error = agentEngine.error {
                ErrorBanner(
                    message: error,
                    isNonBlocking: error.contains("已继续执行标准流程"),
                    canResumeTask: resumableTaskInput != nil,
                    onResumeTask: restoreResumableTaskInput,
                    onOpenSettings: settingsShortcutAction(for: error, recoveryContext: agentEngine.errorRecoveryContext),
                    settingsButtonTitle: settingsShortcutTitle(for: error, recoveryContext: agentEngine.errorRecoveryContext),
                    settingsHelpText: settingsShortcutHelpText(for: error, recoveryContext: agentEngine.errorRecoveryContext),
                    onDismiss: {
                        agentEngine.error = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input area (shown whenever the current session has started or needs a decision)
            if shouldShowInputArea {
                InputArea(
                    text: $inputText,
                    isProcessing: agentEngine.isProcessing,
                    canAcceptInput: agentEngine.canAcceptUserInput,
                    pendingUserDecision: agentEngine.pendingUserDecision,
                    isFocused: $isInputFocused,
                    workingDirectory: $agentEngine.workingDirectory,
                    modelName: agentEngine.primaryDisplayModelName,
                    providerName: agentEngine.primaryDisplayProviderName,
                    onSubmit: onSubmit,
                    onStop: {
                        agentEngine.stopProcessing()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeInOut(duration: 0.3), value: hasVisibleTranscript)
        .animation(.easeInOut(duration: 0.3), value: hasInternalActivity)
        .onAppear {
            isInputFocused = true
        }
    }

    private var visibleMessageCount: Int {
        agentEngine.messages.filter(\.isVisibleInTranscript).count
    }

    private var hasVisibleTranscript: Bool {
        visibleMessageCount > 0
    }

    private var hasInternalActivity: Bool {
        !hasVisibleTranscript && (
            agentEngine.isProcessing ||
            agentEngine.pendingUserDecision != nil
        )
    }

    private var shouldShowInputArea: Bool {
        hasVisibleTranscript || agentEngine.pendingUserDecision != nil
    }

    private var resumableTaskInput: String? {
        let draft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            return draft
        }

        return agentEngine.messages
            .reversed()
            .first(where: shouldUseMessageForTaskResume)?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreResumableTaskInput() {
        guard let resumableTaskInput, !resumableTaskInput.isEmpty else { return }
        inputText = resumableTaskInput
        agentEngine.error = nil
        isInputFocused = true
    }

    private func shouldUseMessageForTaskResume(_ message: Message) -> Bool {
        message.isEligibleUserTaskInput
    }

    private func settingsShortcutAction(
        for error: String,
        recoveryContext: ErrorRecoveryContext?
    ) -> (() -> Void)? {
        guard let launchContext = resolvedSettingsLaunchContext(for: error, recoveryContext: recoveryContext) else { return nil }
        return {
            settingsInitialTab = launchContext.tab
            settingsLaunchContext = launchContext
            showingSettings = true
        }
    }

    private func settingsShortcutHelpText(
        for error: String,
        recoveryContext: ErrorRecoveryContext?
    ) -> String? {
        resolvedSettingsLaunchContext(for: error, recoveryContext: recoveryContext)?.detail
    }

    private func settingsShortcutTitle(
        for error: String,
        recoveryContext: ErrorRecoveryContext?
    ) -> String? {
        if let recoveryContext {
            return recoveryContext.recoveryActionTitle
        }
        return resolvedSettingsLaunchContext(for: error, recoveryContext: recoveryContext)?.title
    }

    private func resolvedSettingsLaunchContext(
        for error: String,
        recoveryContext: ErrorRecoveryContext?
    ) -> SettingsLaunchContext? {
        SettingsRecoveryRouter.resolve(
            error: error,
            recoveryContext: recoveryContext
        )
    }
}

struct InternalActivityView: View {
    let isProcessing: Bool
    let pendingUserDecision: AgentEngine.PendingUserDecision?
    let workingDirectory: String?
    var onStop: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tint)
                        .symbolEffect(.pulse, options: .repeating, value: shouldAnimateActivity)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                }

                if let workingDirectory {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(URL(fileURLWithPath: workingDirectory).lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.bgGlass)
                    .cornerRadius(Theme.radiusSM)
                    .help(workingDirectory)
                }

                if let onStop {
                    Button(action: onStop) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("停止当前任务")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Theme.statusError)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.statusError.opacity(0.12))
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.statusError.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("停止当前任务")
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusLG)
                    .fill(Theme.bgGlass.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLG)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var icon: String {
        if pendingUserDecision != nil {
            return "questionmark.circle"
        }
        return isProcessing ? "arrow.triangle.2.circlepath" : "text.bubble"
    }

    private var tint: Color {
        pendingUserDecision != nil ? Theme.statusWarning : Theme.accentPrimary
    }

    private var shouldAnimateActivity: Bool {
        isProcessing && pendingUserDecision == nil
    }

    private var title: String {
        if pendingUserDecision != nil {
            return "等待你的确认"
        }
        return isProcessing ? "正在准备任务" : "会话正在同步"
    }

    private var detail: String {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "系统需要确认是否覆盖已有 AGENT.md。你可以回复是/否，也可以直接输入新的任务。"
            case .chooseExecutionModeForTask:
                return "系统已完成执行模式判断，正在等待你选择继续多 Agent 或改用单 Agent。你也可以直接输入新的任务，系统会自动切换。"
            }
        }

        if isProcessing {
            return "系统已经开始处理当前任务，正在准备首个可见结果。完成第一步后会自动切换到主阅读流。"
        }

        return "当前会话没有可见消息。你可以继续输入任务。"
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @Binding var showingSettings: Bool
    @Binding var settingsInitialTab: SettingsTab
    @Binding var settingsLaunchContext: SettingsLaunchContext?
    var pipeline: ExecutionPipeline?
    var singleAgentPlan: AgentEngine.SingleAgentPlan?
    var singleAgentVerification: VerifierService.VerificationOutcome?
    var currentTaskPlan: TaskPlan?
    var pendingUserDecision: AgentEngine.PendingUserDecision?
    var currentProvider: AIProvider = .claude
    var currentModelName: String = ""
    var currentWorkingDirectory: String?
    var messageCount: Int = 0
    var prefersCompactRuntimeChrome = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: currentProvider.icon)
                    .font(.system(size: 11))
                Text(topBarModelLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.bgTertiary)
            .cornerRadius(Theme.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
            .help(modelHelpText)

            if pipeline != nil || pendingUserDecision != nil || singleAgentVerification != nil {
                HStack(spacing: 5) {
                    Image(systemName: pipelineIcon)
                        .font(.system(size: 10))
                    Text(pipelineLabel)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(pipelineColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pipelineColor.opacity(0.1))
                .cornerRadius(Theme.radiusSM)
            }

            if shouldShowSecondaryRuntimeSummaries, let executionSummary {
                HStack(spacing: 5) {
                    Image(systemName: summaryIcon)
                        .font(.system(size: 10))
                    Text(executionSummary)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(summaryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(summaryColor.opacity(0.08))
                .cornerRadius(Theme.radiusSM)
            }

            if shouldShowSecondaryRuntimeSummaries, let focusSummary {
                HStack(spacing: 5) {
                    Image(systemName: focusIcon)
                        .font(.system(size: 10))
                    Text(focusSummary)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(focusSummary)
                }
                .foregroundColor(focusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(focusColor.opacity(0.08))
                .cornerRadius(Theme.radiusSM)
            }

            Spacer()

            if let currentWorkingDirectory {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(URL(fileURLWithPath: currentWorkingDirectory).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.bgGlass.opacity(0.7))
                .cornerRadius(Theme.radiusSM)
                .help(currentWorkingDirectory)
            }

            if messageCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text("\(messageCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.bgGlass.opacity(0.5))
                .cornerRadius(Theme.radiusSM)
            }

            Button(action: {
                settingsInitialTab = .ai
                settingsLaunchContext = nil
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .help("设置")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            Theme.bgSecondary.opacity(0.78)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 1)
                }
        )
    }

    private var pipelineLabel: String {
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "需修订"
            case .unverified:
                return "未验证"
            case .verified:
                return "已验证"
            }
        }

        switch pipeline?.overallStatus {
        case _ where pendingUserDecision != nil:
            return "等待确认"
        case .running:
            return "执行中"
        case .completed:
            return "已完成"
        case .cancelled:
            return "已停止"
        case .failed:
            return "需处理"
        case .pending:
            return "待开始"
        case .skipped, .none:
            return "流程"
        }
    }

    private var shouldShowSecondaryRuntimeSummaries: Bool {
        !prefersCompactRuntimeChrome
    }

    private var pipelineColor: Color {
        if let singleAgentVerification {
            return verificationTone(for: singleAgentVerification.status)
        }

        switch pipeline?.overallStatus {
        case _ where pendingUserDecision != nil:
            return Theme.statusWarning
        case .running:
            return Theme.statusInfo
        case .completed:
            return Theme.statusSuccess
        case .cancelled:
            return Theme.textTertiary
        case .failed:
            return Theme.statusError
        case .pending, .skipped, .none:
            return Theme.accentPrimary
        }
    }

    private var pipelineIcon: String {
        if let singleAgentVerification {
            return verificationIcon(for: singleAgentVerification.status)
        }

        switch pipeline?.overallStatus {
        case _ where pendingUserDecision != nil:
            return "questionmark.circle"
        case .running:
            return "arrow.triangle.branch"
        case .completed:
            return "checkmark.seal"
        case .cancelled:
            return "slash.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .pending, .skipped, .none:
            return "arrow.triangle.branch"
        }
    }

    private var executionSummary: String? {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return nil
            case .chooseExecutionModeForTask:
                return nil
            }
        }

        if singleAgentVerification != nil {
            return nil
        }

        if let currentTaskPlan {
            let actionable = currentTaskPlan.subTasks.filter(\.needsAttention).count
            if actionable > 0 {
                return multiAgentSummary(for: currentTaskPlan)
            }
            if currentTaskPlan.status == .completed {
                return nil
            }
            return multiAgentSummary(for: currentTaskPlan)
        }

        if let singleAgentPlan {
            let completed = min(singleAgentPlan.currentStep, singleAgentPlan.steps.count)
            return "\(completed)/\(singleAgentPlan.steps.count) 步"
        }

        if pipeline?.overallStatus == .completed {
            return nil
        }

        if let pipeline,
           let currentStage = pipeline.currentStage {
            if focusSummary == currentStage.type.title {
                return nil
            }
            return currentStage.type.title
        }

        return nil
    }

    private func multiAgentSummary(for plan: TaskPlan) -> String {
        let completed = plan.subTasks.filter { $0.status == .completed }.count
        let failed = plan.subTasks.filter { $0.status == .failed }.count
        let cancelled = plan.subTasks.filter { $0.status == .cancelled }.count
        var parts = ["\(completed)/\(plan.subTasks.count) 子任务"]
        if failed > 0 {
            parts.append("失败 \(failed)")
        }
        if cancelled > 0 {
            parts.append("停止 \(cancelled)")
        }
        return parts.joined(separator: " · ")
    }

    private var summaryIcon: String {
        if pendingUserDecision != nil {
            return "questionmark.circle"
        }
        if currentTaskPlan != nil {
            return "square.stack.3d.up"
        }
        if singleAgentPlan != nil {
            return "list.number"
        }
        return "point.3.connected.trianglepath.dotted"
    }

    private var summaryColor: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if let singleAgentVerification {
            return verificationTone(for: singleAgentVerification.status)
        }

        switch pipeline?.overallStatus {
        case .completed:
            return Theme.statusSuccess
        case .failed:
            return Theme.statusError
        case .cancelled:
            return Theme.textTertiary
        case .running, .pending, .skipped, .none:
            return Theme.textSecondary
        }
    }

    private var modelHelpText: String {
        let provider = currentProvider.displayName
        guard !currentModelName.isEmpty else { return provider }
        return "\(provider) · \(currentModelName)"
    }

    private var topBarModelLabel: String {
        let trimmedModel = currentModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return currentProvider.displayName }
        return trimmedModel
    }

    private var focusSummary: String? {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "覆盖 AGENT.md"
            case .chooseExecutionModeForTask:
                return "继续多 Agent 或改单 Agent"
            }
        }

        if let currentTaskPlan {
            let actionable = currentTaskPlan.subTasks.filter(\.needsAttention).count
            if actionable > 0 {
                return "待处理 \(actionable) 项"
            }
            if currentTaskPlan.status == .completed {
                return nil
            }
        }

        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "答案需要修订"
            case .unverified:
                return "缺少完成证据"
            case .verified:
                return nil
            }
        }

        if let failedStage = pipeline?.stages.last(where: { $0.status == .failed }) {
            return failedStage.type.title
        }

        if let cancelledStage = pipeline?.stages.last(where: { $0.status == .cancelled }) {
            return cancelledStage.type.title
        }

        if pipeline?.overallStatus == .completed {
            return nil
        }

        if let currentStage = pipeline?.currentStage {
            if pipeline?.overallStatus == .running {
                return nil
            }
            return currentStage.type.title
        }

        return nil
    }

    private var focusIcon: String {
        if let singleAgentVerification {
            return verificationFocusIcon(for: singleAgentVerification.status)
        }

        if let pipeline {
            if pipeline.stages.contains(where: { $0.status == .failed }) {
                return "exclamationmark.triangle"
            }
            if pipeline.stages.contains(where: { $0.status == .cancelled }) {
                return "slash.circle"
            }
        }
        if pendingUserDecision != nil {
            return "questionmark.circle"
        }
        return "scope"
    }

    private var focusColor: Color {
        if let singleAgentVerification {
            return verificationTone(for: singleAgentVerification.status)
        }

        if let pipeline {
            if pipeline.stages.contains(where: { $0.status == .failed }) {
                return Theme.statusError
            }
            if pipeline.stages.contains(where: { $0.status == .cancelled }) {
                return Theme.textTertiary
            }
        }
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        return Theme.accentSecondary
    }

    private func verificationTone(for status: VerificationStatus) -> Color {
        switch status {
        case .verified:
            return Theme.statusSuccess
        case .unverified:
            return Theme.statusWarning
        case .needsRetry:
            return Theme.statusError
        }
    }

    private func verificationIcon(for status: VerificationStatus) -> String {
        switch status {
        case .verified:
            return "checkmark.shield"
        case .unverified:
            return "questionmark.app.dashed"
        case .needsRetry:
            return "exclamationmark.shield"
        }
    }

    private func verificationFocusIcon(for status: VerificationStatus) -> String {
        switch status {
        case .verified:
            return "checkmark.seal"
        case .unverified:
            return "exclamationmark.bubble"
        case .needsRetry:
            return "exclamationmark.triangle"
        }
    }
}

struct MetaPill: View {
    let icon: String
    let text: String
    let isSelected: Bool
    var tone: Color? = nil
    var helpText: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(resolvedForegroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(resolvedBackgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(resolvedBorderColor, lineWidth: 1)
        )
        .help(helpText ?? text)
    }

    private var resolvedForegroundColor: Color {
        tone ?? (isSelected ? Theme.textSecondary : Theme.textTertiary)
    }

    private var resolvedBackgroundColor: Color {
        if let tone {
            return tone.opacity(isSelected ? 0.15 : 0.11)
        }
        return isSelected ? Theme.accentPrimary.opacity(0.10) : Theme.bgGlass.opacity(0.55)
    }

    private var resolvedBorderColor: Color {
        if let tone {
            return tone.opacity(isSelected ? 0.28 : 0.20)
        }
        return isSelected ? Theme.accentPrimary.opacity(0.18) : Theme.borderSubtle
    }
}

struct SidebarMetric: View {
    let value: String
    let label: String
    var isEmphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: isEmphasized ? .semibold : .medium, design: .rounded))
                .foregroundColor(isEmphasized ? Theme.textPrimary : Theme.textSecondary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass.opacity(isEmphasized ? 0.62 : 0.46))
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Input Area

struct InputArea: View {
    @Binding var text: String
    let isProcessing: Bool
    let canAcceptInput: Bool
    let pendingUserDecision: AgentEngine.PendingUserDecision?
    @FocusState.Binding var isFocused: Bool
    @Binding var workingDirectory: String?
    let modelName: String
    let providerName: String
    let onSubmit: () -> Bool
    var onStop: (() -> Void)? = nil
    
    @State private var composer = ComposerInputState()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SelectedFileTags(
                    selectedFiles: composer.selectedFiles,
                    workingDirectory: workingDirectory,
                    isRemovable: pendingUserDecision == nil,
                    removalDisabledReason: "请先完成当前确认，再调整文件上下文"
                ) { filePath in
                    composer.removeFileReference(filePath)
                    text = composer.text
                }
                
                // Multi-line text input
                TextField(inputPlaceholder, text: composerTextBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .foregroundColor(Theme.textPrimary)
                    .onSubmit {
                        submitIfPossible()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if let fileContextNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.statusWarning)
                        Text(fileContextNotice)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Bottom toolbar
                HStack(alignment: .center, spacing: 10) {
                    // Folder selector
                    FolderSelector(
                        workingDirectory: $workingDirectory,
                        isLocked: pendingUserDecision != nil,
                        lockHelpText: "请先完成当前确认，再调整工作目录"
                    )
                    
                    // File picker button
                    Button(action: {
                        composer.isShowingFilePicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "at")
                                .font(.system(size: 10, weight: .semibold))
                            Text("添加文件")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.bgGlass.opacity(0.72))
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(workingDirectory == nil || pendingUserDecision != nil)
                    .opacity(workingDirectory == nil || pendingUserDecision != nil ? 0.52 : 1)
                    .help(filePickerHelpText)

                    if !composer.selectedFiles.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10))
                            Text("\(composer.selectedFiles.count) 个文件")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.bgGlass.opacity(0.58))
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
                        )
                        .lineLimit(1)
                        .help(selectedFileSummaryHelp)
                    }

                    Spacer()

                    // Model badge
                    ModelBadge(modelName: modelName, providerName: providerName)
                        .frame(maxWidth: 180, alignment: .trailing)
                        .layoutPriority(0)

                    if let pendingDecisionHint, pendingUserDecision == nil {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.statusWarning)
                                .padding(.top, 1)

                            Text(pendingDecisionHint)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.statusWarning)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(pendingDecisionHint)
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                        .layoutPriority(2)
                    }

                    // Send / Stop button
                    if isProcessing && pendingUserDecision == nil {
                        // Stop button
                        Button(action: {
                            onStop?()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Theme.statusError.opacity(0.18))
                                    .frame(width: 32, height: 32)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.statusError)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("停止当前任务 (Esc)")
                        .keyboardShortcut(.escape, modifiers: [])
                    } else {
                        // Send button
                        Button(action: {
                            submitIfPossible()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(canSend ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.bgGlass))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(canSend ? .white : Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help(sendButtonHelp)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(Theme.bgInput.opacity(0.94))
            .cornerRadius(Theme.radiusXL)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXL)
                    .stroke(isFocused ? Theme.accentPrimary.opacity(0.45) : Theme.borderDefault, lineWidth: 1)
            )
            .shadow(color: Theme.shadowStrong.opacity(0.55), radius: 20, x: 0, y: 12)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(
            Theme.bgSecondary.opacity(0.70)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 1)
                }
        )
        .filePickerSheet(
            composer: composer,
            workingDirectory: workingDirectory
        ) {
            text = composer.text
        }
        .onAppear {
            composer.updateText(text)
        }
        .onChange(of: text) { _, newValue in
            if composer.text != newValue {
                composer.updateText(newValue)
            }
        }
        .onChange(of: workingDirectory) { _, newValue in
            composer.removeFileReferencesOutsideWorkingDirectory(newValue)
            text = composer.text
        }
    }

    private var canSend: Bool {
        composer.canSend && canAcceptInput
    }

    private var fileContextNotice: String? {
        guard workingDirectory == nil else { return nil }
        guard composer.text.hasSuffix("@") else { return nil }
        return "可以先写任务；需要添加文件上下文时，再选择工作目录。"
    }

    private var selectedFileSummaryHelp: String {
        composer.selectedFiles
            .map { PathSecurity.relativePath($0, from: workingDirectory) }
            .joined(separator: "\n")
    }

    private func submitIfPossible() {
        guard canSend else { return }
        text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        composer.updateText(text)
        let accepted = onSubmit()
        if accepted {
            composer.clearInput()
        } else {
            composer.updateText(text)
        }
    }

    private var composerTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                composer.updateTextFromUserInput(
                    newValue,
                    canOpenFilePicker: workingDirectory != nil && pendingUserDecision == nil
                )
            }
        )
    }

    private var pendingDecisionHint: String? {
        guard let pendingUserDecision else { return nil }
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "输入是/否，或直接写新任务"
        case .chooseExecutionModeForTask:
            return "输入是继续多 Agent，输入否改单 Agent，或直接写新任务"
        }
    }

    private var inputPlaceholder: String {
        guard let pendingUserDecision else {
            return "描述任务，Cmd+Return 发送，@ 添加上下文"
        }

        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "回复是/否，或直接写新任务"
        case .chooseExecutionModeForTask:
            return "回复是/否，或直接写新任务"
        }
    }

    private var sendButtonHelp: String {
        guard pendingUserDecision == nil else {
            return "提交回复或新任务 (Cmd+Return)"
        }
        return "发送 (Cmd+Return)"
    }

    private var filePickerHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整文件上下文"
        }
        if workingDirectory == nil {
            return "可以先写任务；需要添加文件上下文时，再选择工作目录"
        }
        return "添加文件上下文"
    }
}

// MARK: - Folder Selector

struct FolderSelector: View {
    @Binding var workingDirectory: String?
    var isLocked: Bool = false
    var lockHelpText: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button(action: pickFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.statusInfo)

                    Text(folderDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.bgGlass)
                .cornerRadius(Theme.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(folderHelpText)
            .disabled(isLocked)
            .opacity(isLocked ? 0.52 : 1)

            if workingDirectory != nil {
                Button(action: clearFolder) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Theme.bgGlass.opacity(0.72))
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(isLocked ? (lockHelpText ?? "当前状态下无法修改工作目录") : "清除工作目录")
                .disabled(isLocked)
                .opacity(isLocked ? 0.52 : 1)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: workingDirectory != nil)
    }

    private var folderDisplayName: String {
        guard let dir = workingDirectory else { return "选择目录" }
        return URL(fileURLWithPath: dir).lastPathComponent
    }

    private var folderHelpText: String {
        if isLocked, let lockHelpText {
            return lockHelpText
        }
        guard let dir = workingDirectory else { return "选择工作目录" }
        return "当前工作目录：\(dir)"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择工作目录"
        panel.prompt = "选择"

        if let dir = workingDirectory {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func clearFolder() {
        workingDirectory = nil
    }
}

// MARK: - Model Badge

struct ModelBadge: View {
    let modelName: String
    let providerName: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)

            Text(shortModelName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.bgGlass)
        .cornerRadius(Theme.radiusSM)
        .help(modelHelpText)
    }

    private var shortModelName: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未选择模型" }
        if trimmed.count > 20 {
            return String(trimmed.prefix(18)) + "..."
        }
        return trimmed
    }

    private var modelHelpText: String {
        let provider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (provider.isEmpty, model.isEmpty) {
        case (true, true):
            return "未选择模型"
        case (true, false):
            return model
        case (false, true):
            return provider
        case (false, false):
            return "\(provider) · \(model)"
        }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var isNonBlocking: Bool = false
    var canResumeTask: Bool = false
    var onResumeTask: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var settingsButtonTitle: String? = nil
    var settingsHelpText: String? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var isExpanded = false
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bannerIcon)
                .font(.system(size: 13))
                .foregroundColor(bannerTone)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(bannerTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text(statusBadgeText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(bannerTone)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(bannerTone.opacity(0.12))
                        .cornerRadius(Theme.radiusSM)
                }

                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(isExpanded ? 8 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if shouldShowExpandButton {
                        ErrorBannerUtilityButton(
                            icon: isExpanded ? "chevron.up" : "chevron.down",
                            tone: Theme.textSecondary,
                            helpText: isExpanded ? "收起错误详情" : "展开完整错误详情"
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isExpanded.toggle()
                            }
                        }
                    }

                    ErrorBannerUtilityButton(
                        icon: didCopy ? "checkmark" : "doc.on.doc",
                        tone: didCopy ? Theme.statusSuccess : Theme.textSecondary,
                        helpText: "复制完整错误信息",
                        action: copyErrorMessage
                    )

                    if canResumeTask, let onResumeTask {
                        Button(action: onResumeTask) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 9, weight: .bold))
                                Text("恢复任务")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.bgElevated.opacity(0.95))
                            .cornerRadius(Theme.radiusSM)
                        }
                        .buttonStyle(.plain)
                        .help("优先恢复当前草稿；如果没有草稿，则恢复最近一条真实任务")
                    }

                    if let onOpenSettings {
                        ErrorBannerUtilityButton(
                            icon: "gearshape",
                            tone: Theme.textSecondary,
                            helpText: settingsButtonTitle ?? settingsHelpText ?? "打开设置修复当前配置问题",
                            action: onOpenSettings
                        )
                        .help(settingsHelpText ?? "打开设置修复当前配置问题")
                    }

                    if let onDismiss {
                        ErrorBannerUtilityButton(
                            icon: "xmark",
                            tone: Theme.textTertiary,
                            helpText: "收起错误提示",
                            action: onDismiss
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgInput.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(bannerTone.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(bannerTone.opacity(0.8))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 16)
        .onChange(of: message) { _, _ in
            isExpanded = false
            didCopy = false
        }
    }

    private var shouldShowExpandButton: Bool {
        message.count > 120 || message.contains("\n")
    }

    private var bannerTone: Color {
        isNonBlocking ? Theme.statusWarning : Theme.statusError
    }

    private var bannerIcon: String {
        isNonBlocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var bannerTitle: String {
        isNonBlocking ? "部分流程已降级" : "本轮执行遇到问题"
    }

    private var statusBadgeText: String {
        if isNonBlocking {
            return "继续执行"
        }
        if canResumeTask {
            return onOpenSettings == nil ? "可恢复" : "可恢复 / 待配置"
        }
        return "已停止"
    }

    private func copyErrorMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}

private struct ErrorBannerUtilityButton: View {
    let icon: String
    let tone: Color
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tone)
                .frame(width: 28, height: 28)
                .background(Theme.bgGlass.opacity(0.7))
                .cornerRadius(Theme.radiusSM)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

// MARK: - Visual Effect View (kept for compatibility)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Helper Functions
