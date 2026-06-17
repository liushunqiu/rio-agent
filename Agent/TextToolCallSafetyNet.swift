import Foundation

// MARK: - Text-based Tool Call Detection (Safety Net)
//
// Detects when the model outputs tool calls as text (e.g. XML-like tags)
// instead of using the structured function-calling API, and injects a
// corrective message so the model retries with proper tool calls.

extension AgentEngine {

    /// Maximum number of times we redirect the model away from text-based tool calls
    /// before accepting the response as-is.
    nonisolated static let maxTextToolCallRedirects = 2

    /// Known tool names in the registry (used for pattern matching).
    nonisolated private static let knownToolNames = [
        "read_file", "write_file", "execute_command", "edit_file",
        "list_directory", "search_files", "find_files", "apply_patch"
    ]

    /// Detect if the model output tool calls as text instead of using
    /// the structured function-calling API.
    ///
    /// Checks for patterns like:
    /// - XML-style tags such as `<functioncall>` or `<invoke>`
    /// - `tool_call` or `function_call` followed by JSON-like syntax
    /// - Natural language descriptions of tool invocations (e.g. "使用 list_directory 工具")
    nonisolated static func containsTextBasedToolCalls(_ content: String) -> Bool {
        let options: NSRegularExpression.Options = [.caseInsensitive]

        // ── Group A: Structured text patterns (XML tags, JSON labels) ─────────
        let structuredPatterns = [
            #"<\s*/?\s*(functioncall|function_call|function|tool_call|invoke|use_tool)\b"#,
            #"(?i)(tool_call|function_call|invoke_tool)\s*[:=]"#,
            #""name"\s*:\s*"(read_file|write_file|execute_command|edit_file|list_directory|search_files|find_files|apply_patch)""#
        ]
        for pattern in structuredPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options),
               regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                RioLogger.agent.debug("🔍 TextToolCallSafetyNet 匹配 Group A (结构化文本): \(pattern, privacy: .public)")
                return true
            }
        }

        // ── Group B: Tool names in invocation-like context ───────────────────
        // Matches tool names inside angle brackets, quotes with colon, or
        // parentheses — contexts that suggest actual invocation rather than
        // casual discussion.
        for tool in knownToolNames {
            let invocationPattern = #"[<(]\s*"# + tool + #"\b|""# + tool + #""\s*:"#
            if let regex = try? NSRegularExpression(pattern: invocationPattern, options: options),
               regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                RioLogger.agent.debug("🔍 TextToolCallSafetyNet 匹配 Group B (工具名上下文): \(tool, privacy: .public)")
                return true
            }
        }

        // ── Group C: Standalone tool name blocks ────────────────────────────
        // Catch markdown/code-block style pseudo-calls like:
        //
        // LIST_DIRECTORY
        // /path/to/project
        //
        // This is a strong signal even when the overall answer is long.
        let standaloneToolLinePattern = #"(?m)^\s*"# + toolNameAlternation() + #"\s*$"#
        if let regex = try? NSRegularExpression(pattern: standaloneToolLinePattern, options: options),
           regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            RioLogger.agent.debug("🔍 TextToolCallSafetyNet 匹配 Group C (独立工具名行)")
            return true
        }

        // ── Group C2: Markdown code-block pseudo-calls ─────────────────────
        // Catch patterns like:
        //   ```list_directory /path
        //   ```read_file
        //   ```execute_command ls
        let codeBlockToolPattern = #"(?m)```\s*"# + toolNameAlternation() + #"\b"#
        if let regex = try? NSRegularExpression(pattern: codeBlockToolPattern, options: options),
           regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            RioLogger.agent.debug("🔍 TextToolCallSafetyNet 匹配 Group C2 (Markdown 代码块)")
            return true
        }

        // ── Group D: Natural language tool-call intent ──────────────────────
        // Evaluate sentence/line-sized segments instead of gating on the whole
        // response length, so long answers still trigger when a specific
        // segment clearly describes an attempted tool invocation.
        let naturalLanguagePatterns = [
            // Chinese: "使用 X 工具", "调用 X", "让我用 X"
            #"(使用|调用|让我用|让我使用|先用|首先用)\s*\w*\s*"# + toolNameAlternation() + #"(\s*工具|\s*函数|\s*方法|\s*来|\s*查看|\s*检查|\s*读取|\s*执行)"#,
            // English: "use X tool", "call X", "let me use X"
            #"(?i)(use|call|invoke|let me (use|call|invoke)|first (use|call))\s+(the\s+)?"# + toolNameAlternation() + #"\b"#,
            // Chinese: "X 工具来/查看/读取/执行"
            toolNameAlternation() + #"\s*(工具|函数|方法)\s*(来|查看|检查|读取|执行|获取)"#,
        ]

        for segment in toolIntentSegments(from: content) {
            for pattern in naturalLanguagePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: options),
                   regex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)) != nil {
                    RioLogger.agent.debug("🔍 TextToolCallSafetyNet 匹配 Group D (自然语言): segment=\(segment.prefix(80), privacy: .public)")
                    return true
                }
            }
        }

        RioLogger.agent.debug("🔍 TextToolCallSafetyNet 未检测到文本形式的工具调用")
        return false
    }

    /// Build a regex alternation of known tool names for pattern matching.
    nonisolated private static func toolNameAlternation() -> String {
        "(" + knownToolNames.joined(separator: "|") + ")"
    }

    nonisolated private static func toolIntentSegments(from content: String) -> [String] {
        content
            .components(separatedBy: CharacterSet(charactersIn: "\n。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 240 }
    }

    /// Check whether the content looks like a text-based tool call attempt,
    /// and if so, inject a corrective system message so the model retries
    /// using the proper structured tool-calling API.
    ///
    /// Returns `true` if a redirect was injected (caller should `continue` the loop),
    /// or `false` if the content should be treated as a normal final response.
    func handleTextToolCallRedirect(_ content: String) -> Bool {
        guard textToolCallRedirectCount < Self.maxTextToolCallRedirects else {
            // Already redirected enough times; accept the response as-is
            RioLogger.agent.warning("⚠️ TextToolCallSafetyNet 已达最大重定向次数 (\(Self.maxTextToolCallRedirects))，接受当前响应")
            return false
        }

        guard Self.containsTextBasedToolCalls(content) else {
            return false
        }

        textToolCallRedirectCount += 1

        // In the streaming path the assistant message (with the text-based tool
        // call content) is already the last message in `messages`. Avoid adding a
        // duplicate — only append when the last message doesn't already carry the
        // same content.
        let lastIsSameAssistant = messages.last.map {
            $0.role == .assistant && !$0.content.isEmpty && content.hasPrefix(String($0.content.prefix(64)))
        } ?? false

        if !lastIsSameAssistant {
            messages.append(Message.assistant(content))
        }

        // Inject a corrective message
        let correctionMessage = Message.system("""
        [System Correction]
        你在回复中用文字描述了要使用工具（如 "使用 list_directory 工具"），但没有通过 API 的 function calling 接口实际调用它。
        You described using a tool in your text response but did NOT actually invoke it through the function-calling API.

        规则 / Rules:
        - 如果你需要使用任何工具，必须通过 function calling 机制发起调用，不能只在文本中提到工具名。
        - If you need to use any tool, you MUST invoke it via the function-calling mechanism — mentioning the tool name in text is NOT sufficient.
        - 如果不需要工具，直接给出文字回答即可。
        - If no tool is needed, simply respond with text.

        请立即通过 function calling 接口重新发起你刚才描述的工具调用。
        Please invoke the tool you described through the function-calling API now.
        """, presentation: .internalOnly)
        messages.append(correctionMessage)

        RioLogger.agent.warning("⚠️ 检测到文本形式的工具调用，已注入纠正提示（第 \(self.textToolCallRedirectCount) 次）")

        return true
    }
}
