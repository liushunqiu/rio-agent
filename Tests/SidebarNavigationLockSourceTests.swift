import XCTest

final class SidebarNavigationLockSourceTests: XCTestCase {
    func testSidebarNavigationIsLockedDuringActiveProcessing() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("isNavigationLocked: isConversationNavigationLocked"),
            "The sidebar should only lock navigation while execution is actively running, not while paused for a user confirmation."
        )
        XCTAssertTrue(
            source.contains("private var isConversationNavigationLocked: Bool {\n        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil\n    }"),
            "ContentView should centralize the active-processing navigation lock so sidebar and menu entry points share the same condition."
        )
        XCTAssertTrue(
            source.contains("let isNavigationLocked: Bool"),
            "SidebarView should receive the runtime navigation lock explicitly."
        )
        XCTAssertTrue(
            source.contains("private func requestNewConversation()")
                && source.contains("guard !isConversationNavigationLocked else {\n            agentEngine.error = \"当前任务运行中，完成或停止后再新建会话。\"\n            return\n        }"),
            "New-conversation requests should be centrally guarded so menu shortcuts cannot bypass the sidebar lock."
        )
        XCTAssertTrue(
            source.contains(".onReceive(NotificationCenter.default.publisher(for: .createNewConversation)) { _ in\n            requestNewConversation()\n        }"),
            "The app-menu new-conversation notification should reuse the guarded request path."
        )
        XCTAssertTrue(
            source.contains("guard !isNavigationLocked else { return }\n                        onNewConversation()"),
            "The new-conversation action should no-op while active execution would otherwise be cancelled by a context reset."
        )
        XCTAssertTrue(
            source.contains(".disabled(isNavigationLocked)")
                && source.contains(".help(newConversationHelpText)"),
            "Locked sidebar actions should expose both disabled state and hover explanation."
        )
        XCTAssertTrue(
            source.contains("guard !isNavigationLocked else { return }\n                                onSelect(conversation)"),
            "Conversation row selection should no-op while active execution is running."
        )
        XCTAssertTrue(
            source.contains("guard !isNavigationLocked else { return }\n                                    pendingDeleteConversation = conversation"),
            "Conversation deletion should not be staged while active execution is running."
        )
        XCTAssertTrue(
            source.contains("Button(\"删除\", role: .destructive) {\n                guard !isNavigationLocked else {\n                    pendingDeleteConversation = nil\n                    return\n                }"),
            "The deletion confirmation should re-check the navigation lock in case active execution starts while the alert is already open."
        )
        XCTAssertTrue(
            source.contains("当前任务运行中，完成或停止后再切换会话。"),
            "The sidebar should make the temporary navigation lock visible instead of silently ignoring clicks."
        )
        XCTAssertTrue(
            source.contains("isDisabled: isNavigationLocked")
                && source.contains(".opacity(isDisabled && !isSelected ? 0.58 : 1)")
                && source.contains("private var rowHelpText: String"),
            "Conversation rows should look and read as disabled while navigation is locked."
        )
    }
}
