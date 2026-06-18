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
    }
}
