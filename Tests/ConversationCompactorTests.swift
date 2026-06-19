import XCTest
@testable import RioAgent

final class ConversationCompactorTests: XCTestCase {
    func testRuleBasedCompactionPreservesAssistantProgressAndToolResults() async {
        let compactor = ConversationCompactor()
        let messages: [Message] = [
            .user("请优化登录流程"),
            Message(
                role: .assistant,
                content: "已经定位到 Views/LoginView.swift 的按钮状态和错误提示问题。",
                toolCalls: [ToolCall(id: "read-1", name: "read_file")]
            ),
            Message(
                role: .assistant,
                content: "准备继续检查 Keychain fallback。",
                toolResults: [.error(toolCallId: "read_file", error: "Permission denied reading Secrets.swift")]
            ),
            .user("最近的问题"),
            .assistant("最近的回答")
        ]

        let compacted = await compactor.compact(messages: messages, keepRecent: 2)

        XCTAssertEqual(compacted.count, 3)
        let summary = compacted[0].content
        XCTAssertTrue(summary.contains("助手结论/进展"))
        XCTAssertTrue(summary.contains("Views/LoginView.swift"))
        XCTAssertTrue(summary.contains("read_file"))
        XCTAssertTrue(summary.contains("关键工具结果"))
        XCTAssertTrue(summary.contains("Permission denied reading Secrets.swift"))
        XCTAssertEqual(compacted[1].content, "最近的问题")
        XCTAssertEqual(compacted[2].content, "最近的回答")
    }

    func testCompactionSkipsInternalOnlyMessagesInVisibleSummary() async {
        let compactor = ConversationCompactor()
        let messages: [Message] = [
            .user("公开需求"),
            Message.system("INTERNAL_SECRET_PLAN", presentation: .internalOnly),
            Message(
                role: .system,
                content: "",
                toolResults: [.success(toolCallId: "hidden", output: "INTERNAL_SECRET_TOOL_OUTPUT")],
                presentation: .internalOnly
            ),
            .assistant("最近的回答")
        ]

        let compacted = await compactor.compact(messages: messages, keepRecent: 1)
        let summary = compacted[0].content

        XCTAssertTrue(summary.contains("公开需求"))
        XCTAssertFalse(summary.contains("INTERNAL_SECRET_PLAN"))
        XCTAssertFalse(summary.contains("INTERNAL_SECRET_TOOL_OUTPUT"))
    }

    func testAICompactionPromptSkipsInternalOnlyMessages() async {
        let service = CapturingSummaryService()
        let compactor = ConversationCompactor(aiService: service, model: "summary-model")
        let messages: [Message] = [
            .user("公开需求"),
            Message.system("INTERNAL_SECRET_PLAN", presentation: .internalOnly),
            Message(
                role: .assistant,
                content: "",
                toolResults: [.error(toolCallId: "hidden", error: "INTERNAL_SECRET_ERROR")],
                presentation: .internalOnly
            ),
            .assistant("最近的回答")
        ]

        _ = await compactor.compact(messages: messages, keepRecent: 1)

        XCTAssertTrue(service.capturedPrompt.contains("公开需求"))
        XCTAssertFalse(service.capturedPrompt.contains("INTERNAL_SECRET_PLAN"))
        XCTAssertFalse(service.capturedPrompt.contains("INTERNAL_SECRET_ERROR"))
    }
}

private final class CapturingSummaryService: AIService {
    let provider: AIProvider = .openAI
    var capturedPrompt = ""

    func sendMessage(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int
    ) async throws -> AIResponse {
        capturedPrompt = messages.first?.content ?? ""
        return AIResponse(
            content: "AI summary",
            reasoningContent: nil,
            toolCalls: nil,
            usage: nil
        )
    }

    func sendMessageStreaming(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int,
        onChunk: @escaping (String) async -> Void,
        onThinkingChunk: @escaping (String) async -> Void
    ) async throws -> AIResponse {
        try await sendMessage(messages, tools: tools, model: model, maxTokens: maxTokens)
    }
}
