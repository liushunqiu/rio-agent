import SwiftUI

// MARK: - Enhanced Message Bubble

struct EnhancedMessageBubble: View {
    let message: Message
    let isToolExecuting: Bool
    let currentToolCallId: String?
    let toolResultsById: [String: ToolResult]

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            MessageSourceHeader(message: message)

            // Thinking card (separate from reply, shown first)
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                ThinkingCard(
                    content: thinking,
                    duration: message.thinkingDuration,
                    isStreaming: message.isStreaming
                )
            }
            
            // Message content
            if !message.content.isEmpty {
                MessageContent(message: message)
            }
            
            // Tool calls
            if let toolCalls = message.toolCalls {
                ForEach(toolCalls) { toolCall in
                    let isCurrentTool = currentToolCallId == toolCall.id
                    let isExecuting = isToolExecuting && isCurrentTool
                    let isCompleted = !isExecuting && toolCallHasResult(toolCall)
                    let result = getToolResult(for: toolCall)

                    if isFileOperationTool(toolCall.name) {
                        FileOperationToolCard(
                            toolCall: toolCall,
                            isExecuting: isExecuting,
                            isCompleted: isCompleted,
                            executionResult: result
                        )
                    } else {
                        EnhancedToolCallCard(
                            toolCall: toolCall,
                            isExecuting: isExecuting,
                            isCompleted: isCompleted,
                            executionResult: result
                        )
                    }
                }
            }
            
            // Tool results (if not already shown in tool cards)
            if let toolResults = message.toolResults {
                ForEach(toolResults, id: \.toolCallId) { result in
                    // Only show results that aren't already displayed in tool cards
                    if Self.shouldDisplayStandaloneToolResult(
                        toolCallId: result.toolCallId,
                        toolCalls: message.toolCalls
                    ) {
                        EnhancedToolResultCard(
                            result: result,
                            toolCallName: getToolCallName(for: result.toolCallId)
                        )
                    }
                }
            }
            
            // Streaming indicator
            if message.isStreaming && message.content.isEmpty && (message.thinkingContent?.isEmpty ?? true) {
                HStack(spacing: 8) {
                    StreamingDots()
                    Text("思考中...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }
            
            // Timestamp & actions
            if !message.content.isEmpty {
                MessageFooter(message: message)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    // MARK: - Helper Methods

    private func toolCallHasResult(_ toolCall: ToolCall) -> Bool {
        return findToolResult(for: toolCall.id) != nil
    }

    private func toolCallHasResult(for toolCallId: String) -> Bool {
        return findToolResult(for: toolCallId) != nil
    }

    static func shouldDisplayStandaloneToolResult(toolCallId: String, toolCalls: [ToolCall]?) -> Bool {
        !(toolCalls?.contains(where: { $0.id == toolCallId }) ?? false)
    }

    private func getToolResult(for toolCall: ToolCall) -> ToolResult? {
        return findToolResult(for: toolCall.id)
    }

    private func getToolCallName(for toolCallId: String) -> String {
        return message.toolCalls?.first(where: { $0.id == toolCallId })?.name ?? "unknown"
    }

    private func findToolResult(for toolCallId: String) -> ToolResult? {
        toolResultsById[toolCallId]
    }

    private func isFileOperationTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("write") || lower.contains("edit")
            || lower.contains("create") || lower.contains("patch")
            || lower.contains("delete")
    }
}

struct MessageSourceHeader: View {
    let message: Message

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))

            Text(title)
                .font(.system(size: 11, weight: .semibold))

            if let modelLabel {
                Text(modelLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: message.role == .user ? 620 : 820, alignment: message.role == .user ? .trailing : .leading)
    }

    private var title: String {
        if message.role == .user {
            return "用户"
        }
        return message.source?.agentName?.isEmpty == false ? message.source!.agentName! : fallbackTitle
    }

    private var modelLabel: String? {
        guard message.role != .user else { return nil }
        let provider = message.source?.providerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = message.source?.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.isEmpty && model.isEmpty { return nil }
        if provider.isEmpty { return model }
        if model.isEmpty { return provider }
        return "\(provider) / \(model)"
    }

    private var fallbackTitle: String {
        switch message.role {
        case .user: return "用户"
        case .assistant: return "助手"
        case .system: return "系统"
        }
    }

    private var icon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "gearshape.fill"
        }
    }

    private var color: Color {
        switch message.role {
        case .user: return Theme.accentPrimary
        case .assistant: return Theme.statusInfo
        case .system: return Theme.textTertiary
        }
    }
}

// MARK: - Enhanced Chat View

struct EnhancedChatView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let currentPipeline: ExecutionPipeline?
    let currentTaskPlan: TaskPlan?

    /// 自动滚动跟随开关
    @State private var autoScrollEnabled = true

    /// 距离底部的偏移（越小越接近底部）
    @State private var bottomOffset: CGFloat = 0
    @State private var visibleViewportHeight: CGFloat = 0

    /// 工具结果索引
    private var toolResultsById: [String: ToolResult] {
        var index: [String: ToolResult] = [:]
        for result in messages.flatMap({ $0.toolResults ?? [] }) {
            index[result.toolCallId] = result
        }
        return index
    }

    private var visibleMessages: [Message] {
        messages.filter(\.isVisibleInTranscript)
    }

    private var transcriptEntries: [TranscriptEntry] {
        TranscriptEntry.make(from: visibleMessages)
    }

    /// 流式内容变化信号
    private var streamingSignal: Int {
        (visibleMessages.last?.content.count ?? 0) + (visibleMessages.last?.thinkingContent?.count ?? 0)
    }

    /// 是否接近底部（距离底部 < 120pt 视为接近）
    private var isNearBottom: Bool {
        bottomOffset < 120
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 6, pinnedViews: []) {
                        ForEach(transcriptEntries) { entry in
                            switch entry {
                            case .message(let message):
                                EnhancedMessageBubble(
                                    message: message,
                                    isToolExecuting: isProcessing && currentToolCallId != nil,
                                    currentToolCallId: currentToolCallId,
                                    toolResultsById: toolResultsById
                                )
                                .id(message.id)

                            case .activity(let messages):
                                AgentActivityGroupView(
                                    messages: messages,
                                    isProcessing: isProcessing,
                                    currentToolCallId: currentToolCallId,
                                    toolResultsById: toolResultsById
                                )
                                .id(messages.first?.id)
                            }
                        }

                        // TaskPlan 面板（Multi-Agent 模式）
                        if let taskPlan = currentTaskPlan {
                            TaskPlanView(plan: taskPlan)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 8)
                        }

                        // 底部锚点（用于滚动）
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: BottomOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).maxY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollViewportHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    }
                )
                .onPreferenceChange(BottomOffsetPreferenceKey.self) { contentBottom in
                    let newOffset = max(0, visibleViewportHeight - contentBottom)
                    bottomOffset = newOffset
                    if autoScrollEnabled && newOffset > 140 && !isProcessing {
                        autoScrollEnabled = false
                    }
                }
                .onPreferenceChange(ScrollViewportHeightPreferenceKey.self) { height in
                    visibleViewportHeight = height
                }
                // 新消息到达时滚动
                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount && (autoScrollEnabled || isProcessing) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // 流式内容更新时滚动
                .onChange(of: streamingSignal) { _, _ in
                    if autoScrollEnabled && (visibleMessages.last?.isStreaming == true || isProcessing) {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                // 工具调用变化时滚动
                .onChange(of: currentToolCallId) { _, _ in
                    if autoScrollEnabled && isProcessing {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    // 初始加载滚动到底部
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                
                // 浮动控制按钮
                if !visibleMessages.isEmpty {
                    VStack(spacing: 10) {
                        // 自动跟随开关
                        FloatingButton(
                            icon: autoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle",
                            label: autoScrollEnabled ? "自动跟随" : (isNearBottom ? "恢复跟随" : "回到底部"),
                            isActive: autoScrollEnabled,
                            badge: !isNearBottom ? true : nil
                        ) {
                            if autoScrollEnabled {
                                autoScrollEnabled = false
                            } else {
                                autoScrollEnabled = true
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo("bottom", anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }
}

private enum TranscriptEntry: Identifiable {
    case message(Message)
    case activity([Message])

    var id: UUID {
        switch self {
        case .message(let message):
            return message.id
        case .activity(let messages):
            return messages.first?.id ?? UUID()
        }
    }

    static func make(from messages: [Message]) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        var activityBuffer: [Message] = []

        func flushActivity() {
            guard !activityBuffer.isEmpty else { return }
            entries.append(.activity(activityBuffer))
            activityBuffer.removeAll()
        }

        for message in messages {
            if message.isAgentActivity {
                activityBuffer.append(message)
            } else {
                flushActivity()
                entries.append(.message(message))
            }
        }

        flushActivity()
        return entries
    }
}

private extension Message {
    var isAgentActivity: Bool {
        role == .assistant
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!(thinkingContent?.isEmpty ?? true) || !(toolCalls?.isEmpty ?? true) || !(toolResults?.isEmpty ?? true))
    }
}

private struct AgentActivityGroupView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let toolResultsById: [String: ToolResult]

    @State private var isExpanded = false

    private var toolCalls: [ToolCall] {
        messages.flatMap { $0.toolCalls ?? [] }
    }

    private var hasFailure: Bool {
        toolCalls.contains { tool in
            toolResultsById[tool.id]?.status == .error
        }
    }

    private var isRunning: Bool {
        isProcessing && currentToolCallId != nil && toolCalls.contains { $0.id == currentToolCallId }
    }

    private var completedCount: Int {
        toolCalls.filter { toolResultsById[$0.id]?.status == .success }.count
    }

    private var failedCount: Int {
        toolCalls.filter { toolResultsById[$0.id]?.status == .error }.count
    }

    private var totalThinkingDuration: TimeInterval {
        messages.compactMap(\.thinkingDuration).reduce(0, +)
    }

    private var summaryText: String {
        var parts: [String] = []
        if hasFailure {
            parts.append("有失败项")
        } else if isRunning {
            parts.append("持续执行中")
        }
        if !toolCalls.isEmpty {
            parts.append("\(toolCalls.count) 次工具调用")
        }
        if totalThinkingDuration > 0 {
            parts.append(formatDuration(totalThinkingDuration))
        }
        if failedCount > 0 {
            parts.append("\(failedCount) 个失败")
        } else if completedCount > 0 {
            parts.append("\(completedCount) 个完成")
        }
        return parts.isEmpty ? "内部处理" : parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        if hasFailure { return Theme.statusError }
        if isRunning { return Theme.statusInfo }
        return Theme.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isRunning ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)

                    Text(isRunning ? "正在执行" : "执行摘要")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isRunning ? Theme.statusInfo : Theme.textSecondary)

                    Text(summaryText)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)

                    Spacer()

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.statusInfo)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(isRunning ? Theme.statusInfo.opacity(0.06) : Color.clear)
            )

            if isExpanded || hasFailure || isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        if let thinking = message.thinkingContent, !thinking.isEmpty {
                            ActivityThinkingRow(
                                content: thinking,
                                duration: message.thinkingDuration,
                                isStreaming: message.isStreaming
                            )
                        }

                        ForEach(message.toolCalls ?? []) { toolCall in
                            ActivityToolRow(
                                toolCall: toolCall,
                                result: toolResultsById[toolCall.id],
                                isExecuting: isProcessing && currentToolCallId == toolCall.id
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgSecondary.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(hasFailure ? Theme.statusError.opacity(0.28) : Theme.borderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isExpanded = hasFailure || isRunning
        }
        .onChange(of: isRunning) { _, running in
            if running {
                isExpanded = true
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

private struct ActivityThinkingRow: View {
    let content: String
    let duration: TimeInterval?
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.thinkingAccent.opacity(0.75))

                    Text("思考")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    if let duration {
                        Text(String(format: "%.0fms", duration * 1000))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }

                    if isStreaming {
                        ThinkingDots()
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
            }
        }
    }
}

private struct ActivityToolRow: View {
    let toolCall: ToolCall
    let result: ToolResult?
    let isExecuting: Bool

    @State private var isExpanded = false

    private var statusColor: Color {
        if isExecuting { return Theme.statusInfo }
        switch result?.status {
        case .success: return Theme.statusSuccess
        case .error: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        case .none: return Theme.textTertiary
        }
    }

    private var statusIcon: String {
        if isExecuting { return "arrow.triangle.2.circlepath" }
        switch result?.status {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .none: return "clock"
        }
    }

    private var statusText: String {
        if isExecuting { return "执行中" }
        switch result?.status {
        case .success: return "执行成功"
        case .error: return "执行失败"
        case .cancelled: return "已取消"
        case .none: return "等待结果"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 14)

                    Text(toolCall.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(statusColor)

                    Spacer()

                    if !toolCall.arguments.isEmpty || result != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded || result?.status == .error {
                VStack(alignment: .leading, spacing: 8) {
                    if !toolCall.arguments.isEmpty {
                        ForEach(Array(toolCall.arguments.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 8) {
                                Text(key)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.textTertiary)
                                    .frame(width: 86, alignment: .leading)

                                Text(String(describing: value.value))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.textSecondary.opacity(0.85))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let result {
                        let text = result.error ?? result.output
                        if !text.isEmpty {
                            Text(text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(result.status == .error ? Theme.statusError : Theme.textTertiary)
                                .lineLimit(result.status == .error ? nil : 4)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.codeBackground.opacity(0.75))
                                .cornerRadius(Theme.radiusSM)
                        }
                    }
                }
                .padding(.leading, 22)
            }
        }
        .onAppear {
            isExpanded = result?.status == .error || isExecuting
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Floating Button

struct FloatingButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let badge: Bool?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))

                    if badge == true {
                        Circle()
                            .fill(Theme.accentPrimary)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }

                if isHovered {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .foregroundColor(isActive ? Theme.accentPrimary : Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.bgSecondary)
                    .shadow(color: Theme.shadowStrong.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? Theme.accentPrimary.opacity(0.3) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help(isActive ? "点击切换到手动滚动模式" : "点击开启自动跟随最新消息")
    }
}


// MARK: - Processing Animation Overlay

struct ProcessingAnimationOverlay: View {
    let isProcessing: Bool
    let currentToolName: String?
    let progress: Double?

    var body: some View {
        if isProcessing {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentPrimary.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在处理...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)

                        if let toolName = currentToolName {
                            Text("执行: \(toolName)")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accentPrimary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                        .fill(Theme.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                        .stroke(Theme.accentPrimary.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

struct EnhancedMessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            EnhancedMessageBubble(
                message: Message(
                    role: .assistant,
                    content: "我来帮你创建一个新文件。",
                    toolCalls: [
                        ToolCall(id: "1", name: "write_file", arguments: [
                            "path": AnyCodable("/path/to/file.swift"),
                            "content": AnyCodable("print(\"Hello\")")
                        ])
                    ],
                    toolResults: [
                        .success(toolCallId: "1", output: "文件写入成功")
                    ]
                ),
                isToolExecuting: false,
                currentToolCallId: nil,
                toolResultsById: [:]
            )

            EnhancedMessageBubble(
                message: Message(
                    role: .assistant,
                    content: "正在编辑文件...",
                    toolCalls: [
                        ToolCall(id: "2", name: "edit_file", arguments: [
                            "path": AnyCodable("/path/to/file.swift"),
                            "old_text": AnyCodable("old"),
                            "new_text": AnyCodable("new")
                        ])
                    ]
                ),
                isToolExecuting: true,
                currentToolCallId: "2",
                toolResultsById: [:]
            )
        }
        .padding()
        .background(Theme.bgPrimary)
        .previewLayout(.sizeThatFits)
    }
}
