import Foundation

/// Audits whether a task result is actually supported by execution evidence.
/// Unlike Critic, this service does not try to repair failures; it classifies result confidence.
class VerifierService {
    struct VerificationOutcome {
        let status: VerificationStatus
        let summary: String
    }

    private let aiService: AIService?
    private let model: String
    private let maxTokens: Int

    init(aiService: AIService?, model: String, maxTokens: Int = 1200) {
        self.aiService = aiService
        self.model = model
        self.maxTokens = maxTokens
    }

    func verify(
        task: String,
        output: String,
        errors: [String],
        evidence: [String],
        systemPrompt: String?
    ) async -> VerificationOutcome {
        if !errors.isEmpty {
            return VerificationOutcome(
                status: .needsRetry,
                summary: "执行期间存在错误，当前结果不能视为已验证完成。"
            )
        }

        let trimmedEvidence = evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedEvidence.isEmpty else {
            return VerificationOutcome(
                status: .unverified,
                summary: "没有收集到可审计的工具证据，结果暂时只能视为未验证。"
            )
        }

        guard let aiService else {
            return heuristicVerification(output: output, evidence: trimmedEvidence)
        }

        let prompt = buildPrompt(
            task: task,
            output: output,
            evidence: trimmedEvidence,
            systemPrompt: systemPrompt
        )

        do {
            let response = try await aiService.sendMessage(
                [Message.system(prompt)],
                tools: [],
                model: model,
                maxTokens: maxTokens
            )

            if let content = response.content,
               let outcome = parseOutcome(from: content) {
                return outcome
            }
        } catch {
            return heuristicVerification(output: output, evidence: trimmedEvidence)
        }

        return heuristicVerification(output: output, evidence: trimmedEvidence)
    }

    private func heuristicVerification(output: String, evidence: [String]) -> VerificationOutcome {
        let lower = output.lowercased()
        let hasWeakLanguage = lower.contains("应该") || lower.contains("可能") || lower.contains("probably")
        let hasConcreteEvidence = evidence.contains { item in
            item.contains("SUCCESS")
                && !item.contains("evidence=（空输出）")
                || item.contains("ERROR")
                || item.contains("tool=")
                || item.contains("read_file")
                || item.contains("execute_command")
        }
        let hasNonEmptyEvidence = evidence.contains { !$0.contains("evidence=（空输出）") }

        if hasConcreteEvidence && hasNonEmptyEvidence && !hasWeakLanguage {
            return VerificationOutcome(
                status: .verified,
                summary: "结果有工具证据支撑，且输出未出现明显的猜测性表述。"
            )
        }

        return VerificationOutcome(
            status: .unverified,
            summary: "结果缺少足够强的完成证据，建议补充读回、测试或命令验证。"
        )
    }

    private func buildPrompt(
        task: String,
        output: String,
        evidence: [String],
        systemPrompt: String?
    ) -> String {
        let truncatedOutput = output.count > 2500
            ? String(output.prefix(2500)) + "\n[... 已截断 ...]"
            : output

        let evidenceText = evidence
            .prefix(12)
            .joined(separator: "\n\n")

        var prompt = """
        你是一个验证器（Verifier）。你的职责不是修复问题，而是审计“当前任务结果是否真的被证据支持”。

        请根据任务描述、执行结果和工具证据，判断该结果属于以下哪一种：
        - VERIFIED: 结果已被充分证据支持
        - UNVERIFIED: 没有足够证据证明完成，但也没有明确执行错误
        - NEEDS_RETRY: 结果与证据冲突，或证据显示任务实际上未完成

        <task>
        \(task)
        </task>

        """

        if let systemPrompt, !systemPrompt.isEmpty {
            prompt += """
            <worker_system_prompt>
            \(systemPrompt)
            </worker_system_prompt>

            """
        }

        prompt += """
        <result>
        \(truncatedOutput)
        </result>

        <evidence>
        \(evidenceText)
        </evidence>

        输出格式必须严格如下：
        STATUS: VERIFIED|UNVERIFIED|NEEDS_RETRY
        SUMMARY: 一句话总结判断依据

        判断标准：
        - 只有在证据足够支撑完成声明时，才能给 VERIFIED
        - 如果结果像是计划、猜测、预期，或缺少读回/测试/命令证据，应给 UNVERIFIED
        - 如果结果声称完成，但证据显示失败、冲突或缺失关键步骤，应给 NEEDS_RETRY
        """

        return prompt
    }

    private func parseOutcome(from content: String) -> VerificationOutcome? {
        let lines = content.components(separatedBy: .newlines)
        let statusLine = lines.first { $0.uppercased().hasPrefix("STATUS:") }
        let summaryLine = lines.first { $0.uppercased().hasPrefix("SUMMARY:") }

        guard let statusLine, let summaryLine else { return nil }

        let rawStatus = statusLine
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let summary = summaryLine
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let status: VerificationStatus
        switch rawStatus {
        case "VERIFIED":
            status = .verified
        case "NEEDS_RETRY":
            status = .needsRetry
        case "UNVERIFIED":
            status = .unverified
        default:
            return nil
        }

        return VerificationOutcome(
            status: status,
            summary: summary.isEmpty ? "验证器未返回摘要。" : summary
        )
    }
}
