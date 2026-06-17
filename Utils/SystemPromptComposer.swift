import Foundation

enum SystemPromptScope {
    case singleAgent
    case orchestrator
    case worker(AgentCapability)
    case router
}

enum SystemPromptComposer {
    static func compose(
        basePrompt: String,
        scope: SystemPromptScope,
        availableTools: [Tool]
    ) -> String {
        let trimmedPrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return basePrompt }
        guard shouldApplyLayering(to: trimmedPrompt, scope: scope) else { return trimmedPrompt }

        let language = promptLanguage(for: trimmedPrompt)
        let layers = defaultLayers(for: scope)
        let renderedLayers = layers.compactMap { render($0, scope: scope, language: language, availableTools: availableTools) }

        guard !renderedLayers.isEmpty else { return trimmedPrompt }
        return ([trimmedPrompt] + renderedLayers).joined(separator: "\n\n")
    }

    private static func shouldApplyLayering(to prompt: String, scope: SystemPromptScope) -> Bool {
        switch scope {
        case .singleAgent:
            return AIConfiguration.builtInSingleAgentPrompts.contains(prompt)
        case .orchestrator:
            return MultiAgentConfig.isBuiltInOrchestratorPrompt(prompt)
        case .worker(let capability):
            return MultiAgentConfig.isBuiltInWorkerPrompt(prompt, capability: capability)
        case .router:
            return RouterConfig.builtInPrompts.contains(prompt)
        }
    }

    private static func defaultLayers(for scope: SystemPromptScope) -> [SystemPromptLayer] {
        switch scope {
        case .singleAgent:
            return [.responseContract, .evidenceRequirements, .toolDiscipline, .checkableStateRules, .availableTools]
        case .orchestrator:
            return [.responseContract, .evidenceRequirements]
        case .worker:
            return [.responseContract, .evidenceRequirements, .toolDiscipline, .checkableStateRules, .availableTools]
        case .router:
            return [.routingOutputContract]
        }
    }

    private static func render(
        _ layer: SystemPromptLayer,
        scope: SystemPromptScope,
        language: PromptLanguage,
        availableTools: [Tool]
    ) -> String? {
        switch layer {
        case .responseContract:
            switch language {
            case .english:
                return """
                Response contract:
                - Reply in the user's language.
                - Start with the answer, result, or current execution status.
                - Keep formatting light unless structure clearly improves readability.
                """
            case .chinese:
                return """
                回答约定：
                - 使用与用户相同的语言回答。
                - 第一段先给答案、结果或当前执行状态。
                - 仅在确实提升可读性时使用列表或额外格式。
                """
            }

        case .evidenceRequirements:
            switch language {
            case .english:
                return """
                Evidence policy:
                - Separate observed facts from inference.
                - Do not claim completion, success, or verification without evidence from this conversation.
                - If a result is not checked, state that it is unverified instead of implying success.
                """
            case .chinese:
                return """
                证据规则：
                - 区分“已观察到的事实”和“推断”。
                - 没有本轮对话中的工具证据时，不要声称已完成、已修复或已验证。
                - 如果结果尚未检查，明确写“未验证”，不要暗示成功。
                """
            }

        case .toolDiscipline:
            switch language {
            case .english:
                return """
                Tool discipline:
                - You MUST use the structured tool-calling API (function calling) to invoke tools. NEVER output tool calls as text, XML tags, or any other plain-text format.
                - Explore before editing, and read before writing.
                - Prefer precise edits over broad rewrites when touching existing files.
                - After changes, verify with a read-back, test, or command when one is available.
                - If the same approach fails repeatedly, stop and change strategy.
                """
            case .chinese:
                return """
                工具纪律：
                - 必须通过 API 的结构化 tool call（function calling）机制调用工具。严禁以文本、XML 标签或任何其他纯文本格式输出工具调用。
                - 先探索后修改，先读取再写入。
                - 修改现有文件时，优先做精确变更，避免大面积重写。
                - 改动后尽量通过读回、测试或命令结果做验证。
                - 同一路径连续失败时，停止重复尝试并切换策略。
                """
            }

        case .checkableStateRules:
            switch language {
            case .english:
                return """
                Checkable-state rules:
                - When a claim depends on the current repository state, file contents, command output, or any other tool-observable fact, check it before answering.
                - If the necessary check is unavailable or incomplete, say what remains unverified.
                """
            case .chinese:
                return """
                可检查状态规则：
                - 当结论依赖当前仓库状态、文件内容、命令输出或其他可通过工具观察的事实时，先检查再回答。
                - 如果无法完成必要检查，明确说明哪些内容仍未验证。
                """
            }

        case .availableTools:
            guard !availableTools.isEmpty else { return nil }
            let toolLines = availableTools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
            switch language {
            case .english:
                return """
                Available tools (invoke via the function-calling API, never as text):
                \(toolLines)
                """
            case .chinese:
                return """
                可用工具（必须通过 function-calling API 调用，禁止以文本形式输出）：
                \(toolLines)
                """
            }

        case .routingOutputContract:
            switch language {
            case .english:
                return """
                Routing output contract:
                - Return strict JSON only.
                - Do not add markdown fences, explanations, or extra prose.
                - If uncertain, still choose the closest route and lower confidence.
                """
            case .chinese:
                return """
                路由输出约定：
                - 只输出严格 JSON。
                - 不要添加 Markdown 代码块、解释性文字或额外 prose。
                - 即使不确定，也要选择最接近的路由目标，并降低置信度。
                """
            }
        }
    }

    private static func promptLanguage(for prompt: String) -> PromptLanguage {
        prompt.range(of: #"[一-龥]"#, options: .regularExpression) == nil ? .english : .chinese
    }
}

private enum PromptLanguage {
    case english
    case chinese
}
