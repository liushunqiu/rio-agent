import SwiftUI

struct MessageBubble: View {
    let message: Message

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
                    ToolCallCard(toolCall: toolCall)
                }
            }

            // Tool results
            if let toolResults = message.toolResults {
                ForEach(toolResults, id: \.toolCallId) { result in
                    ToolResultCard(result: result)
                }
            }

            // Streaming indicator (only when no content and no thinking yet)
            if message.isStreaming && message.content.isEmpty && (message.thinkingContent == nil || message.thinkingContent!.isEmpty) {
                HStack(spacing: 8) {
                    StreamingDots()
                    Text("思考中...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }

            // Timestamp & actions — only for messages with actual text content, not for tool-call-only messages
            if !message.content.isEmpty {
                MessageFooter(message: message)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Message Content

struct MessageContent: View {
    let message: Message

    var body: some View {
        if message.role == .user {
            // User bubble with gradient
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(Theme.textOnAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Theme.userBubble)
                .cornerRadius(Theme.radiusLG)
                .textSelection(.enabled)
        } else if message.role == .system {
            // System message
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bgTertiary.opacity(0.5))
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
        } else {
            // Assistant message
            if message.isStreaming {
                // 流式输出期间使用简单的Text视图，提高性能
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusLG)
                            .fill(Theme.assistantBubbleBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusLG)
                            .stroke(Theme.assistantBubbleBorder, lineWidth: 1)
                    )
            } else {
                // 流式输出完成后使用完整的Markdown渲染
                MarkdownRenderer(text: message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusLG)
                            .fill(Theme.assistantBubbleBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusLG)
                            .stroke(Theme.assistantBubbleBorder, lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Message Footer

struct MessageFooter: View {
    let message: Message
    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 14) {
            Text(message.timestamp, style: .time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary.opacity(0.7))

            if message.role == .assistant && !message.content.isEmpty && !message.isStreaming {
                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "已复制" : "复制")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isCopied ? Theme.statusSuccess : Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isCopied ? Color.clear : Theme.bgTertiary.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
                .help("复制内容")
            }
        }
        .padding(.top, 2)
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
            }
        }
    }
}

// MARK: - Streaming Dots Animation

struct StreamingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.accentPrimary)
                    .frame(width: 6, height: 6)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.8)))
                    .scaleEffect(0.6 + 0.4 * abs(sin(phase + Double(i) * 0.8)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Thinking Card

struct ThinkingCard: View {
    let content: String
    let duration: TimeInterval?
    let isStreaming: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact one-line header — clickable to expand
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Text(isExpanded ? "−" : "+")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.thinkingAccent)

                    Text("Thought:")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.thinkingAccent)

                    if let duration = duration {
                        Text(String(format: "%.0fms", duration * 1000))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.thinkingAccent)
                    }

                    if isStreaming {
                        ThinkingDots()
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Expandable thinking content — plain text, no card
            if isExpanded {
                if content.count > 2000 {
                    ScrollView {
                        Text(content)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.textSecondary.opacity(0.65))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                            .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 400)
                } else {
                    Text(content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.textSecondary.opacity(0.65))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgTertiary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Thinking Dots (for streaming state inside ThinkingCard header)

struct ThinkingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.thinkingAccent)
                    .frame(width: 3, height: 3)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.8)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Avatars

struct AssistantAvatar: View {
    var body: some View {
        ZStack {
            // Gradient ring
            Circle()
                .stroke(Theme.accentGradient, lineWidth: 1.5)
                .frame(width: 40, height: 40)

            // Dark fill
            Circle()
                .fill(Theme.bgSecondary)
                .frame(width: 37, height: 37)

            // Icon
            Image(systemName: "bolt.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.accentGradient)
        }
    }
}

struct UserAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accentPrimary.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.accentPrimary.opacity(0.25), lineWidth: 1)
                )

            Image(systemName: "person.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.accentPrimary)
        }
    }
}

// MARK: - Tool Views

struct ToolCallCard: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.statusWarning)

                    Text(toolCall.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Theme.borderSubtle)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(toolCall.arguments.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.accentPrimary)
                                .frame(minWidth: 80, alignment: .leading)

                            Text(String(describing: value.value))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.toolCallBg)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.toolCallBorder, lineWidth: 1)
        )
    }
}

struct ToolResultCard: View {
    let result: ToolResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)

                    Text(result.status == .success ? "执行成功" : "执行失败")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Theme.borderSubtle)

                VStack(alignment: .leading, spacing: 8) {
                    if !result.output.isEmpty {
                        Text(result.output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.codeBackground)
                            .cornerRadius(Theme.radiusSM)
                    }

                    if let error = result.error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.statusError)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.statusError.opacity(0.1))
                            .cornerRadius(Theme.radiusSM)
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(statusColor.opacity(0.06))
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch result.status {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .success: return Theme.statusSuccess
        case .error: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        }
    }
}
