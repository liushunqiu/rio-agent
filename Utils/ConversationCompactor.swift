import Foundation

// MARK: - Conversation Compactor
// 对话压缩模块，负责智能压缩历史消息以节省 Token

/// 对话压缩器 - 使用 AI 或规则压缩历史消息
class ConversationCompactor {

    // MARK: - Configuration

    /// 默认保留的最近消息数
    static let defaultKeepRecent = 20

    /// 用于总结的最大输入长度
    private let maxSummaryInputLength = 10000

    /// 用于总结的最大 Token 数
    private let maxSummaryTokens = 1000

    // MARK: - AI Service

    private let aiService: AIService?
    private let model: String

    // MARK: - Initialization

    init(aiService: AIService? = nil, model: String = "gpt-4o") {
        self.aiService = aiService
        self.model = model
    }

    // MARK: - Public Methods

    /// 检查是否需要压缩
    func shouldCompact(messageCount: Int, threshold: Int = 50) -> Bool {
        return messageCount > threshold
    }

    /// 执行对话压缩
    /// - Parameters:
    ///   - messages: 原始消息列表
    ///   - keepRecent: 保留最近的消息数
    ///   - showNotification: 是否显示通知消息
    /// - Returns: 压缩后的消息列表
    func compact(
        messages: [Message],
        keepRecent: Int = defaultKeepRecent,
        showNotification: Bool = false
    ) async -> [Message] {

        guard messages.count > keepRecent else {
            if showNotification {
                let msg = Message.system("💬 当前对话较短（\(messages.count) 条消息），无需压缩。")
                return messages + [msg]
            }
            return messages
        }

        let oldMessages = Array(messages.prefix(messages.count - keepRecent))
        let recentMessages = Array(messages.suffix(keepRecent))

        // Try AI-powered compaction first
        if aiService != nil {
            if let summary = await performAICompaction(oldMessages: oldMessages) {
                let summaryMessage = createSummaryMessage(
                    summary: summary,
                    compactedCount: oldMessages.count,
                    keptCount: recentMessages.count
                )
                var result = [summaryMessage] + recentMessages

                if showNotification {
                    let notification = Message.system("✅ 已使用 AI 压缩 \(oldMessages.count) 条历史消息。")
                    result.append(notification)
                }

                return result
            }
        }

        // Fallback to rule-based compaction
        return performRuleBasedCompaction(
            oldMessages: oldMessages,
            recentMessages: recentMessages,
            showNotification: showNotification
        )
    }

    // MARK: - AI-Powered Compaction

    private func performAICompaction(oldMessages: [Message]) async -> String? {
        guard let aiService = aiService else { return nil }

        // Build conversation text for summarization
        let conversationText = buildConversationText(from: oldMessages)

        // Limit input length
        let truncatedText = truncateText(conversationText, maxLength: maxSummaryInputLength)

        // Create summarization prompt
        let prompt = buildSummaryPrompt(conversationText: truncatedText)

        do {
            let response = try await aiService.sendMessage(
                [Message.system(prompt)],
                tools: [],
                model: model,
                maxTokens: maxSummaryTokens
            )
            return response.content
        } catch {
            return nil
        }
    }

    private func buildConversationText(from messages: [Message]) -> String {
        var text = ""
        for msg in messages where msg.isVisibleInTranscript {
            let role: String
            switch msg.role {
            case .user: role = "用户"
            case .assistant: role = "助手"
            case .system: role = "系统"
            }

            if !msg.content.isEmpty {
                text += "\(role): \(msg.content)\n"
            }

            // Include tool usage info
            if let toolCalls = msg.toolCalls {
                for tc in toolCalls {
                    text += "\(role) 调用工具: \(tc.name)\n"
                }
            }

            if let toolResults = msg.toolResults {
                for result in toolResults {
                    text += "\(role) 工具结果（\(toolResultStatusLabel(result.status))）: \(snippet(result.modelContent, maxLength: 200))\n"
                }
            }
        }
        return text
    }

    private func buildSummaryPrompt(conversationText: String) -> String {
        return """
        请将以下对话历史压缩为简洁的摘要。要求：

        1. 保留所有重要的上下文信息（用户的需求、已完成的任务、发现的问题）
        2. 保留关键的技术细节（文件路径、函数名、代码修改）
        3. 保留当前的工作状态（正在做什么、下一步计划）
        4. 使用结构化格式，便于后续 AI 继续工作

        对话历史：
        \(conversationText)

        请输出压缩后的摘要（使用 Markdown 格式）：
        """
    }

    private func truncateText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "\n... (对话内容已截断)"
    }

    private func createSummaryMessage(summary: String, compactedCount: Int, keptCount: Int) -> Message {
        let content = """
        ## 对话历史摘要（AI 压缩）

        \(summary)

        *（已压缩 \(compactedCount) 条历史消息，保留最近 \(keptCount) 条）*
        """
        return Message.system(content)
    }

    // MARK: - Rule-Based Compaction

    private func performRuleBasedCompaction(
        oldMessages: [Message],
        recentMessages: [Message],
        showNotification: Bool
    ) -> [Message] {

        var summary = "## 对话历史摘要\n\n"
        var userMessages: [String] = []
        var assistantMessages: [String] = []
        var toolCallsMade: [String] = []
        var toolResultSummaries: [String] = []

        for msg in oldMessages where msg.isVisibleInTranscript {
            switch msg.role {
            case .user:
                if !msg.content.isEmpty {
                    userMessages.append(snippet(msg.content, maxLength: 120))
                }
            case .assistant:
                if !msg.content.isEmpty {
                    assistantMessages.append(snippet(msg.content, maxLength: 160))
                }
                if let toolCalls = msg.toolCalls {
                    for tc in toolCalls {
                        toolCallsMade.append(tc.name)
                    }
                }
            case .system:
                break
            }

            if let toolResults = msg.toolResults {
                for result in toolResults {
                    let text = snippet(result.modelContent, maxLength: 160)
                    toolResultSummaries.append("\(result.toolCallId) · \(toolResultStatusLabel(result.status)): \(text)")
                }
            }
        }

        if !userMessages.isEmpty {
            summary += "**用户请求:**\n"
            for (index, msg) in userMessages.prefix(3).enumerated() {
                summary += "\(index + 1). \(msg)\n"
            }
            if userMessages.count > 3 {
                summary += "... 还有 \(userMessages.count - 3) 个请求\n"
            }
        }

        if !assistantMessages.isEmpty {
            summary += "\n**助手结论/进展:**\n"
            for (index, msg) in assistantMessages.prefix(4).enumerated() {
                summary += "\(index + 1). \(msg)\n"
            }
            if assistantMessages.count > 4 {
                summary += "... 还有 \(assistantMessages.count - 4) 条进展\n"
            }
        }

        if !toolCallsMade.isEmpty {
            let uniqueTools = Set(toolCallsMade).sorted()
            summary += "\n**使用的工具:** \(uniqueTools.joined(separator: ", "))\n"
        }

        if !toolResultSummaries.isEmpty {
            summary += "\n**关键工具结果:**\n"
            for (index, resultSummary) in toolResultSummaries.prefix(5).enumerated() {
                summary += "\(index + 1). \(resultSummary)\n"
            }
            if toolResultSummaries.count > 5 {
                summary += "... 还有 \(toolResultSummaries.count - 5) 条工具结果\n"
            }
        }

        let summaryMessage = Message.system(summary)
        var result = [summaryMessage] + recentMessages

        if showNotification {
            let notification = Message.system("✅ 已压缩 \(oldMessages.count) 条历史消息。")
            result.append(notification)
        }

        return result
    }

    private func snippet(_ text: String, maxLength: Int) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !cleaned.isEmpty else { return "无内容" }
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength)) + "..."
    }

    private func toolResultStatusLabel(_ status: ToolResultStatus) -> String {
        switch status {
        case .success:
            return "成功"
        case .error:
            return "错误"
        case .cancelled:
            return "已取消"
        }
    }
}
