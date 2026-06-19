import XCTest

final class SidebarDeleteConfirmationSourceTests: XCTestCase {
    func testConversationDeletionRequiresExplicitConfirmation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("@State private var pendingDeleteConversation: Conversation?"),
            "Sidebar should stage a conversation for deletion instead of deleting immediately from the context menu."
        )
        XCTAssertTrue(
            source.contains(".alert(\"删除对话？\""),
            "Deleting a conversation should show a confirmation alert."
        )
        XCTAssertTrue(
            source.contains("deleteConfirmationMessage"),
            "The delete confirmation should explain what will be deleted."
        )
        XCTAssertTrue(
            source.contains("conversation.visibleMessageCount"),
            "The confirmation should include the visible message count so users understand the impact."
        )
        XCTAssertTrue(
            source.contains("这个操作无法撤销"),
            "The confirmation should explicitly warn that deletion is irreversible."
        )
    }

    func testConversationRowsExposeTruncatedContextOnHover() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains(".help(conversation.title)"),
            "Long conversation titles should expose the full title on hover."
        )
        XCTAssertTrue(
            source.contains(".help(previewText)"),
            "Truncated conversation previews should expose the full preview text."
        )
        XCTAssertTrue(
            source.contains("helpText: conversation.workingDirectory"),
            "Folder pills should expose the full workspace path, not only the last folder name."
        )
        XCTAssertTrue(
            source.contains("var helpText: String?"),
            "MetaPill should support contextual help text for compact labels."
        )
        XCTAssertTrue(
            source.contains(".help(helpText ?? text)"),
            "MetaPill should always provide a hover fallback for compact content."
        )
        XCTAssertTrue(
            source.contains("if let pendingDecisionLabel {\n                    MetaPill("),
            "Conversation rows should surface pending confirmation state directly instead of making paused sessions look like normal chats."
        )
        XCTAssertTrue(
            source.contains("private var previewText: String? {\n        conversation.latestPreviewContent\n    }"),
            "Conversation row previews should reuse the centralized preview model so pills can own state labels while preview text carries the concrete task context."
        )
        XCTAssertTrue(
            source.contains("return \"等待覆盖确认\""),
            "Sidebar should give overwrite confirmations a concrete, scan-friendly label."
        )
        XCTAssertTrue(
            source.contains("return \"等待模式确认\""),
            "Sidebar should give execution-mode confirmations a concrete, scan-friendly label."
        )
        XCTAssertTrue(
            source.contains("if let messageMetaLabel {\n                    MetaPill("),
            "Conversation rows should only render the generic message-count pill when it adds new information."
        )
        XCTAssertTrue(
            source.contains("private var messageMetaLabel: String? {\n        if visibleMessageCount > 0 {\n            return \"\\(visibleMessageCount) 条消息\"\n        }\n        if pendingDecisionLabel != nil || hasDraft {\n            return nil\n        }\n        return \"未开始\"\n    }"),
            "Draft-only or pending-confirmation sessions should not repeat a generic 'not started' pill once a more specific state is already visible."
        )
    }
}
