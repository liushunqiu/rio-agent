import XCTest

final class ConversationPersistenceSourceTests: XCTestCase {
    func testConversationPersistenceFlushesBeforeLifecycleExit() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/ConversationManager.swift"))
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            managerSource.contains("func flushPendingSave()"),
            "ConversationManager should expose an immediate save path for app lifecycle events."
        )
        XCTAssertTrue(
            managerSource.contains("saveDebounceTask?.cancel()"),
            "Immediate flush should cancel the pending debounced write before saving."
        )
        XCTAssertTrue(
            contentSource.contains("@Environment(\\.scenePhase) private var scenePhase"),
            "ContentView should observe scene phase changes so pending drafts are saved when the app backgrounds."
        )
        XCTAssertTrue(
            contentSource.contains("NSApplication.willTerminateNotification"),
            "ContentView should flush conversations on app termination."
        )
        XCTAssertTrue(
            contentSource.contains("conversationManager.flushPendingSave()"),
            "Lifecycle flush should force the latest conversation state to disk instead of waiting for debounce."
        )
    }

    func testAcceptedSubmissionsClearDraftInBothComposerSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        let acceptedOccurrences = source.components(separatedBy: "if accepted {\n                        conversationManager.updateDraftInput(\"\")").count - 1

        XCTAssertEqual(
            acceptedOccurrences,
            2,
            "Both the main composer and the new-chat composer should clear draftInput after accepted submissions."
        )
        XCTAssertTrue(
            source.contains("let accepted = agentEngine.submitUserInput(text)"),
            "New-chat submissions should keep the accepted flag so rejected submissions preserve the user's draft."
        )
    }
}
