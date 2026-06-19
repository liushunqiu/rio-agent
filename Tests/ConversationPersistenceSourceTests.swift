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
        XCTAssertTrue(
            contentSource.contains("pendingDecision: .set(agentEngine.persistedPendingDecision)"),
            "Conversation persistence should save pending confirmation state so paused decisions survive reloads and conversation switches."
        )
    }

    func testConversationPersistenceCanUseInjectedStorage() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/ConversationManager.swift"))
        let testSource = try String(contentsOf: repoRoot.appendingPathComponent("Tests/ConversationManagerTests.swift"))

        XCTAssertTrue(
            managerSource.contains("private let userDefaults: UserDefaults"),
            "ConversationManager should keep its backing store injectable so tests and development runs do not overwrite real user conversations."
        )
        XCTAssertTrue(
            managerSource.contains("init(\n        userDefaults: UserDefaults = .standard,\n        saveKey: String = \"saved_conversations\"\n    )"),
            "The app should keep the existing default persistence while allowing isolated stores."
        )
        XCTAssertTrue(
            managerSource.contains("userDefaults.set(data, forKey: saveKey)")
                && managerSource.contains("guard let data = userDefaults.data(forKey: saveKey) else { return }"),
            "Conversation persistence should consistently use the injected store for both reads and writes."
        )
        XCTAssertTrue(
            testSource.contains("private func makeIsolatedManager() -> ConversationManager")
                && testSource.contains("ConversationManager(\n            userDefaults: defaults,"),
            "ConversationManager tests should use isolated storage instead of touching the real saved_conversations key."
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

    func testLandingPageDraftCreatesConversationBeforeFirstSubmit() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("if conversationManager.currentConversation == nil {\n                    guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }\n                    _ = conversationManager.createNewConversation("),
            "Typing a first non-empty landing-page draft should create a conversation immediately so the draft can be restored after backgrounding or restart."
        )
        XCTAssertTrue(
            source.contains("workingDirectory: agentEngine.workingDirectory"),
            "The draft-created conversation should keep the current workspace context."
        )
        XCTAssertTrue(
            source.contains("conversationManager.updateDraftInput(newValue)"),
            "After creating the draft conversation, the binding should persist the user's actual draft text."
        )
    }

    func testDeletingFinalConversationClearsEngineWorkspaceState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engineSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            contentSource.contains("agentEngine.clearConversation()"),
            "Deleting the final selected conversation should reset the engine instead of leaving stale workspace context active."
        )
        XCTAssertTrue(
            engineSource.contains("workingDirectory = nil"),
            "Clearing the active conversation should also clear the engine working directory."
        )
    }

    func testSelectingConversationLoadsResolvedCurrentSnapshot() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let managerSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/ConversationManager.swift"))

        XCTAssertTrue(
            managerSource.contains("func selectConversation(_ conversation: Conversation) -> Conversation?"),
            "ConversationManager should return the stored snapshot that was actually selected."
        )
        XCTAssertTrue(
            managerSource.contains("guard let storedConversation = conversations.first(where: { $0.id == conversation.id }) else {\n            return nil\n        }"),
            "Selecting a stale sidebar snapshot should not resurrect a deleted or unmanaged conversation."
        )

        XCTAssertTrue(
            contentSource.contains("guard let selectedConversation = conversationManager.selectConversation(conversation) else {\n                        return\n                    }\n                    agentEngine.loadConversation(selectedConversation)"),
            "Conversation switches should load only the manager-confirmed snapshot so stale sidebar values do not overwrite newer messages, drafts, workspace, or pending decisions."
        )
        XCTAssertFalse(
            contentSource.contains("conversationManager.selectConversation(conversation)\n                    agentEngine.loadConversation(conversation)"),
            "ContentView should not bypass ConversationManager's stored snapshot when selecting a conversation."
        )
        XCTAssertFalse(
            contentSource.contains("conversationManager.currentConversation ?? conversation"),
            "ContentView should not fall back to a stale external conversation snapshot after selection fails."
        )
    }
}
