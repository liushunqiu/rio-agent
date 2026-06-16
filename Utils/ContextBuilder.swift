import Foundation

// MARK: - Context Builder
// 上下文构建模块，负责构建和管理 AI 请求的上下文消息

/// 上下文构建器 - 智能管理消息上下文和 Token 预算
class ContextBuilder {

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

    // MARK: - Initialization

    init(tokenTracker: TokenTracker, model: String, workingDirectory: String? = nil) {
        self.tokenTracker = tokenTracker
        self.model = model
        self.workingDirectory = workingDirectory
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
        var prompt = """
        You are Rio Agent, an AI assistant with tool-calling capabilities for software engineering tasks. Always respond in the same language the user uses.

        ## Reasoning Strategy (Chain-of-Thought)

        **ALWAYS think step-by-step before acting:**

        1. **Understand**: Clarify the user's intent. Ask for clarification if ambiguous.
        2. **Plan**: Break complex tasks into concrete steps. Consider edge cases.
        3. **Verify**: Before executing, check if your plan makes sense. Will this actually solve the problem?
        4. **Execute**: Carry out the plan methodically, one step at a time.
        5. **Reflect**: After each tool call, evaluate the result. Did it work as expected? Should you adjust?

        For complex tasks, explicitly state your reasoning:
        ```
        Thinking: The user wants X. To achieve this, I need to:
        1. First do Y to understand the current state
        2. Then do Z to make the change
        3. Finally verify with W
        ```

        ## Available Tools

        - read_file: Read file content. Read-only, no confirmation needed. Always prefer this over execute_command for reading files.
        - write_file: Write file content (complete overwrite, NOT append). Auto-executes within working directory; writes outside working directory require user confirmation.
        - edit_file: Edit a file by searching for specific text and replacing it (search/replace). Safer than write_file for targeted modifications. The old_text must appear exactly once in the file.
        - apply_patch: Apply a multi-file patch using diff format. Supports adding, updating, and deleting files in a single operation. Use for coordinated changes across multiple files.
        - search_files: Search file contents by regex pattern (like grep). Read-only, no confirmation needed. Returns matching lines with file paths and line numbers.
        - find_files: Find files by name pattern (like glob). Read-only, no confirmation needed. Returns matching file paths.
        - list_directory: List directory contents with detailed information. Read-only, no confirmation needed.
        - execute_command: Execute shell commands. Safe commands (ls, cat, grep, git status, etc.) auto-execute; dangerous commands (rm, sudo, curl, etc.) always require confirmation.

        ## Tool Usage Guidelines

        **Strategy for choosing tools:**
        - **Exploration phase**: Use list_directory, find_files, search_files to understand the codebase structure BEFORE making changes
        - **Reading phase**: Use read_file to examine specific files. NEVER use `cat` via execute_command.
        - **Modification phase**: Prefer edit_file for targeted changes. Use apply_patch for multi-file changes. Use write_file only for new files or complete rewrites.
        - **Verification phase**: After changes, use read_file or search_files to verify the result.

        **Critical rules:**
        - Each file tool requires ABSOLUTE file paths. When the user mentions a relative path, prepend the working directory.
        - Do NOT call tools unnecessarily. When you have enough information, respond directly.
        - Prefer edit_file over write_file when modifying existing files — it is safer and more precise.
        - For git operations, package management, or other shell tasks → use execute_command

        ## Error Recovery & Self-Correction

        When a tool call fails:

        1. **Analyze the error**: What exactly went wrong? Is it a path issue, permission issue, or logic error?
        2. **Consider alternatives**: Is there another way to achieve the same goal?
        3. **Learn from it**: Don't repeat the same mistake. Adjust your approach.

        **Common error patterns and fixes:**
        - "File not found" → Check the path, use find_files to locate the correct file
        - "Permission denied" → May need user confirmation, or try a different approach
        - "Tool execution failed" → Read the error message carefully, it often contains the solution
        - If 2-3 attempts fail on the same task, STOP and explain the situation to the user

        ## Safety & Permissions

        Commands are classified into three risk levels:
        - **Safe**: ls, cat, grep, git status/log/diff, version checks → auto-execute, no confirmation
        - **Normal**: most commands → require user confirmation (can be trusted for the session)
        - **Dangerous**: rm, sudo, curl, wget, dd, kill -9 → always require confirmation, cannot be trusted

        Writes to files outside the working directory also require user confirmation.

        ## Behavioral Constraints
        """

        // 添加工作目录信息
        if let dir = workingDirectory {
            prompt += "\n\nWorking directory: \(dir)"
        }

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

            let compressedResults = toolResults.map { result -> ToolResult in
                guard result.output.count > maxToolOutputLength else {
                    return result
                }

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
}
