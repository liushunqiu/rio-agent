import Foundation

// MARK: - Context Builder
// 上下文构建模块，负责构建和管理 AI 请求的上下文消息

/// 上下文构建器 - 智能管理消息上下文和 Token 预算
class ContextBuilder {
    private static let systemPromptCache = NSCache<NSString, NSString>()

    // MARK: - Configuration

    /// 上下文窗口使用阈值（85% 保留安全边际）
    private let contextThreshold: Double = 0.85

    /// 工具输出的最大字符数（旧消息）
    private let maxToolOutputLength = 1500

    /// 保持未压缩的最近消息数
    private let recentUncompressedCount = 4

    /// 最少保留的消息数（即使超出 Token 预算）
    private let minimumMessageCount = 4

    // MARK: - Dependencies

    private let tokenTracker: TokenTracker
    private let model: String
    private let workingDirectory: String?
    private let maxContextMessages: Int?
    private let systemPrompt: String
    private let memoryContext: String?

    // MARK: - Initialization

    init(
        tokenTracker: TokenTracker,
        model: String,
        workingDirectory: String? = nil,
        maxContextMessages: Int? = nil,
        systemPrompt: String,
        memoryContext: String? = nil
    ) {
        self.tokenTracker = tokenTracker
        self.model = model
        self.workingDirectory = workingDirectory
        self.maxContextMessages = Self.normalizeMessageLimit(maxContextMessages)
        self.systemPrompt = systemPrompt
        self.memoryContext = memoryContext
    }

    // MARK: - Public Methods

    /// 构建上下文消息（包含系统消息 + 智能选择的历史消息）
    func buildContextMessages(from messages: [Message]) -> [Message] {
        let systemMsg = buildSystemMessage()

        let contextWindow = ModelCapabilities.capabilities(for: model).contextWindow
        let threshold = Int(Double(contextWindow) * contextThreshold)

        var totalTokens = tokenTracker.estimateTokens(systemMsg.content)
        var keptMessages: [Message] = []

        // 智能保留策略: 从最新到最旧遍历
        let reversedMessages = messages.reversed()
        var keepCount = 0

        for msg in reversedMessages {
            if let maxContextMessages, keepCount >= maxContextMessages {
                break
            }

            let msgTokens = estimateMessageTokens(msg)
            if totalTokens + msgTokens > threshold, keepCount >= minimumMessageCount {
                break
            }
            totalTokens += msgTokens
            keptMessages.append(msg)
            keepCount += 1
        }

        // 恢复时间顺序并压缩旧工具输出
        return [systemMsg] + compressToolOutputs(keptMessages.reversed())
    }

    /// 估算单个消息的 Token 数
    func estimateMessageTokens(_ message: Message) -> Int {
        var total = 4 // 消息格式开销

        total += tokenTracker.estimateTokens(message.content)

        if let thinking = message.thinkingContent {
            total += tokenTracker.estimateTokens(thinking)
        }

        if let toolResults = message.toolResults {
            for tr in toolResults {
                total += 6 + tokenTracker.estimateTokens(tr.output)
            }
        }

        if let toolCalls = message.toolCalls {
            for tc in toolCalls {
                total += 8 + tokenTracker.estimateTokens(tc.name)
                total += tokenTracker.estimateTokens("\(tc.arguments)")
            }
        }

        return total
    }

    // MARK: - Private Methods

    /// 构建系统提示消息
    private func buildSystemMessage() -> Message {
        let cacheKey = [
            workingDirectory ?? "__no_working_directory__",
            systemPrompt,
            memoryContext ?? ""
        ].joined(separator: "\u{1F}")
        if let cached = Self.systemPromptCache.object(forKey: cacheKey as NSString) {
            return Message.system(String(cached))
        }

        var prompt = systemPrompt
        if let dir = workingDirectory {
            prompt += "\n\nWorking directory: \(dir)"
        }
        if let memoryContext, !memoryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nMemory context:\n\(memoryContext)"
        }
        Self.systemPromptCache.setObject(prompt as NSString, forKey: cacheKey as NSString)
        return Message.system(prompt)
    }

    /// 压缩旧消息中的工具输出以节省 Token
    private func compressToolOutputs(_ messages: [Message]) -> [Message] {
        return messages.enumerated().map { index, message in
            // 保持最近的消息不压缩
            guard index < messages.count - recentUncompressedCount else {
                return message
            }

            // 压缩旧的工具结果
            guard let toolResults = message.toolResults, !toolResults.isEmpty else {
                return message
            }

            var didCompress = false
            let compressedResults = toolResults.map { result -> ToolResult in
                guard result.output.count > maxToolOutputLength else {
                    return result
                }
                didCompress = true

                // 保留首尾内容，中间截断 — 首部通常包含关键信息，尾部包含总结
                let prefixLen = maxToolOutputLength * 2 / 3
                let suffixLen = maxToolOutputLength / 3
                let prefix = String(result.output.prefix(prefixLen))
                let suffix = String(result.output.suffix(suffixLen))

                return ToolResult(
                    toolCallId: result.toolCallId,
                    status: result.status,
                    output: "\(prefix)\n\n[... truncated \(result.output.count - maxToolOutputLength) chars ...]\n\n\(suffix)",
                    error: result.error
                )
            }

            guard didCompress else {
                return message
            }

            return Message(
                id: message.id,
                role: message.role,
                content: message.content,
                thinkingContent: message.thinkingContent,
                thinkingDuration: message.thinkingDuration,
                toolCalls: message.toolCalls,
                toolResults: compressedResults,
                isStreaming: message.isStreaming
            )
        }
    }

    private static func normalizeMessageLimit(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 999 else { return nil }
        return max(value, 1)
    }
}
