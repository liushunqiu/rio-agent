import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var agentEngine = AgentEngine()
    @StateObject private var conversationManager = ConversationManager()
    @State private var showingSettings = false
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
                    conversationManager.selectConversation(conversation)
                    agentEngine.loadConversation(conversation)
                },
                onDelete: { conversation in
                    conversationManager.deleteConversation(conversation)
                    if let current = conversationManager.currentConversation {
                        agentEngine.loadConversation(current)
                    } else {
                        agentEngine.clearConversation()
                    }
                },
                onNewConversation: {
                    let newConversation = conversationManager.createNewConversation()
                    agentEngine.workingDirectory = nil
                    agentEngine.loadConversation(newConversation)
                },
                onOpenSettings: {
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
                onSubmit: {
                    let text = conversationManager.currentConversation?.draftInput ?? ""
                    conversationManager.updateDraftInput("")
                    agentEngine.submitUserInput(text) {
                        conversationManager.updateCurrentConversation(
                            messages: agentEngine.messages,
                            workingDirectory: agentEngine.workingDirectory
                        )
                    }
                },
                onNewChatSubmit: { text in
                    // 如果没有当前对话，创建新对话
                    if conversationManager.currentConversation == nil {
                        let newConversation = conversationManager.createNewConversation()
                        agentEngine.loadConversation(newConversation)
                    }
                    agentEngine.submitUserInput(text) {
                        conversationManager.updateCurrentConversation(
                            messages: agentEngine.messages,
                            workingDirectory: agentEngine.workingDirectory
                        )
                    }
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
                runtimeRoles: agentEngine.runtimeModelRoles,
                messageCount: agentEngine.messages.count,
                estimatedTokens: agentEngine.getTotalTokensUsed(),
                contextWindow: AIProvider.contextWindow(for: agentEngine.primaryDisplayModelName),
                recentFiles: agentEngine.memory.session.recentFiles
            )
            .frame(width: 260)
        }
        .background(AppBackgroundView())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings, onDismiss: {
            // 不管用什么方式关闭设置面板，都保存一次
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
                memory: agentEngine.memory
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
                    workingDirectory: agentEngine.workingDirectory
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewConversation)) { _ in
            let newConversation = conversationManager.createNewConversation()
            agentEngine.workingDirectory = nil
            agentEngine.loadConversation(newConversation)
        }
    }

    private func resolveConfirmation(_ result: ConfirmationResult) {
        guard let continuation = confirmationContinuation else { return }
        confirmationContinuation = nil
        showingConfirmation = false
        continuation.resume(returning: result)
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

                Button(action: onNewConversation) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("新建对话")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accentPrimary.opacity(0.13))
                    .cornerRadius(Theme.radiusMD)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(Theme.accentPrimary.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
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
                                    onDelete(conversation)
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
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Theme.accentPrimary : Theme.textTertiary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(isSelected ? Theme.accentPrimary.opacity(0.13) : Color.clear)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Text(conversation.updatedAt, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()
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
}

// MARK: - Main Content

struct MainContentView: View {
    @ObservedObject var agentEngine: AgentEngine
    @Binding var inputText: String
    @Binding var showingSettings: Bool
    let onSubmit: () -> Void
    let onNewChatSubmit: ((String) -> Void)?

    @FocusState private var isInputFocused: Bool

    init(
        agentEngine: AgentEngine,
        inputText: Binding<String>,
        showingSettings: Binding<Bool>,
        onSubmit: @escaping () -> Void,
        onNewChatSubmit: ((String) -> Void)? = nil
    ) {
        self._agentEngine = ObservedObject(wrappedValue: agentEngine)
        self._inputText = inputText
        self._showingSettings = showingSettings
        self.onSubmit = onSubmit
        self.onNewChatSubmit = onNewChatSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            TopBar(
                showingSettings: $showingSettings,
                isPipelineActive: true,
                currentProvider: agentEngine.configuration.executionProvider
            )

            // Chat area
            if agentEngine.messages.isEmpty {
                NewChatPage(
                    onSubmit: { text in
                        onNewChatSubmit?(text)
                    },
                    workingDirectory: $agentEngine.workingDirectory
                )
                .transition(.opacity)
            } else {
                EnhancedChatView(
                    messages: agentEngine.messages,
                    isProcessing: agentEngine.isProcessing,
                    currentToolCallId: agentEngine.currentToolCallId,
                    currentPipeline: agentEngine.currentPipeline,
                    currentTaskPlan: nil
                )
                .transition(.opacity)
            }

            // Error banner
            if let error = agentEngine.error {
                ErrorBanner(message: error) {
                    agentEngine.error = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input area (only in chat mode)
            if !agentEngine.messages.isEmpty {
                InputArea(
                    text: $inputText,
                    isProcessing: agentEngine.isProcessing,
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
        .animation(.easeInOut(duration: 0.3), value: agentEngine.messages.isEmpty)
        .onAppear {
            isInputFocused = true
        }
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @Binding var showingSettings: Bool
    var isPipelineActive: Bool = true
    var currentProvider: AIProvider = .claude

    var body: some View {
        HStack(spacing: 12) {
            // Provider badge
            HStack(spacing: 6) {
                Image(systemName: currentProvider.icon)
                    .font(.system(size: 11))
                Text(currentProvider.displayName)
                    .font(.system(size: 11, weight: .medium))
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

            if isPipelineActive {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text("Pipeline")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.accentPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accentPrimary.opacity(0.1))
                .cornerRadius(Theme.radiusSM)
            }

            Spacer()

            Button(action: { showingSettings = true }) {
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
}

// MARK: - Input Area

struct InputArea: View {
    @Binding var text: String
    let isProcessing: Bool
    @FocusState.Binding var isFocused: Bool
    @Binding var workingDirectory: String?
    let modelName: String
    let providerName: String
    let onSubmit: () -> Void
    var onStop: (() -> Void)? = nil
    
    @State private var isShowingFilePicker = false
    @State private var selectedFiles: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // 已选择的文件标签
                if !selectedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedFiles, id: \.self) { filePath in
                                FileTag(filePath: filePath) {
                                    removeFileReference(filePath)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }
                }
                
                // Multi-line text input
                TextField("描述任务，Cmd+Return 发送，@ 添加上下文", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .foregroundColor(Theme.textPrimary)
                    .onSubmit {
                        submitIfPossible()
                    }
                    .onChange(of: text) { oldValue, newValue in
                        // 延迟执行，避免在视图更新期间修改状态
                        DispatchQueue.main.async {
                            handleInput(newValue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Bottom toolbar
                HStack(spacing: 10) {
                    // Folder selector
                    FolderSelector(workingDirectory: $workingDirectory)
                    
                    // File picker button
                    Button(action: {
                        isShowingFilePicker = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "at")
                                .font(.system(size: 11))
                            Text("添加文件")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.bgGlass)
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("添加文件上下文")

                    Spacer()

                    // Model badge
                    ModelBadge(modelName: modelName, providerName: providerName)

                    // Send / Stop button
                    if isProcessing {
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
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
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
        .sheet(isPresented: $isShowingFilePicker) {
            FilePickerView(workingDirectory: workingDirectory) { filePath in
                addFileReference(filePath)
            }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    private func submitIfPossible() {
        guard canSend else { return }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit()
        selectedFiles.removeAll()
    }
    
    private func handleInput(_ text: String) {
        selectedFiles = FileReferenceParser.fileReferences(in: text)

        if text.hasSuffix("@") {
            isShowingFilePicker = true
        }
    }
    
    private func addFileReference(_ filePath: String) {
        text = FileReferenceParser.appendingReference(to: text, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: text)
    }
    
    private func removeFileReference(_ filePath: String) {
        text = FileReferenceParser.removingReference(from: text, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: text)
    }
}

// MARK: - Folder Selector

struct FolderSelector: View {
    @Binding var workingDirectory: String?

    var body: some View {
        Button(action: pickFolder) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.statusInfo)

                Text(folderDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

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
        .help("选择工作目录")
    }

    private var folderDisplayName: String {
        guard let dir = workingDirectory else { return "选择目录" }
        return URL(fileURLWithPath: dir).lastPathComponent
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
    }

    private var shortModelName: String {
        // Trim long model names for display
        if modelName.count > 20 {
            return String(modelName.prefix(18)) + "..."
        }
        return modelName
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.statusError)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Theme.statusError)
                .lineLimit(4)

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.statusError.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.statusError.opacity(0.08))
        .overlay(
            VStack {
                Rectangle()
                    .fill(Theme.statusError.opacity(0.2))
                    .frame(height: 1)
                Spacer()
            }
        )
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
