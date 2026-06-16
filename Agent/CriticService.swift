import Foundation

/// 独立的 Critic 服务，分析执行错误并生成修复建议。
/// 支持单模型和多模型串行审查模式（主模型 -> 备用模型）。
/// 被单 Agent 和多 Agent 执行路径共享。
class CriticService {
    /// 主 Critic AI 服务
    private let aiService: AIService?
    /// 主 Critic 模型名称
    private let model: String
    /// 最大 token 数
    private let maxTokens: Int

    /// 备用 Critic AI 服务（串行降级，当主模型失败或输出质量不足时使用）
    private let secondaryService: AIService?
    /// 备用 Critic 模型名称
    private let secondaryModel: String?

    // MARK: - 初始化

    /// 单模型初始化（向后兼容）
    /// - Parameters:
    ///   - aiService: AI 服务实例
    ///   - model: 模型名称
    ///   - maxTokens: 最大 token 数，默认 2000
    init(aiService: AIService?, model: String, maxTokens: Int = 2000) {
        self.aiService = aiService
        self.model = model
        self.maxTokens = maxTokens
        self.secondaryService = nil
        self.secondaryModel = nil
    }

    /// 多模型串行审查初始化
    /// 先使用主模型进行审查，若主模型失败或输出质量不足（少于 50 字符），
    /// 则串行降级到备用模型。若两者均成功，则合并两份分析结果。
    /// - Parameters:
    ///   - aiService: 主 AI 服务实例
    ///   - model: 主模型名称
    ///   - secondaryService: 备用 AI 服务实例（可选）
    ///   - secondaryModel: 备用模型名称（可选）
    ///   - maxTokens: 最大 token 数，默认 2000
    init(
        aiService: AIService?,
        model: String,
        secondaryService: AIService?,
        secondaryModel: String?,
        maxTokens: Int = 2000
    ) {
        self.aiService = aiService
        self.model = model
        self.secondaryService = secondaryService
        self.secondaryModel = secondaryModel
        self.maxTokens = maxTokens
    }

    // MARK: - 核心分析

    /// 分析错误并生成可操作的修复建议（串行多模型审查）。
    ///
    /// 执行流程：
    /// 1. 首先尝试主 Critic 模型
    /// 2. 若主模型失败或输出质量不足（< 50 字符），尝试备用模型
    /// 3. 若两者均成功产出高质量分析，调用 mergeCriticAnalyses() 合并结果
    /// - Parameters:
    ///   - task: 原始任务描述
    ///   - errors: 执行过程中遇到的错误列表
    ///   - output: 执行输出内容
    ///   - systemPrompt: Worker 的系统提示词（可选）
    /// - Returns: 修复建议文本
    func analyze(task: String, errors: [String], output: String, systemPrompt: String?) async -> String {
        guard !errors.isEmpty else {
            return fallbackFeedback(errors: errors)
        }

        let prompt = buildCriticPrompt(
            task: task, errors: errors, output: output, systemPrompt: systemPrompt
        )

        // 第一步：尝试主模型
        let primaryResult: String? = await callCriticModel(
            service: aiService, model: model, prompt: prompt, errors: errors
        )

        // 如果没有配置备用模型，直接返回主模型结果
        guard let secondaryService, let secondaryModel else {
            return primaryResult ?? fallbackFeedback(errors: errors)
        }

        // 判断主模型输出是否为高质量（>= 50 字符）
        let primaryIsHighQuality = primaryResult.map { $0.count >= 50 } ?? false

        // 第二步：串行调用备用模型（无论主模型是否成功，均尝试获取第二份审查意见用于合并）
        let secondaryResult = await callCriticModel(
            service: secondaryService, model: secondaryModel, prompt: prompt, errors: errors
        )

        // 第三步：根据结果决定最终输出
        switch (primaryIsHighQuality, secondaryResult.map({ $0.count >= 50 }) ?? false) {
        case (true, true):
            // 两者均产出高质量分析，合并两份结果
            return await mergeCriticAnalyses(
                primaryAnalysis: primaryResult!,
                secondaryAnalysis: secondaryResult!,
                errors: errors
            )
        case (true, false):
            // 仅主模型高质量，直接返回主模型结果
            return primaryResult!
        case (false, true):
            // 仅备用模型高质量，返回备用模型结果
            return secondaryResult!
        case (false, false):
            // 两者均未产出高质量结果，降级为基础反馈
            return fallbackFeedback(errors: errors)
        }
    }

    // MARK: - 模型调用辅助方法

    /// 调用单个 Critic 模型并返回结果。
    /// - Parameters:
    ///   - service: AI 服务实例
    ///   - model: 模型名称
    ///   - prompt: 构建好的审查提示词
    ///   - errors: 错误列表（用于降级反馈）
    /// - Returns: 模型输出的分析结果，失败时返回 nil
    private func callCriticModel(
        service: AIService?, model: String, prompt: String, errors: [String]
    ) async -> String? {
        guard let service else { return nil }
        do {
            let response = try await service.sendMessage(
                [Message.system(prompt)], tools: [], model: model, maxTokens: maxTokens
            )
            return response.content
        } catch {
            return nil
        }
    }

    // MARK: - 分析合并

    /// 合并两份 Critic 分析结果。
    /// 使用主模型对两份专家审查进行综合，提取两者最佳洞察。
    /// 若合并调用失败，则直接返回主模型的分析结果作为降级。
    /// - Parameters:
    ///   - primaryAnalysis: 主模型的审查结果
    ///   - secondaryAnalysis: 备用模型的审查结果
    ///   - errors: 原始错误列表
    /// - Returns: 合并后的修复建议
    private func mergeCriticAnalyses(
        primaryAnalysis: String,
        secondaryAnalysis: String,
        errors: [String]
    ) async -> String {
        guard let aiService else {
            return primaryAnalysis
        }

        let mergePrompt = """
        你收到了两位专家对同一组错误的独立审查报告。请综合两份报告中的最佳洞察，合并为一份统一的修复指导。

        <errors>
        \(errors.joined(separator: "\n"))
        </errors>

        <expert_review_1>
        \(primaryAnalysis)
        </expert_review_1>

        <expert_review_2>
        \(secondaryAnalysis)
        </expert_review_2>

        请合并两份审查：
        1. 提取两者对根因分析的一致观点
        2. 综合两者的修复建议，去除重复项，保留最有价值的建议
        3. 如果两份审查存在分歧，指出分歧点并给出你的判断

        输出简洁的合并修复指导。不要写代码，只写指导。
        """

        do {
            let response = try await aiService.sendMessage(
                [Message.system(mergePrompt)], tools: [], model: model, maxTokens: maxTokens
            )
            return response.content ?? primaryAnalysis
        } catch {
            // 合并调用失败，降级返回主模型分析结果
            return primaryAnalysis
        }
    }

    // MARK: - 提示词构建

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
