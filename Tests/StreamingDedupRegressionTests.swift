import XCTest
@testable import RioAgent

final class StreamingDedupRegressionTests: XCTestCase {
    func testConversationLoopDoesNotAppendDuplicateAssistantMessageWhenStreamingAlreadyRenderedContent() async throws {
        let engine = await MainActor.run { AgentEngine() }

        await MainActor.run {
            engine.appendMessage(.user("hello"))
        }

        try await ConversationLoop.run(engine: await MainActor.run { engine }) { _ in
            await MainActor.run {
                engine.appendMessage(
                    Message(
                        role: .assistant,
                        content: "streamed answer",
                        isStreaming: false
                    )
                )
            }

            return AIResponse(
                content: "streamed answer",
                reasoningContent: nil,
                toolCalls: nil,
                usage: nil
            )
        }

        let assistantMessages = await MainActor.run {
            engine.messages.filter { $0.role == .assistant }
        }

        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content, "streamed answer")
    }

    func testStreamingTextToolCallContentTriggersRedirectWithoutDuplicatingAssistantMessage() async throws {
        let engine = await MainActor.run { AgentEngine() }
        var invocationCount = 0

        await MainActor.run {
            engine.appendMessage(.user("检查项目结构"))
        }

        try await ConversationLoop.run(engine: await MainActor.run { engine }) { _ in
            invocationCount += 1

            if invocationCount == 1 {
                await MainActor.run {
                    engine.appendMessage(
                        Message(
                            role: .assistant,
                            content: "我先使用 list_directory 工具查看目录结构。",
                            isStreaming: false
                        )
                    )
                }

                return AIResponse(
                    content: "我先使用 list_directory 工具查看目录结构。",
                    reasoningContent: nil,
                    toolCalls: nil,
                    usage: nil
                )
            } else {
                return AIResponse(
                    content: nil,
                    reasoningContent: nil,
                    toolCalls: nil,
                    usage: nil
                )
            }
        }

        let allMessages = await MainActor.run { engine.messages }
        let assistantMessages = allMessages.filter { $0.role == .assistant }
        let correctionMessages = allMessages.filter { $0.role == .user && $0.content.contains("[System Correction]") }

        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content, "我先使用 list_directory 工具查看目录结构。")
        XCTAssertEqual(correctionMessages.count, 1)
    }
}
