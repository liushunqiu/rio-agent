import XCTest
@testable import RioAgent

@MainActor
final class AgentEngineRegressionTests: XCTestCase {

    func testContextMessagesReflectUpdatedWorkingDirectoryAfterInitialBuild() {
        let engine = AgentEngine()
        engine.appendMessage(.user("hello"))

        let initialSystemPrompt = engine.buildContextMessages().first?.content ?? ""
        XCTAssertFalse(initialSystemPrompt.contains("Working directory:"))

        engine.workingDirectory = "/tmp/rio-agent-project"

        let updatedSystemPrompt = engine.buildContextMessages().first?.content ?? ""
        XCTAssertTrue(updatedSystemPrompt.contains("Working directory: /tmp/rio-agent-project"))
    }

    func testClearConversationResetsUsageTracking() {
        let engine = AgentEngine()

        engine.trackTokenUsage(.init(promptTokens: 120, completionTokens: 45))
        XCTAssertGreaterThan(engine.sessionCost, 0)
        XCTAssertFalse(engine.getSessionUsageSummary().isEmpty)

        engine.clearConversation()

        XCTAssertEqual(engine.sessionCost, 0)
        XCTAssertEqual(engine.getSessionUsageSummary(), "")
        XCTAssertEqual(engine.getTotalTokensUsed(), 0)
    }

    func testLoadConversationResetsUsageTracking() {
        let engine = AgentEngine()

        engine.trackTokenUsage(.init(promptTokens: 80, completionTokens: 20))
        XCTAssertGreaterThan(engine.sessionCost, 0)

        let conversation = Conversation(
            messages: [.user("restored message")],
            workingDirectory: "/tmp/restored"
        )
        engine.loadConversation(conversation)

        XCTAssertEqual(engine.sessionCost, 0)
        XCTAssertEqual(engine.getSessionUsageSummary(), "")
        XCTAssertEqual(engine.workingDirectory, "/tmp/restored")
    }

    func testContextMessagesHonorConfiguredMessageLimit() {
        let engine = AgentEngine()

        engine.appendMessage(.system("system note"))
        engine.appendMessage(.user("first"))
        engine.appendMessage(.assistant("second"))
        engine.appendMessage(.user("third"))
        engine.appendMessage(.assistant("fourth"))

        var config = engine.configuration
        config.maxContextMessages = 2
        engine.updateConfiguration(config)

        let contextMessages = engine.buildContextMessages()

        XCTAssertEqual(contextMessages.count, 3)
        XCTAssertEqual(contextMessages.dropFirst().map(\.content), ["third", "fourth"])
    }

    func testManualTaskSplitStrategyPromptsBeforeStartingMultiAgent() async {
        let engine = AgentEngine()
        var config = engine.multiAgentConfig
        config.taskSplitStrategy = .manual
        engine.updateMultiAgentConfig(config)

        await engine.processUserInput("请分析这个项目并修改多个文件后再测试")

        XCTAssertFalse(engine.isProcessing)
        XCTAssertTrue(engine.messages.contains {
            $0.role == .system && $0.content.contains("适合 Multi-Agent 协作")
        })
        XCTAssertTrue(engine.messages.contains {
            $0.role == .user && $0.content == "请分析这个项目并修改多个文件后再测试"
        })
    }

    func testOlderLargeToolOutputsAreCompressedButRecentOnesStayIntact() {
        let engine = AgentEngine()
        let largeOutput = String(repeating: "0123456789", count: 300)
        var config = engine.configuration
        config.maxContextMessages = 999
        engine.updateConfiguration(config)

        engine.appendMessage(Message(
            role: .user,
            content: "",
            toolResults: [ToolResult.success(toolCallId: "older", output: largeOutput)]
        ))
        engine.appendMessage(.assistant("filler-1"))
        engine.appendMessage(.user("filler-2"))
        engine.appendMessage(.assistant("middle"))
        engine.appendMessage(Message(
            role: .user,
            content: "",
            toolResults: [ToolResult.success(toolCallId: "recent", output: largeOutput)]
        ))

        let contextMessages = engine.buildContextMessages()
        let toolMessages = contextMessages.filter { $0.toolResults != nil }

        XCTAssertEqual(toolMessages.count, 2)
        guard toolMessages.count == 2 else { return }
        XCTAssertTrue(toolMessages[0].toolResults?.first?.output.contains("[... truncated") == true)
        XCTAssertFalse(toolMessages[1].toolResults?.first?.output.contains("[... truncated") == true)
    }

    func testHandleFinalContentSkipsVerificationWhenNoToolEvidenceExists() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("just chat")

        let finalized = await engine.handleFinalContent("这是普通回答。")

        XCTAssertTrue(finalized)
        XCTAssertEqual(engine.messages.last?.content, "这是普通回答。")
    }

    func testHandleFinalContentAppendsUnverifiedNoteWhenEvidenceIsWeak() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("修改文件")

        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.success(toolCallId: "1", output: "")],
            consecutiveErrors: 0
        )

        let finalized = await engine.handleFinalContent("已完成修改。")

        XCTAssertTrue(finalized)
        XCTAssertTrue(engine.messages.last?.content.contains("未验证说明") == true)
    }

    func testHandleFinalContentRequestsRevisionWhenVerifierNeedsRetry() async {
        let engine = AgentEngine()
        engine.memory.setCurrentTask("运行测试")

        _ = await engine.buildToolResultReflection(
            toolCalls: [ToolCall(name: "execute_command")],
            results: [ToolResult.error(toolCallId: "1", error: "exit code 1")],
            consecutiveErrors: 1
        )

        let finalized = await engine.handleFinalContent("测试已经通过。")

        XCTAssertFalse(finalized)
        XCTAssertTrue(engine.messages.last?.role == .user)
        XCTAssertTrue(engine.messages.last?.content.contains("[Verification Audit]") == true)
    }
}
