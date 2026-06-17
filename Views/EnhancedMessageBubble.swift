import SwiftUI

// MARK: - Enhanced Message Bubble

struct EnhancedMessageBubble: View {
    let message: Message
    let isToolExecuting: Bool
    let currentToolCallId: String?
    let toolResultsById: [String: ToolResult]

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
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
                    if !toolCallHasResult(for: result.toolCallId) {
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

// MARK: - Enhanced Chat View

struct EnhancedChatView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let currentPipeline: ExecutionPipeline?
    let currentTaskPlan: TaskPlan?

    /// 自动滚动跟随开关
    @State private var autoScrollEnabled = true

    /// 用户是否正在手动滚动（用于暂时禁用自动跟随）
    @State private var isUserScrolling = false

    /// 上次消息数量（检测新消息）
    @State private var lastMessageCount = 0

    /// 滚动位置追踪
    @State private var scrollPosition: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    /// 工具结果索引
    private var toolResultsById: [String: ToolResult] {
        var index: [String: ToolResult] = [:]
        for result in messages.flatMap({ $0.toolResults ?? [] }) {
            index[result.toolCallId] = result
        }
        return index
    }

    /// 流式内容变化信号
    private var streamingSignal: Int {
        (messages.last?.content.count ?? 0) + (messages.last?.thinkingContent?.count ?? 0)
    }

    /// 是否接近底部（距离底部 < 100pt 视为接近）
    private var isNearBottom: Bool {
        contentHeight - scrollPosition - visibleHeight < 100
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6, pinnedViews: []) {
                        ForEach(messages) { message in
                            EnhancedMessageBubble(
                                message: message,
                                isToolExecuting: isProcessing && currentToolCallId != nil,
                                currentToolCallId: currentToolCallId,
                                toolResultsById: toolResultsById
                            )
                            .id(message.id)
                        }

                        // Pipeline 流程面板（在消息列表末尾显示）
                        if let pipeline = currentPipeline, !pipeline.stages.isEmpty {
                            ExecutionPipelineView(pipeline: pipeline)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollPosition = -value
                }
                // 新消息到达时滚动
                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount && (autoScrollEnabled || isProcessing) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    lastMessageCount = newCount
                }
                // 流式内容更新时滚动
                .onChange(of: streamingSignal) { _, _ in
                    if autoScrollEnabled && (messages.last?.isStreaming == true || isProcessing) {
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
            }

            // 浮动控制按钮
            if !messages.isEmpty {
                VStack(spacing: 10) {
                    // 自动跟随开关
                    FloatingButton(
                        icon: autoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle",
                        label: autoScrollEnabled ? "自动跟随" : "手动模式",
                        isActive: autoScrollEnabled,
                        badge: !isNearBottom && !autoScrollEnabled ? true : nil
                    ) {
                        autoScrollEnabled.toggle()
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
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

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
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
