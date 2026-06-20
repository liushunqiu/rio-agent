import XCTest

final class SidebarDeleteConfirmationSourceTests: XCTestCase {
    func testConversationDeletionRequiresExplicitConfirmation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let sidebarItemSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/ConversationSidebarItem.swift"))
        let source = contentSource + "\n" + sidebarItemSource

        XCTAssertTrue(
            source.contains("@State private var pendingDeleteItem: ConversationSidebarItem?"),
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
        XCTAssertFalse(
            source.contains("let messageCount = item.visibleMessageCount")
                || source.contains("条可见消息"),
            "The delete confirmation should not read per-conversation message counts from the sidebar hot path."
        )
        XCTAssertTrue(
            source.contains("这个操作无法撤销"),
            "The confirmation should explicitly warn that deletion is irreversible."
        )
    }

    func testConversationRowsStayMinimalAndFast() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let sidebarItemSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/ConversationSidebarItem.swift"))
        let sidebarListSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/SidebarConversationListView.swift"))
        let source = contentSource + "\n" + sidebarItemSource + "\n" + sidebarListSource

        XCTAssertTrue(
            sidebarListSource.contains("toolTip = [item.title, item.workingDirectoryLabel].joined(separator: \"\\n\")"),
            "Minimal rows should expose the full title and workspace path on hover."
        )
        XCTAssertTrue(
            sidebarListSource.contains("titleField.stringValue = item.title")
                && sidebarListSource.contains("directoryField.stringValue = item.workingDirectoryLabel"),
            "Rows should render only title and concrete working directory."
        )
        XCTAssertFalse(
            sidebarListSource.contains("countField")
                || sidebarListSource.contains("messageMetaLabel"),
            "Rows should not keep a per-conversation message count field in the scrolling path."
        )
        XCTAssertTrue(
            sidebarItemSource.contains("let workingDirectoryLabel: String")
                && sidebarItemSource.contains("\"未设置工作目录\""),
            "Sidebar snapshots should carry a concrete workspace label without deriving folder pills during rendering."
        )
        XCTAssertTrue(
            contentSource.contains("SidebarConversationListView("),
            "Sidebar should render conversations through the AppKit-backed list instead of SwiftUI row views."
        )
        XCTAssertTrue(
            source.contains("struct ConversationSidebarItem: Identifiable, Equatable")
                && source.contains("let workingDirectoryLabel: String"),
            "Conversation rows should come from a lightweight sidebar snapshot so scrolling does not repeatedly scan full conversation history."
        )
        XCTAssertFalse(
            sidebarItemSource.contains("visibleMessageCount")
                || sidebarItemSource.contains("messageMetaLabel")
                || sidebarItemSource.contains("conversation.messages")
                || sidebarItemSource.contains("incrementalVisibleMessageCount"),
            "Sidebar snapshots should not compute per-chat message counts."
        )
        XCTAssertTrue(
            contentSource.contains("@ObservedObject var sidebarState: SidebarState")
                && contentSource.contains("let sidebarItems = sidebarState.items")
                && contentSource.contains("let selectedConversationID = sidebarState.selectedConversationID"),
            "SidebarView should observe only the isolated sidebar state instead of the full conversation manager."
        )
        XCTAssertFalse(
            contentSource.contains("@ObservedObject var conversationManager: ConversationManager"),
            "SidebarView should not observe ConversationManager because streaming conversation mutations would invalidate the whole sidebar."
        )
        XCTAssertFalse(
            contentSource.contains("conversationManager.conversations.map(ConversationSidebarItem.init)"),
            "SidebarView body should not map conversations into snapshots while the user scrolls."
        )
        XCTAssertFalse(
            contentSource.contains("List(sidebarItems)"),
            "Sidebar should not use SwiftUI List for the hot scrolling path."
        )
        XCTAssertTrue(
            sidebarListSource.contains("struct SidebarConversationListView: NSViewRepresentable")
                && sidebarListSource.contains("SidebarConversationCellView")
                && sidebarListSource.contains("NSTableViewDataSource")
                && sidebarListSource.contains("NSScrollView"),
            "The hot scrolling path should use AppKit table cells instead of SwiftUI row views."
        )
        XCTAssertTrue(
            sidebarListSource.contains("static let rowHeight: CGFloat = 66")
                && sidebarListSource.contains("reloadData(\n                forRowIndexes: rowsToReload")
                && sidebarListSource.contains("visibleRowIndexes(in: tableView)"),
            "Conversation rows should use fixed-height AppKit cells and refresh only visible rows for non-structural updates."
        )
        XCTAssertTrue(
            sidebarListSource.contains("if isLiveScrolling")
                && sidebarListSource.contains("deferredParent = parent")
                && sidebarListSource.contains("NSScrollView.willStartLiveScrollNotification"),
            "Streaming/sidebar content changes should be deferred while the user is actively scrolling, including structural list changes."
        )
        XCTAssertTrue(
            sidebarListSource.contains("SidebarConversationScrollView")
                && sidebarListSource.contains("window.makeFirstResponder(sidebarTableView)")
                && sidebarListSource.contains("override func scrollWheel(with event: NSEvent)"),
            "Sidebar scrolling should claim first responder on wheel input so an already-focused composer does not keep the list on the slower unfocused scroll path."
        )
        XCTAssertTrue(
            sidebarListSource.contains("override func layout()")
                && sidebarListSource.contains("cardView.frame = bounds.insetBy")
                && sidebarListSource.contains("titleField.frame = NSRect")
                && sidebarListSource.contains("directoryField.frame = NSRect"),
            "Fixed-height sidebar cells should use manual frames instead of Auto Layout in the scrolling path."
        )
        XCTAssertFalse(
            sidebarListSource.contains("NSLayoutConstraint.activate"),
            "Sidebar row cells should avoid constraint solving while scrolling."
        )
        XCTAssertFalse(
            sidebarListSource.contains("previewField")
                || sidebarListSource.contains("timeField")
                || sidebarListSource.contains("SidebarPillView")
                || sidebarListSource.contains("NSImageView"),
            "Rows should not keep preview, time, pill, or icon controls in the hot scrolling path."
        )
        XCTAssertFalse(
            sidebarItemSource.contains("previewText")
                || sidebarItemSource.contains("RelativeDateTimeFormatter")
                || sidebarItemSource.contains("pendingDecisionLabel")
                || sidebarItemSource.contains("folderName"),
            "Sidebar snapshots should not compute preview text, relative dates, pending labels, or folder pills."
        )
        XCTAssertFalse(
            source.contains("@State private var hoveredConversation"),
            "Hover state should stay inside each row so scrolling across rows does not invalidate the whole sidebar."
        )
        XCTAssertFalse(
            source.contains("struct ConversationRow: View"),
            "The sidebar should not keep the old SwiftUI row view in the hot scrolling implementation."
        )
    }

    func testSidebarIsIsolatedFromStreamingRuntimeInvalidations() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let managerSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/ConversationManager.swift"))

        XCTAssertTrue(
            source.contains("@StateObject private var dependencies = ContentViewDependencies()"),
            "ContentView should own a stable dependency container instead of directly observing high-frequency runtime objects."
        )
        XCTAssertFalse(
            source.contains("@StateObject private var agentEngine = AgentEngine()"),
            "Root ContentView should not observe AgentEngine directly because streaming updates would invalidate the sidebar."
        )
        XCTAssertTrue(
            source.contains("private struct RuntimeStateBridge: View")
                && source.contains("private struct ContextPanelHost: View"),
            "High-frequency runtime observation should be isolated to tiny bridge/context host views, not the root layout."
        )
        XCTAssertTrue(
            source.contains("final class SidebarRuntimeState: ObservableObject")
                && source.contains("guard isNavigationLocked != isLocked || isSettingsLocked != isLocked else { return }"),
            "Sidebar runtime state should publish only when lock booleans actually change."
        )
        XCTAssertTrue(
            source.contains("sidebarState: conversationManager.sidebarState")
                && source.contains("@ObservedObject var sidebarState: SidebarState")
                && managerSource.contains("final class SidebarState: ObservableObject"),
            "Sidebar conversation data should be bridged through an isolated state object."
        )
        XCTAssertTrue(
            managerSource.contains("if self.items != items {\n            self.items = items\n        }")
                && managerSource.contains("guard self.selectedConversationID != selectedConversationID else { return }"),
            "SidebarState should avoid publishing while streaming updates leave sidebar rows and selection unchanged."
        )
    }
}
