import Foundation

/// Standalone Critic service that analyzes execution errors and generates fix suggestions.
/// Shared by both single-agent and multi-agent execution paths.
class CriticService {
    private let aiService: AIService?
    private let model: String
    private let maxTokens: Int

    init(aiService: AIService?, model: String, maxTokens: Int = 2000) {
        self.aiService = aiService
        self.model = model
        self.maxTokens = maxTokens
    }

    /// Analyze errors and generate actionable fix suggestions using the Critic model.
    func analyze(task: String, errors: [String], output: String, systemPrompt: String?) async -> String {
        guard let aiService, !errors.isEmpty else {
            return fallbackFeedback(errors: errors)
        }

        let prompt = buildCriticPrompt(
            task: task, errors: errors, output: output, systemPrompt: systemPrompt
        )

        do {
            let response = try await aiService.sendMessage(
                [Message.system(prompt)], tools: [], model: model, maxTokens: maxTokens
            )
            return response.content ?? fallbackFeedback(errors: errors)
        } catch {
            return fallbackFeedback(errors: errors)
        }
    }

    private func buildCriticPrompt(
        task: String, errors: [String], output: String, systemPrompt: String?
    ) -> String {
        let truncatedOutput = output.count > 3000
            ? String(output.prefix(3000)) + "\n[... 已截断 ...]"
            : output

        var prompt = """
        你是一个代码审查专家（Critic）。执行任务时遇到了错误。请分析错误原因并给出具体的修复建议。

        <original_task>
        \(task)
        </original_task>

        """

        if let systemPrompt {
            prompt += """
            <worker_system_prompt>
            \(systemPrompt)
            </worker_system_prompt>

            """
        }

        prompt += """
        <execution_output>
        \(truncatedOutput)
        </execution_output>

        <errors>
        \(errors.joined(separator: "\n"))
        </errors>

        请分析：
        1. 错误的根本原因是什么？
        2. 具体的修复建议（下一步应该怎么做）
        3. 需要避免的常见陷阱

        输出简洁的修复指导，这将作为下一次尝试的补充指令。不要写代码，只写指导。
        """
        return prompt
    }

    /// Fallback pattern-based feedback when the Critic AI service is unavailable.
    func fallbackFeedback(errors: [String]) -> String {
        var feedback = "执行过程中遇到以下错误，请逐一分析并修复：\n\n"
        for (i, error) in errors.enumerated() {
            feedback += "\(i + 1). \(error)\n"
            let lower = error.lowercased()
            if lower.contains("file not found") || lower.contains("no such file") {
                feedback += "   → 建议：先用 find_files 搜索文件名，或用 list_directory 确认目录存在\n"
            } else if lower.contains("permission denied") {
                feedback += "   → 建议：检查文件权限 (ls -la)，可能需要用户确认\n"
            } else if lower.contains("old_text") && (lower.contains("not found") || lower.contains("no match")) {
                feedback += "   → 建议：先用 read_file 读取文件最新内容，确认 old_text 精确匹配\n"
            } else if lower.contains("command not found") {
                feedback += "   → 建议：检查命令是否已安装 (which <cmd>)\n"
            } else if lower.contains("syntax error") || lower.contains("parse error") {
                feedback += "   → 建议：用 read_file 检查最近修改的文件，找到并修复语法错误\n"
            } else if lower.contains("module") && lower.contains("not found") {
                feedback += "   → 建议：运行包管理器安装依赖\n"
            }
        }
        return feedback
    }
}
