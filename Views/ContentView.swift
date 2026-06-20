import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dependencies = ContentViewDependencies()
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
                sidebarState: conversationManager.sidebarState,
                runtimeState: sidebarRuntimeState,
                onSelect: { item in
                    guard let conversation = conversationManager.conversation(withID: item.id) else {
                        return
                    }
                    prepareForConversationContextChange()
                    guard let selectedConversation = conversationManager.selectConversation(conversation) else {
                        return
                    }
                    agentEngine.loadConversation(selectedConversation)
                },
                onDelete: { item in
                    guard let conversation = conversationManager.conversation(withID: item.id) else {
                        return
                    }
                    let deletesCurrentConversation = conversationManager.currentConversation?.id == conversation.id
                    if deletesCurrentConversation {
                        prepareForConversationContextChange()
                    }

                    let nextConversation = conversationManager.deleteConversation(conversation)

                    guard deletesCurrentConversation else { return }

                    if let current = nextConversation {
                        agentEngine.loadConversation(current)
                    } else {
                        agentEngine.clearConversation()
                    }
                },
                onNewConversation: requestNewConversation,
                onOpenSettings: {
                    openSettings()
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
                runtimeState: mainContentRuntimeState,
                inputText: conversationDraftBinding,
                workingDirectory: Binding(
                    get: { agentEngine.workingDirectory },
                    set: { agentEngine.workingDirectory = $0 }
                ),
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
            ContextPanelHost(agentEngine: agentEngine)
            .frame(width: 260)
        }
        .background(
            RuntimeStateBridge(
                agentEngine: agentEngine,
                conversationManager: conversationManager,
                sidebarRuntimeState: sidebarRuntimeState
            )
        )
        .background(
            MainContentRuntimeBridge(
                agentEngine: agentEngine,
                runtimeState: mainContentRuntimeState
            )
        )
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
            // 启动时加载已保存的当前对话，避免新消息覆盖旧对话。
            // 对话已改为后台异步加载，确保数据就绪后再灌入引擎，避免首屏空跑与二次重绘卡顿。
            conversationManager.performAfterInitialLoad { [weak agentEngine, weak conversationManager] in
                guard let agentEngine, let conversationManager else { return }
                if let current = conversationManager.currentConversation {
                    agentEngine.loadConversation(current)
                }
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
            requestNewConversation()
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

    private var isConversationNavigationLocked: Bool {
        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil
    }

    private var isRuntimeConfigurationLocked: Bool {
        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil
    }

    private func openSettings(tab: SettingsTab = .ai, launchContext: SettingsLaunchContext? = nil) {
        guard !isRuntimeConfigurationLocked else {
            agentEngine.error = "当前任务运行中，完成或停止后再修改设置。"
            return
        }

        settingsInitialTab = tab
        settingsLaunchContext = launchContext
        showingSettings = true
    }

    private func requestNewConversation() {
        guard !isConversationNavigationLocked else {
            agentEngine.error = "当前任务运行中，完成或停止后再新建会话。"
            return
        }

        prepareForConversationContextChange()
        let newConversation = conversationManager.createNewConversation(
            workingDirectory: agentEngine.workingDirectory
        )
        agentEngine.loadConversation(newConversation)
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
            set: { newValue in
                if conversationManager.currentConversation == nil {
                    guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    _ = conversationManager.createNewConversation(
                        workingDirectory: agentEngine.workingDirectory
                    )
                }
                conversationManager.updateDraftInput(newValue)
            }
        )
    }

    private var agentEngine: AgentEngine {
        dependencies.agentEngine
    }

    private var conversationManager: ConversationManager {
        dependencies.conversationManager
    }

    private var sidebarRuntimeState: SidebarRuntimeState {
        dependencies.sidebarRuntimeState
    }

    private var mainContentRuntimeState: MainContentRuntimeState {
        dependencies.mainContentRuntimeState
    }
}

@MainActor
private final class ContentViewDependencies: ObservableObject {
    let agentEngine = AgentEngine()
    let conversationManager = ConversationManager()
    let sidebarRuntimeState = SidebarRuntimeState()
    let mainContentRuntimeState = MainContentRuntimeState()
}

@MainActor
final class SidebarRuntimeState: ObservableObject {
    @Published private(set) var isNavigationLocked = false
    @Published private(set) var isSettingsLocked = false

    func update(isProcessing: Bool, pendingUserDecision: AgentEngine.PendingUserDecision?) {
        let isLocked = isProcessing && pendingUserDecision == nil
        guard isNavigationLocked != isLocked || isSettingsLocked != isLocked else { return }
        isNavigationLocked = isLocked
        isSettingsLocked = isLocked
    }
}

private struct RuntimeStateBridge: View {
    @ObservedObject var agentEngine: AgentEngine
    let conversationManager: ConversationManager
    let sidebarRuntimeState: SidebarRuntimeState

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: syncRuntimeState)
            .onChange(of: agentEngine.isProcessing) { _, _ in
                syncRuntimeState()
            }
            .onChange(of: agentEngine.pendingUserDecision) { _, _ in
                syncRuntimeState()
            }
            .onChange(of: agentEngine.workingDirectory) { _, newValue in
                conversationManager.updateWorkingDirectory(newValue)
            }
    }

    private func syncRuntimeState() {
        sidebarRuntimeState.update(
            isProcessing: agentEngine.isProcessing,
            pendingUserDecision: agentEngine.pendingUserDecision
        )
    }
}

private struct ContextPanelHost: View {
    @ObservedObject var agentEngine: AgentEngine

    var body: some View {
        let snapshot = ContextPanelSnapshot(agentEngine: agentEngine)

        ContextPanel(
            singleAgentPlan: agentEngine.currentSingleAgentPlan,
            taskPlan: agentEngine.currentTaskPlan,
            pipeline: agentEngine.currentPipeline,
            singleAgentVerification: agentEngine.singleAgentVerificationSummary,
            pendingUserDecision: agentEngine.pendingUserDecision,
            runtimeRoles: snapshot.runtimeRoles,
            messageCount: snapshot.visibleMessageCount,
            workingDirectory: snapshot.workingDirectory,
            estimatedTokens: snapshot.estimatedTokens,
            contextWindow: snapshot.contextWindow,
            recentFiles: snapshot.recentFiles
        )
    }
}

@MainActor
fileprivate final class MainContentRuntimeState: ObservableObject {
    @Published fileprivate(set) var snapshot = MainContentRuntimeSnapshot.empty

    fileprivate func update(snapshot newSnapshot: MainContentRuntimeSnapshot) {
        guard snapshot.renderSignature != newSnapshot.renderSignature else { return }
        snapshot = newSnapshot
    }
}

private struct MainContentRuntimeBridge: View {
    @ObservedObject var agentEngine: AgentEngine
    @ObservedObject var runtimeState: MainContentRuntimeState

    var body: some View {
        let snapshot = MainContentRuntimeSnapshot(agentEngine: agentEngine)

        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                runtimeState.update(snapshot: snapshot)
            }
            .onChange(of: snapshot.renderSignature) { _, _ in
                runtimeState.update(snapshot: snapshot)
            }
    }
}

@MainActor
private struct ContextPanelSnapshot {
    let runtimeRoles: [AgentEngine.RuntimeModelRole]
    let visibleMessageCount: Int
    let workingDirectory: String?
    let estimatedTokens: Int
    let contextWindow: Int
    let recentFiles: [String]

    init(agentEngine: AgentEngine) {
        runtimeRoles = agentEngine.runtimeModelRoles
        visibleMessageCount = Self.visibleMessageCount(in: agentEngine.messages)
        workingDirectory = agentEngine.workingDirectory
        estimatedTokens = agentEngine.getTotalTokensUsed()
        contextWindow = AIProvider.contextWindow(for: Self.primaryModelName(
            runtimeRoles: runtimeRoles,
            fallback: agentEngine.configuration.executionModel
        ))
        recentFiles = agentEngine.memory.session.recentFiles
    }

    private static func visibleMessageCount(in messages: [Message]) -> Int {
        messages.reduce(0) { count, message in
            count + (message.isVisibleInTranscript ? 1 : 0)
        }
    }

    private static func primaryModelName(
        runtimeRoles: [AgentEngine.RuntimeModelRole],
        fallback: String
    ) -> String {
        runtimeRoles.first(where: \.isActive)?.modelName
            ?? runtimeRoles.first?.modelName
            ?? fallback
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
    @ObservedObject var sidebarState: SidebarState
    @ObservedObject var runtimeState: SidebarRuntimeState
    let onSelect: (ConversationSidebarItem) -> Void
    let onDelete: (ConversationSidebarItem) -> Void
    let onNewConversation: () -> Void
    let onOpenSettings: () -> Void

    @State private var pendingDeleteItem: ConversationSidebarItem?

    var body: some View {
        let sidebarItems = sidebarState.items
        let selectedConversationID = sidebarState.selectedConversationID

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

                    Button(action: {
                        guard !isNavigationLocked else { return }
                        onNewConversation()
                    }) {
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
                    .disabled(isNavigationLocked)
                    .opacity(isNavigationLocked ? 0.52 : 1)
                    .help(newConversationHelpText)
                }

                if isNavigationLocked {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.statusInfo)
                            .padding(.top, 1)
                        Text("当前任务运行中，完成或停止后再切换会话。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.bgGlass.opacity(0.48))
                    .cornerRadius(Theme.radiusMD)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(Theme.statusInfo.opacity(0.14), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            Group {
                if sidebarItems.isEmpty {
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
                    SidebarConversationListView(
                        items: sidebarItems,
                        selectedID: selectedConversationID,
                        isNavigationLocked: isNavigationLocked,
                        onSelect: { item in
                            onSelect(item)
                        },
                        onDelete: { item in
                            pendingDeleteItem = item
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                Button(action: {
                    guard !isSettingsLocked else { return }
                    onOpenSettings()
                }) {
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
                .disabled(isSettingsLocked)
                .opacity(isSettingsLocked ? 0.52 : 1)
                .help(settingsHelpText)
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
                pendingDeleteItem = nil
            }
            Button("删除", role: .destructive) {
                guard !isNavigationLocked else {
                    pendingDeleteItem = nil
                    return
                }
                if let pendingDeleteItem {
                    onDelete(pendingDeleteItem)
                }
                pendingDeleteItem = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .animation(.easeInOut(duration: 0.16), value: isNavigationLocked)
    }

    private var newConversationHelpText: String {
        isNavigationLocked ? "当前任务运行中，完成或停止后再新建会话" : "新建会话"
    }

    private var settingsHelpText: String {
        isSettingsLocked ? "当前任务运行中，完成或停止后再修改设置" : "设置"
    }

    private var isNavigationLocked: Bool {
        runtimeState.isNavigationLocked
    }

    private var isSettingsLocked: Bool {
        runtimeState.isSettingsLocked
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteItem != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteItem = nil
                }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        guard let item = pendingDeleteItem else {
            return "这个操作无法撤销。"
        }

        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "未命名对话" : title
        let draftSuffix = item.hasDraft ? "，并包含未发送草稿" : ""
        return "将删除「\(displayTitle)」\(draftSuffix)。这个操作无法撤销。"
    }

}

// MARK: - Main Content

private struct MainContentView: View {
    let agentEngine: AgentEngine
    @ObservedObject var runtimeState: MainContentRuntimeState
    @Binding var inputText: String
    @Binding var workingDirectory: String?
    @Binding var showingSettings: Bool
    @Binding var settingsInitialTab: SettingsTab
    @Binding var settingsLaunchContext: SettingsLaunchContext?
    let onSubmit: () -> Bool
    let onNewChatSubmit: ((String) -> Bool)?

    @FocusState private var isInputFocused: Bool

    init(
        agentEngine: AgentEngine,
        runtimeState: MainContentRuntimeState,
        inputText: Binding<String>,
        workingDirectory: Binding<String?>,
        showingSettings: Binding<Bool>,
        settingsInitialTab: Binding<SettingsTab>,
        settingsLaunchContext: Binding<SettingsLaunchContext?>,
        onSubmit: @escaping () -> Bool,
        onNewChatSubmit: ((String) -> Bool)? = nil
    ) {
        self.agentEngine = agentEngine
        self._runtimeState = ObservedObject(wrappedValue: runtimeState)
        self._inputText = inputText
        self._workingDirectory = workingDirectory
        self._showingSettings = showingSettings
        self._settingsInitialTab = settingsInitialTab
        self._settingsLaunchContext = settingsLaunchContext
        self.onSubmit = onSubmit
        self.onNewChatSubmit = onNewChatSubmit
    }

    var body: some View {
        let _ = (
            currentTaskPlan: agentEngine.currentTaskPlan,
            currentPipeline: agentEngine.currentPipeline,
            pendingUserDecision: agentEngine.pendingUserDecision,
            singleAgentVerification: agentEngine.singleAgentVerificationSummary
        )
        let snapshot = runtimeState.snapshot
        let hasVisibleTranscript = snapshot.visibleMessageCount > 0
        let hasInternalActivity = !hasVisibleTranscript && (
            snapshot.isProcessing ||
            snapshot.pendingUserDecision != nil
        )
        let shouldShowInputArea = hasVisibleTranscript || snapshot.pendingUserDecision != nil

        VStack(spacing: 0) {
            // Top bar
            TopBar(
                showingSettings: $showingSettings,
                settingsInitialTab: $settingsInitialTab,
                settingsLaunchContext: $settingsLaunchContext,
                pipeline: snapshot.currentPipeline,
                singleAgentPlan: snapshot.currentSingleAgentPlan,
                singleAgentVerification: agentEngine.singleAgentVerificationSummary,
                currentTaskPlan: agentEngine.currentTaskPlan,
                pendingUserDecision: agentEngine.pendingUserDecision,
                isSettingsLocked: snapshot.isRuntimeConfigurationLocked,
                currentProvider: snapshot.currentProvider,
                currentModelName: snapshot.primaryModelName,
                currentWorkingDirectory: snapshot.workingDirectory,
                messageCount: snapshot.visibleMessageCount,
                prefersCompactRuntimeChrome: hasVisibleTranscript && (
                    agentEngine.currentPipeline != nil ||
                    agentEngine.pendingUserDecision != nil ||
                    agentEngine.singleAgentVerificationSummary != nil
                )
            )

            // Chat area
            if hasVisibleTranscript {
                EnhancedChatView(
                    messages: snapshot.messages,
                    isProcessing: snapshot.isProcessing,
                    currentToolCallId: snapshot.currentToolCallId,
                    currentPipeline: agentEngine.currentPipeline,
                    singleAgentVerification: agentEngine.singleAgentVerificationSummary,
                    currentTaskPlan: agentEngine.currentTaskPlan,
                    pendingUserDecision: agentEngine.pendingUserDecision
                )
                .transition(.opacity)
            } else if hasInternalActivity {
                InternalActivityView(
                    isProcessing: snapshot.isProcessing,
                    pendingUserDecision: snapshot.pendingUserDecision,
                    workingDirectory: snapshot.workingDirectory,
                    onStop: snapshot.isProcessing && snapshot.pendingUserDecision == nil ? {
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
                    workingDirectory: $workingDirectory,
                    modelName: snapshot.primaryModelName,
                    providerName: snapshot.primaryProviderName,
                    canAcceptInput: snapshot.canAcceptInput,
                    pendingUserDecision: snapshot.pendingUserDecision
                )
                .transition(.opacity)
            }

            // Error banner
            if let error = snapshot.error {
                ErrorBanner(
                    message: error,
                    isNonBlocking: error.contains("已继续执行标准流程"),
                    canResumeTask: resumableTaskInput != nil,
                    onResumeTask: restoreResumableTaskInput,
                    onOpenSettings: settingsShortcutAction(for: error, recoveryContext: agentEngine.errorRecoveryContext),
                    settingsButtonTitle: settingsShortcutTitle(for: error, recoveryContext: agentEngine.errorRecoveryContext),
                    settingsHelpText: settingsShortcutHelpText(for: error, recoveryContext: snapshot.errorRecoveryContext),
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
                    isProcessing: snapshot.isProcessing,
                    canAcceptInput: snapshot.canAcceptInput,
                    pendingUserDecision: snapshot.pendingUserDecision,
                    isFocused: $isInputFocused,
                    workingDirectory: $workingDirectory,
                    modelName: snapshot.primaryModelName,
                    providerName: snapshot.primaryProviderName,
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

    private var isRuntimeConfigurationLocked: Bool {
        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil
    }

    private var resumableTaskInput: String? {
        let draft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            return draft
        }

        return runtimeState.snapshot.messages
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
            guard !isRuntimeConfigurationLocked else {
                agentEngine.error = "当前任务运行中，完成或停止后再修改设置。"
                return
            }

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

@MainActor
private struct MainContentRuntimeSnapshot {
    struct RenderSignature: Equatable {
        let messages: MessagesSignature
        let isProcessing: Bool
        let currentToolCallId: String?
        let currentPipeline: PipelineSignature
        let currentSingleAgentPlan: SingleAgentPlanSignature
        let currentTaskPlan: TaskPlanSignature
        let singleAgentVerification: VerificationSignature
        let pendingUserDecision: AgentEngine.PendingUserDecision?
        let workingDirectory: String?
        let canAcceptInput: Bool
        let error: String?
        let errorRecoveryContext: ErrorRecoveryContext?
        let currentProvider: AIProvider
        let primaryModelName: String
        let primaryProviderName: String
    }

    struct MessagesSignature: Equatable {
        let totalCount: Int
        let visibleCount: Int
        let totalContentUTF8: Int
        let totalThinkingUTF8: Int
        let streamingCount: Int
        let totalToolCalls: Int
        let totalToolResults: Int
        let finalAnswerCount: Int
        let lastMessageID: UUID?
        let lastContentUTF8: Int
        let lastThinkingUTF8: Int
        let lastStreaming: Bool

        init(messages: [Message]) {
            totalCount = messages.count
            visibleCount = messages.reduce(0) { $0 + ($1.isVisibleInTranscript ? 1 : 0) }
            totalContentUTF8 = messages.reduce(0) { $0 + $1.content.utf8.count }
            totalThinkingUTF8 = messages.reduce(0) { $0 + ($1.thinkingContent?.utf8.count ?? 0) }
            streamingCount = messages.reduce(0) { $0 + ($1.isStreaming ? 1 : 0) }
            totalToolCalls = messages.reduce(0) { $0 + ($1.toolCalls?.count ?? 0) }
            totalToolResults = messages.reduce(0) { $0 + ($1.toolResults?.count ?? 0) }
            finalAnswerCount = messages.reduce(0) { $0 + ($1.isFinalAnswer ? 1 : 0) }
            let lastMessage = messages.last
            lastMessageID = lastMessage?.id
            lastContentUTF8 = lastMessage?.content.utf8.count ?? 0
            lastThinkingUTF8 = lastMessage?.thinkingContent?.utf8.count ?? 0
            lastStreaming = lastMessage?.isStreaming ?? false
        }
    }

    struct PipelineSignature: Equatable {
        let stageCount: Int
        let runningStageCount: Int
        let failedStageCount: Int
        let cancelledStageCount: Int
        let completedStageCount: Int
        let totalSubstepCount: Int

        init(pipeline: ExecutionPipeline?) {
            guard let pipeline else {
                stageCount = 0
                runningStageCount = 0
                failedStageCount = 0
                cancelledStageCount = 0
                completedStageCount = 0
                totalSubstepCount = 0
                return
            }

            stageCount = pipeline.stages.count
            runningStageCount = pipeline.stages.reduce(0) { $0 + ($1.status == .running ? 1 : 0) }
            failedStageCount = pipeline.stages.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) }
            cancelledStageCount = pipeline.stages.reduce(0) { $0 + ($1.status == .cancelled ? 1 : 0) }
            completedStageCount = pipeline.stages.reduce(0) { $0 + ($1.status == .completed ? 1 : 0) }
            totalSubstepCount = pipeline.stages.reduce(0) { $0 + $1.substeps.count }
        }
    }

    struct SingleAgentPlanSignature: Equatable {
        let stepCount: Int
        let currentStep: Int
        let status: TaskPlanStatus?
        let taskUTF8: Int

        init(plan: AgentEngine.SingleAgentPlan?) {
            stepCount = plan?.steps.count ?? 0
            currentStep = plan?.currentStep ?? 0
            status = plan?.status
            taskUTF8 = plan?.originalTask.utf8.count ?? 0
        }
    }

    struct TaskPlanSignature: Equatable {
        let subTaskCount: Int
        let attentionCount: Int
        let runningCount: Int
        let failedCount: Int
        let retryNeededCount: Int
        let totalRetryCount: Int
        let status: TaskPlanStatus?

        init(plan: TaskPlan?) {
            guard let plan else {
                subTaskCount = 0
                attentionCount = 0
                runningCount = 0
                failedCount = 0
                retryNeededCount = 0
                totalRetryCount = 0
                status = nil
                return
            }

            subTaskCount = plan.subTasks.count
            attentionCount = plan.subTasks.reduce(0) { $0 + ($1.needsAttention ? 1 : 0) }
            runningCount = plan.subTasks.reduce(0) { $0 + ($1.status == .running ? 1 : 0) }
            failedCount = plan.subTasks.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) }
            retryNeededCount = plan.subTasks.reduce(0) { $0 + ($1.verificationStatus == .needsRetry ? 1 : 0) }
            totalRetryCount = plan.subTasks.reduce(0) { $0 + $1.retryCount }
            status = plan.status
        }
    }

    struct VerificationSignature: Equatable {
        let status: VerificationStatus?
        let summaryUTF8: Int

        init(outcome: VerifierService.VerificationOutcome?) {
            status = outcome?.status
            summaryUTF8 = outcome?.summary.utf8.count ?? 0
        }
    }

    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let currentPipeline: ExecutionPipeline?
    let currentSingleAgentPlan: AgentEngine.SingleAgentPlan?
    let currentTaskPlan: TaskPlan?
    let singleAgentVerification: VerifierService.VerificationOutcome?
    let pendingUserDecision: AgentEngine.PendingUserDecision?
    let workingDirectory: String?
    let canAcceptInput: Bool
    let error: String?
    let errorRecoveryContext: ErrorRecoveryContext?
    let visibleMessageCount: Int
    let isRuntimeConfigurationLocked: Bool
    let currentProvider: AIProvider
    let primaryModelName: String
    let primaryProviderName: String
    let renderSignature: RenderSignature

    static let empty = MainContentRuntimeSnapshot(
        messages: [],
        isProcessing: false,
        currentToolCallId: nil,
        currentPipeline: nil,
        currentSingleAgentPlan: nil,
        currentTaskPlan:
            nil,
        singleAgentVerification: nil,
        pendingUserDecision: nil,
        workingDirectory: nil,
        canAcceptInput: true,
        error: nil,
        errorRecoveryContext: nil,
        visibleMessageCount: 0,
        isRuntimeConfigurationLocked: false,
        currentProvider: .claude,
        primaryModelName: "",
        primaryProviderName: "",
        renderSignature: RenderSignature(
            messages: MessagesSignature(messages: []),
            isProcessing: false,
            currentToolCallId: nil,
            currentPipeline: PipelineSignature(pipeline: nil),
            currentSingleAgentPlan: SingleAgentPlanSignature(plan: nil),
            currentTaskPlan: TaskPlanSignature(plan: nil),
            singleAgentVerification: VerificationSignature(outcome: nil),
            pendingUserDecision: nil,
            workingDirectory: nil,
            canAcceptInput: true,
            error: nil,
            errorRecoveryContext: nil,
            currentProvider: .claude,
            primaryModelName: "",
            primaryProviderName: ""
        )
    )

    init(agentEngine: AgentEngine) {
        let runtimeRoles = agentEngine.runtimeModelRoles
        let messages = agentEngine.messages
        let pendingUserDecision = agentEngine.pendingUserDecision
        let visibleMessageCount = Self.visibleMessageCount(in: messages)
        let currentProvider = agentEngine.configuration.executionProvider
        let primaryModelName = runtimeRoles.first(where: \.isActive)?.modelName
            ?? runtimeRoles.first?.modelName
            ?? agentEngine.configuration.executionModel
        let primaryProviderName = runtimeRoles.first(where: \.isActive)?.providerName
            ?? runtimeRoles.first?.providerName
            ?? agentEngine.configuration.executionProvider.displayName

        self.messages = messages
        isProcessing = agentEngine.isProcessing
        currentToolCallId = agentEngine.currentToolCallId
        currentPipeline = agentEngine.currentPipeline
        currentSingleAgentPlan = agentEngine.currentSingleAgentPlan
        currentTaskPlan = agentEngine.currentTaskPlan
        singleAgentVerification = agentEngine.singleAgentVerificationSummary
        self.pendingUserDecision = pendingUserDecision
        workingDirectory = agentEngine.workingDirectory
        canAcceptInput = agentEngine.canAcceptUserInput
        error = agentEngine.error
        errorRecoveryContext = agentEngine.errorRecoveryContext
        self.visibleMessageCount = visibleMessageCount
        isRuntimeConfigurationLocked = agentEngine.isProcessing && pendingUserDecision == nil
        self.currentProvider = currentProvider
        self.primaryModelName = primaryModelName
        self.primaryProviderName = primaryProviderName
        renderSignature = RenderSignature(
            messages: MessagesSignature(messages: messages),
            isProcessing: agentEngine.isProcessing,
            currentToolCallId: agentEngine.currentToolCallId,
            currentPipeline: PipelineSignature(pipeline: agentEngine.currentPipeline),
            currentSingleAgentPlan: SingleAgentPlanSignature(plan: agentEngine.currentSingleAgentPlan),
            currentTaskPlan: TaskPlanSignature(plan: agentEngine.currentTaskPlan),
            singleAgentVerification: VerificationSignature(outcome: agentEngine.singleAgentVerificationSummary),
            pendingUserDecision: pendingUserDecision,
            workingDirectory: agentEngine.workingDirectory,
            canAcceptInput: agentEngine.canAcceptUserInput,
            error: agentEngine.error,
            errorRecoveryContext: agentEngine.errorRecoveryContext,
            currentProvider: currentProvider,
            primaryModelName: primaryModelName,
            primaryProviderName: primaryProviderName
        )
    }

    private init(
        messages: [Message],
        isProcessing: Bool,
        currentToolCallId: String?,
        currentPipeline: ExecutionPipeline?,
        currentSingleAgentPlan: AgentEngine.SingleAgentPlan?,
        currentTaskPlan: TaskPlan?,
        singleAgentVerification: VerifierService.VerificationOutcome?,
        pendingUserDecision: AgentEngine.PendingUserDecision?,
        workingDirectory: String?,
        canAcceptInput: Bool,
        error: String?,
        errorRecoveryContext: ErrorRecoveryContext?,
        visibleMessageCount: Int,
        isRuntimeConfigurationLocked: Bool,
        currentProvider: AIProvider,
        primaryModelName: String,
        primaryProviderName: String,
        renderSignature: RenderSignature
    ) {
        self.messages = messages
        self.isProcessing = isProcessing
        self.currentToolCallId = currentToolCallId
        self.currentPipeline = currentPipeline
        self.currentSingleAgentPlan = currentSingleAgentPlan
        self.currentTaskPlan = currentTaskPlan
        self.singleAgentVerification = singleAgentVerification
        self.pendingUserDecision = pendingUserDecision
        self.workingDirectory = workingDirectory
        self.canAcceptInput = canAcceptInput
        self.error = error
        self.errorRecoveryContext = errorRecoveryContext
        self.visibleMessageCount = visibleMessageCount
        self.isRuntimeConfigurationLocked = isRuntimeConfigurationLocked
        self.currentProvider = currentProvider
        self.primaryModelName = primaryModelName
        self.primaryProviderName = primaryProviderName
        self.renderSignature = renderSignature
    }

    private static func visibleMessageCount(in messages: [Message]) -> Int {
        messages.reduce(0) { count, message in
            count + (message.isVisibleInTranscript ? 1 : 0)
        }
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
    var isSettingsLocked = false
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
                guard !isSettingsLocked else { return }
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
            .disabled(isSettingsLocked)
            .opacity(isSettingsLocked ? 0.52 : 1)
            .hoverHighlight()
            .help(settingsHelpText)
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

    private var settingsHelpText: String {
        isSettingsLocked ? "当前任务运行中，完成或停止后再修改设置" : "设置"
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
        let failed = plan.subTasks.filter { $0.resolvedFailureSource != nil }.count
        let cancelled = plan.subTasks.filter { $0.status == .cancelled }.count
        var parts = ["\(completed)/\(plan.subTasks.count) 子任务"]
        if let failedSubTask = prioritizedFailureSubTask(in: plan) {
            let label = failureSourceLabel(for: failedSubTask)
            parts.append("\(label) \(failed)")
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
        if let currentTaskPlan {
            if prioritizedFailureSubTask(in: currentTaskPlan) != nil {
                return Theme.statusError
            }
            if currentTaskPlan.subTasks.contains(where: { $0.status == .cancelled }) {
                return Theme.textTertiary
            }
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
            if let failedSubTask = prioritizedFailureSubTask(in: currentTaskPlan) {
                return failureSourceLabel(for: failedSubTask)
            }
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
        if pendingUserDecision != nil {
            return "questionmark.circle"
        }
        if let currentTaskPlan,
           let failedSubTask = prioritizedFailureSubTask(in: currentTaskPlan) {
            return failureSourceIcon(for: failedSubTask)
        }

        if let pipeline {
            if pipeline.stages.contains(where: { $0.status == .failed }) {
                return "exclamationmark.triangle"
            }
            if pipeline.stages.contains(where: { $0.status == .cancelled }) {
                return "slash.circle"
            }
        }
        return "scope"
    }

    private var focusColor: Color {
        if let singleAgentVerification {
            return verificationTone(for: singleAgentVerification.status)
        }
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if let currentTaskPlan,
           prioritizedFailureSubTask(in: currentTaskPlan) != nil {
            return Theme.statusError
        }

        if let pipeline {
            if pipeline.stages.contains(where: { $0.status == .failed }) {
                return Theme.statusError
            }
            if pipeline.stages.contains(where: { $0.status == .cancelled }) {
                return Theme.textTertiary
            }
        }
        return Theme.accentSecondary
    }

    private func prioritizedFailureSubTask(in plan: TaskPlan) -> SubTask? {
        plan.subTasks.first(where: { $0.status == .failed }) ??
            plan.subTasks.first(where: { $0.verificationStatus == .needsRetry })
    }

    private func failureSourceLabel(for subTask: SubTask) -> String {
        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "依赖阻塞"
        case .verification?:
            return "验证未通过"
        case .execution?, .none:
            return "执行失败"
        }
    }

    private func failureSourceIcon(for subTask: SubTask) -> String {
        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "link.badge.plus"
        case .verification?:
            return "checkmark.shield.fill"
        case .execution?, .none:
            return "exclamationmark.triangle"
        }
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
                    isRemovable: canEditContext,
                    removalDisabledReason: fileContextLockHelpText
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
                        isLocked: !canEditContext,
                        lockHelpText: workingDirectoryLockHelpText
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
                    .disabled(workingDirectory == nil || !canEditContext)
                    .opacity(workingDirectory == nil || !canEditContext ? 0.52 : 1)
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
            workingDirectory: workingDirectory,
            isEnabled: canEditContext
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
        .onChange(of: canEditContext) { _, canEditContext in
            if !canEditContext {
                composer.isShowingFilePicker = false
            }
        }
    }

    private var canSend: Bool {
        composer.canSend && canAcceptInput
    }

    private var canEditContext: Bool {
        canAcceptInput && pendingUserDecision == nil
    }

    private var fileContextNotice: String? {
        guard composer.text.hasSuffix("@") else { return nil }
        guard canEditContext else { return fileContextLockHelpText }
        guard workingDirectory == nil else { return nil }
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
                    canOpenFilePicker: workingDirectory != nil && canEditContext
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
            if !canAcceptInput {
                return "当前任务执行中，完成或停止后可继续输入"
            }
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
        if !canAcceptInput {
            return "当前任务执行中，完成或停止后可继续发送"
        }
        return "发送 (Cmd+Return)"
    }

    private var filePickerHelpText: String {
        if !canEditContext {
            return fileContextLockHelpText
        }
        if workingDirectory == nil {
            return "可以先写任务；需要添加文件上下文时，再选择工作目录"
        }
        return "添加文件上下文"
    }

    private var fileContextLockHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整文件上下文"
        }
        if !canAcceptInput {
            return "当前任务正在执行，完成或停止后再调整文件上下文"
        }
        return "当前状态下无法调整文件上下文"
    }

    private var workingDirectoryLockHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整工作目录"
        }
        if !canAcceptInput {
            return "当前任务正在执行，完成或停止后再调整工作目录"
        }
        return "当前状态下无法调整工作目录"
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
        guard !isLocked else { return }

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
        guard !isLocked else { return }
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
    @State private var copyResetID: UUID?

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

                ErrorBannerActions(
                    shouldShowExpandButton: shouldShowExpandButton,
                    isExpanded: isExpanded,
                    didCopy: didCopy,
                    canResumeTask: canResumeTask,
                    onResumeTask: onResumeTask,
                    onOpenSettings: onOpenSettings,
                    settingsButtonTitle: settingsButtonTitle,
                    settingsHelpText: settingsHelpText,
                    onDismiss: onDismiss,
                    onToggleExpanded: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    },
                    onCopy: copyErrorMessage
                )
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
            copyResetID = nil
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
        let resetID = UUID()
        copyResetID = resetID
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard copyResetID == resetID else { return }
            didCopy = false
            copyResetID = nil
        }
    }
}

private struct ErrorBannerActions: View {
    let shouldShowExpandButton: Bool
    let isExpanded: Bool
    let didCopy: Bool
    let canResumeTask: Bool
    let onResumeTask: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let settingsButtonTitle: String?
    let settingsHelpText: String?
    let onDismiss: (() -> Void)?
    let onToggleExpanded: () -> Void
    let onCopy: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                actionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if shouldShowExpandButton {
            ErrorBannerUtilityButton(
                icon: isExpanded ? "chevron.up" : "chevron.down",
                tone: Theme.textSecondary,
                helpText: isExpanded ? "收起错误详情" : "展开完整错误详情",
                action: onToggleExpanded
            )
        }

        ErrorBannerUtilityButton(
            icon: didCopy ? "checkmark" : "doc.on.doc",
            tone: didCopy ? Theme.statusSuccess : Theme.textSecondary,
            helpText: "复制完整错误信息",
            action: onCopy
        )

        if canResumeTask, let onResumeTask {
            Button(action: onResumeTask) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .bold))
                    Text("恢复任务")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
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
