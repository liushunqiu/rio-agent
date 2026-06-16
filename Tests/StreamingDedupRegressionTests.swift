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
                content: nil,
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
}
