import Foundation
import os

// MARK: - AI Response Fetcher

/// Abstraction over streaming vs non-streaming AI calls.
/// The caller provides a closure that, given context messages, returns an `AIResponse`.
/// For streaming, the closure internally manages message buffer updates via side effects.
typealias AIResponseFetcher = (_ contextMessages: [Message]) async throws -> AIResponse

// MARK: - Conversation Loop (shared between streaming & non-streaming paths)

enum ConversationLoop {

    /// Unified agent conversation loop.
    ///
    /// Both streaming and non-streaming execution paths share identical logic for:
    /// - Iteration & cancellation control
    /// - Tool call dispatch and result processing
    /// - Error tracking, critic escalation, and plan advancement
    ///
    /// The only difference is the `fetchResponse` closure that abstracts the AI call.
    @MainActor
    static func run(
        engine: AgentEngine,
        fetchResponse: @escaping AIResponseFetcher
    ) async throws {
        var iterationCount = 0
        var consecutiveErrors = 0

        while true {
            guard !engine.isCancelledFlag else { break }

            iterationCount += 1
            guard iterationCount <= AgentEngine.maxIterations else {
                let warning = Message.system(
                    "⚠️ 已达到最大工具调用次数上限（\(AgentEngine.maxIterations) 次），已自动停止。如需继续，请直接描述下一步操作。"
                )
                engine.appendMessage(warning)
                break
            }

            // ── AI Call ──────────────────────────────────────────────
            let contextMessages = engine.buildContextMessages()
            RioLogger.agent.debug("🔄 ConversationLoop 第 \(iterationCount) 轮迭代，上下文消息数: \(contextMessages.count)")
            let response = try await fetchResponse(contextMessages)

            engine.trackTokenUsage(response.usage)

            // ── Tool Calls ───────────────────────────────────────────
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                let toolNames = toolCalls.map { $0.name }.joined(separator: ", ")
                RioLogger.agent.info("🔧 第 \(iterationCount) 轮: 收到 \(toolCalls.count) 个工具调用 [\(toolNames)]")
                let results = await engine.executeToolCalls(toolCalls)

                // Error tracking
                let hasErrors = results.contains { $0.status == .error }
                if hasErrors {
                    consecutiveErrors += 1
                    RioLogger.agent.warning("⚠️ 第 \(iterationCount) 轮: 工具执行有错误，连续错误次数: \(consecutiveErrors)")
                    if consecutiveErrors >= AgentEngine.maxConsecutiveErrors {
                        let msg = Message.system(
                            "⚠️ 连续 \(consecutiveErrors) 次工具执行错误，已自动停止。请检查错误信息后重试。"
                        )
                        engine.appendMessage(msg)
                        break
                    }
                } else {
                    consecutiveErrors = 0
                    engine.advancePlanStep()
                }

                // Error reflection + critic escalation
                let reflection = await engine.buildToolResultReflection(
                    toolCalls: toolCalls,
                    results: results,
                    consecutiveErrors: consecutiveErrors
                )

                let resultMessage = Message(
                    role: .system,
                    content: reflection.isEmpty ? "" : "[Tool Execution Results with Analysis]",
                    toolResults: results,
                    presentation: .internalOnly
                )
                engine.appendMessage(resultMessage)
                continue
            }

            // ── No Tool Calls ──────────────────────────────────────
            // Safety net: detect when the model outputs tool calls as text
            // (XML-like tags) instead of using the structured API, and redirect.
            if let content = response.content, !content.isEmpty,
               engine.handleTextToolCallRedirect(content) {
                RioLogger.agent.warning("⚠️ 第 \(iterationCount) 轮: 检测到文本形式的工具调用，已注入纠正提示")
                continue
            }

            // ── Task complete ────────────────────────────────────────
            RioLogger.agent.info("✅ 第 \(iterationCount) 轮: 无工具调用，任务完成")
            let finalized = await engine.handleFinalContent(response.content)
            if finalized {
                engine.clearPlan()
                break
            }
        }
    }
}
