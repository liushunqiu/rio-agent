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

// MARK: - Enhanced Chat View (Paginated)

struct EnhancedChatView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?

    /// 单页目标渲染重量。短消息会多放，长输出/工具结果会少放。
    private let targetPageWeight = 9_000

    /// 防止大量短消息堆在同一页。
    private let maxMessagesPerPage = 12

    /// 当前页码（0-based）
    @State private var currentPage: Int = 0

    /// 流式输出时是否自动跟随最后一页
    @State private var followLatest = true

    /// 滚动防抖定时器
    @State private var scrollDebounceTimer: Timer?

    // MARK: - Computed

    /// 总页数
    private var totalPages: Int {
        max(1, messagePages.count)
    }

    /// 是否在最后一页
    private var isOnLastPage: Bool {
        currentPage >= totalPages - 1
    }

    /// 当前页显示的消息
    private var pagedMessages: [Message] {
        guard !messagePages.isEmpty else { return [] }
        return messagePages[min(currentPage, messagePages.count - 1)]
    }

    /// 按渲染成本分页，而不是固定消息条数。
    private var messagePages: [[Message]] {
        guard !messages.isEmpty else { return [] }

        var pages: [[Message]] = []
        var page: [Message] = []
        var pageWeight = 0

        for message in messages {
            let weight = renderWeight(for: message)
            let shouldStartNewPage = !page.isEmpty
                && (pageWeight + weight > targetPageWeight || page.count >= maxMessagesPerPage)

            if shouldStartNewPage {
                pages.append(page)
                page = []
                pageWeight = 0
            }

            page.append(message)
            pageWeight += weight
        }

        if !page.isEmpty {
            pages.append(page)
        }

        return pages
    }

    /// 工具结果索引，避免每个消息气泡重复扫描全量消息。
    private var toolResultsById: [String: ToolResult] {
        var index: [String: ToolResult] = [:]
        for result in messages.flatMap({ $0.toolResults ?? [] }) {
            index[result.toolCallId] = result
        }
        return index
    }

    /// 流式文本变化信号，只比较长度，减少大字符串作为 onChange 值的复制成本。
    private var streamingContentSignal: Int {
        (messages.last?.content.count ?? 0) + (messages.last?.thinkingContent?.count ?? 0)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(pagedMessages) { message in
                            EnhancedMessageBubble(
                                message: message,
                                isToolExecuting: isProcessing && currentToolCallId != nil,
                                currentToolCallId: currentToolCallId,
                                toolResultsById: toolResultsById
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .scale)
                            ))
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .onChange(of: messages.count) { _, _ in
                    let latestPage = max(0, totalPages - 1)
                    if currentPage > latestPage {
                        currentPage = latestPage
                    }

                    // 新消息到达时，自动跳到最后一页
                    if followLatest || isProcessing {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentPage = latestPage
                        }
                    }
                }
                .onChange(of: streamingContentSignal) { _, _ in
                    if followLatest && (messages.last?.isStreaming == true || isProcessing) {
                        currentPage = max(0, totalPages - 1)
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: currentToolCallId) { _, _ in
                    if shouldAutoScroll {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            // 分页导航栏
            if totalPages > 1 {
                PaginationBar(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    followLatest: followLatest,
                    isStreaming: messages.last?.isStreaming == true,
                    onFirstPage: {
                        followLatest = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentPage = 0
                        }
                    },
                    onPrevPage: {
                        followLatest = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentPage = max(0, currentPage - 1)
                        }
                    },
                    onNextPage: {
                        let nextPage = min(totalPages - 1, currentPage + 1)
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentPage = nextPage
                        }
                        followLatest = nextPage >= totalPages - 1
                    },
                    onLastPage: {
                        followLatest = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentPage = totalPages - 1
                        }
                    },
                    onToggleFollow: {
                        followLatest.toggle()
                        if followLatest {
                            withAnimation(.easeOut(duration: 0.2)) {
                                currentPage = totalPages - 1
                            }
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            // 初始加载时跳到最后一页
            currentPage = max(0, totalPages - 1)
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard shouldAutoScroll else { return }
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: false) { _ in
            DispatchQueue.main.async {
                guard shouldAutoScroll, let lastMessage = pagedMessages.last else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var shouldAutoScroll: Bool {
        followLatest && isOnLastPage && (messages.last?.isStreaming == true || isProcessing)
    }

    private func renderWeight(for message: Message) -> Int {
        var weight = 120

        switch message.role {
        case .user:
            weight += message.content.count
        case .system:
            weight += message.content.count * 2
        case .assistant:
            weight += message.content.count * 2
        }

        if let thinkingContent = message.thinkingContent {
            weight += thinkingContent.count
        }

        if let toolCalls = message.toolCalls {
            weight += toolCalls.reduce(0) { total, toolCall in
                let argumentsWeight = toolCall.arguments.values.reduce(0) { partial, value in
                    partial + String(describing: value.value).count
                }
                return total + 600 + toolCall.name.count + argumentsWeight
            }
        }

        if let toolResults = message.toolResults {
            weight += toolResults.reduce(0) { total, result in
                total + 700 + result.output.count + (result.error?.count ?? 0)
            }
        }

        return weight
    }
}

// MARK: - Pagination Bar

struct PaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let followLatest: Bool
    let isStreaming: Bool
    let onFirstPage: () -> Void
    let onPrevPage: () -> Void
    let onNextPage: () -> Void
    let onLastPage: () -> Void
    let onToggleFollow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 第一页
            Button(action: onFirstPage) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(currentPage > 0 ? Theme.textSecondary : Theme.textTertiary)
            .disabled(currentPage <= 0)
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            // 上一页
            Button(action: onPrevPage) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(currentPage > 0 ? Theme.textSecondary : Theme.textTertiary)
            .disabled(currentPage <= 0)

            // 页码指示
            Text("\(currentPage + 1) / \(totalPages)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(minWidth: 50)

            // 下一页
            Button(action: onNextPage) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(currentPage < totalPages - 1 ? Theme.textSecondary : Theme.textTertiary)
            .disabled(currentPage >= totalPages - 1)

            // 最后一页
            Button(action: onLastPage) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(currentPage < totalPages - 1 ? Theme.textSecondary : Theme.textTertiary)
            .disabled(currentPage >= totalPages - 1)
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Spacer()

            // 跟随最新 / 流式指示
            if isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.accentPrimary)
                        .frame(width: 6, height: 6)
                        .opacity(0.8)
                    Text("输出中")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accentPrimary)
                }
            }

            Button(action: onToggleFollow) {
                HStack(spacing: 4) {
                    Image(systemName: followLatest ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 9))
                    Text(followLatest ? "已锁定" : "已解锁")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(followLatest ? Theme.accentPrimary : Theme.textTertiary)
            .help(followLatest ? "流式输出时自动跳转最新页（点击解锁）" : "已解锁翻页，点击锁定自动跟随")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .background(Theme.bgSecondary.opacity(0.72))
        .overlay(
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1),
            alignment: .top
        )
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
