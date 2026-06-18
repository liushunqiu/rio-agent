import XCTest

final class NewChatPendingDecisionSourceTests: XCTestCase {
    func testNewChatPageMatchesComposerPendingDecisionHints() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let newChatSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift"))
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            newChatSource.contains("let pendingUserDecision: AgentEngine.PendingUserDecision?"),
            "NewChatPage should receive pending confirmation state instead of showing the normal empty-task prompt."
        )
        XCTAssertTrue(
            contentSource.contains("pendingUserDecision: agentEngine.pendingUserDecision"),
            "ContentView should pass pending confirmation state into the new-chat entry point."
        )
        XCTAssertTrue(
            contentSource.contains("canAcceptInput: agentEngine.canAcceptUserInput"),
            "The landing-page composer should share the same input-acceptance gate as the main composer."
        )
        XCTAssertTrue(
            newChatSource.contains("输入“是”覆盖，输入“否”取消，或直接写新任务"),
            "NewChatPage should explain overwrite confirmation responses."
        )
        XCTAssertTrue(
            newChatSource.contains("输入“是”用 Multi-Agent，输入“否”改单 Agent，或直接写新任务"),
            "NewChatPage should explain execution-mode confirmation responses."
        )
        XCTAssertTrue(
            newChatSource.contains(".disabled(pendingUserDecision != nil)"),
            "Quick prompts should not overwrite an active confirmation flow."
        )
        XCTAssertTrue(
            newChatSource.contains("提交回复或新任务 (Cmd+Return)"),
            "The send button help should clarify pending-confirmation submissions."
        )
        XCTAssertTrue(
            newChatSource.contains("private var canSend: Bool {\n        composer.canSend && canAcceptInput\n    }"),
            "NewChatPage should not present an active send button when the engine cannot accept input."
        )
        XCTAssertTrue(
            newChatSource.contains(".disabled(!canSend)"),
            "The landing-page send button should use the same gated canSend state as the main composer."
        )
        XCTAssertTrue(
            newChatSource.contains(".foregroundColor(canSend ? .white : Theme.textTertiary)"),
            "The landing-page send button styling should follow the same gated state instead of advertising a rejected submission as active."
        )
    }
}
