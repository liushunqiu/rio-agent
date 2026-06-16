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
}
