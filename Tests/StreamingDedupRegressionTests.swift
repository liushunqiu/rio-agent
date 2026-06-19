import XCTest
@testable import RioAgent

final class StreamingDedupRegressionTests: XCTestCase {
    func testConversationLoopDoesNotAppendDuplicateAssistantMessageWhenStreamingAlreadyRenderedContent() async throws {
        let engine = await MainActor.run { makeIsolatedAgentEngine(testCase: self) }

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
        let engine = await MainActor.run { makeIsolatedAgentEngine(testCase: self) }
        var invocationCount = 0

        await MainActor.run {
            ToolRegistry.shared.register(CancelledLoopTestTool())
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
                    toolCalls: [
                        ToolCall(id: "cancelled-command", name: "cancel_test_tool")
                    ],
                    usage: nil
                )
            }
        }

        let allMessages = await MainActor.run { engine.messages }
        let assistantMessages = allMessages.filter { $0.role == .assistant }
        let visibleAssistantMessages = assistantMessages.filter(\.isVisibleInTranscript)
        let correctionMessages = allMessages.filter {
            $0.role == .system
                && $0.presentation == .internalOnly
                && $0.content.contains("[System Correction]")
        }

        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content, "我先使用 list_directory 工具查看目录结构。")
        XCTAssertTrue(visibleAssistantMessages.isEmpty)
        XCTAssertEqual(correctionMessages.count, 1)
    }

    func testConversationLoopRejectsEmptyFinalResponse() async throws {
        let engine = await MainActor.run { makeIsolatedAgentEngine(testCase: self) }

        await MainActor.run {
            engine.appendMessage(.user("请分析当前项目"))
        }

        do {
            try await ConversationLoop.run(engine: await MainActor.run { engine }) { _ in
                AIResponse(
                    content: "  \n",
                    reasoningContent: nil,
                    toolCalls: nil,
                    usage: nil
                )
            }
            XCTFail("Expected empty final response to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("模型返回了空响应"))
        }

        let assistantMessages = await MainActor.run {
            engine.messages.filter { $0.role == .assistant }
        }
        XCTAssertTrue(assistantMessages.isEmpty)
    }

    func testConversationLoopStopsAfterCancelledToolResult() async throws {
        let engine = await MainActor.run { makeIsolatedAgentEngine(testCase: self) }
        var invocationCount = 0

        await MainActor.run {
            ToolRegistry.shared.register(CancelledLoopTestTool())
            engine.appendMessage(.user("run command"))
        }

        try await ConversationLoop.run(engine: await MainActor.run { engine }) { _ in
            invocationCount += 1
            return AIResponse(
                content: nil,
                reasoningContent: nil,
                toolCalls: [
                    ToolCall(id: "cancelled-command", name: "cancel_test_tool")
                ],
                usage: nil
            )
        }

        let toolResultMessages = await MainActor.run {
            engine.messages.filter { $0.toolResults != nil }
        }

        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(toolResultMessages.count, 1)
        XCTAssertEqual(toolResultMessages.first?.toolResults?.first?.status, .cancelled)
    }
}

private struct CancelledLoopTestTool: Tool {
    let name = "cancel_test_tool"
    let description = "Cancellation test tool"
    let parameters: [String: ToolParameter] = [:]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        ToolResult.cancelled(toolCallId: name, reason: "用户停止任务")
    }
}

final class ConversationLoopSourceTests: XCTestCase {
    func testStreamingPlaceholderMutationsAreGuardedByMessageId() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        XCTAssertTrue(
            source.contains("let messageId = streamingMessage.id")
                && source.contains("self.messages[streamingIndex].id == messageId"),
            "Streaming updates should verify the placeholder id instead of trusting a stale array index after conversation switches."
        )
        XCTAssertTrue(
            source.contains("if isCurrentStreamingMessage() {\n                    self.messages.remove(at: streamingIndex)\n                }\n                throw error"),
            "Streaming error cleanup should not remove a message from a newly loaded conversation at the same index."
        )
    }

    func testCancelledToolResultsDoNotAdvancePlanSteps() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/ConversationLoop.swift"))

        XCTAssertTrue(
            source.contains("let hasCancelled = results.contains { $0.status == .cancelled }"),
            "ConversationLoop should explicitly distinguish cancelled tool results from successful results."
        )
        XCTAssertTrue(
            source.contains("} else if hasCancelled {"),
            "Cancelled tool results should take a separate branch before plan advancement."
        )
        XCTAssertTrue(
            source.contains("if hasCancelled {\n                    break\n                }\n                continue"),
            "Cancelled tool results should stop the loop after preserving the result message."
        )
        XCTAssertTrue(
            source.contains("throw AIServiceError.emptyResponse"),
            "Empty model responses should stop with a visible error instead of being treated as task completion."
        )

        let cancelledBranch = try XCTUnwrap(source.range(of: "} else if hasCancelled {"))
        let advanceCall = try XCTUnwrap(source.range(of: "engine.advancePlanStep()"))
        XCTAssertLessThan(
            cancelledBranch.lowerBound,
            advanceCall.lowerBound,
            "The cancelled branch should be evaluated before advancePlanStep is reachable."
        )
    }
}
