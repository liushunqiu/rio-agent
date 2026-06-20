import XCTest

final class SidebarNavigationLockSourceTests: XCTestCase {
    func testSidebarNavigationIsLockedDuringActiveProcessing() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let sidebarListSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/SidebarConversationListView.swift"))
        let source = contentSource + "\n" + sidebarListSource

        XCTAssertTrue(
            source.contains("runtimeState: sidebarRuntimeState"),
            "The sidebar should receive isolated runtime lock state instead of observing every AgentEngine update."
        )
        XCTAssertTrue(
            source.contains("private var isConversationNavigationLocked: Bool {\n        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil\n    }"),
            "ContentView should centralize the active-processing navigation lock so sidebar and menu entry points share the same condition."
        )
        XCTAssertTrue(
            source.contains("@ObservedObject var runtimeState: SidebarRuntimeState")
                && source.contains("private var isNavigationLocked: Bool {\n        runtimeState.isNavigationLocked\n    }"),
            "SidebarView should derive navigation lock state from the lightweight sidebar runtime state."
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
            sidebarListSource.contains("guard !isNavigationLocked,")
                && sidebarListSource.contains("parent.onSelect(items[row])"),
            "Conversation row selection should no-op while active execution is running."
        )
        XCTAssertTrue(
            sidebarListSource.contains("deleteItem.isEnabled = !isNavigationLocked")
                && sidebarListSource.contains("@objc private func deleteConversation")
                && sidebarListSource.contains("guard !isNavigationLocked,"),
            "Conversation deletion should not be staged while active execution is running."
        )
        XCTAssertTrue(
            source.contains("Button(\"删除\", role: .destructive) {\n                guard !isNavigationLocked else {\n                    pendingDeleteItem = nil\n                    return\n                }"),
            "The deletion confirmation should re-check the navigation lock in case active execution starts while the alert is already open."
        )
        XCTAssertTrue(
            source.contains("当前任务运行中，完成或停止后再切换会话。"),
            "The sidebar should make the temporary navigation lock visible instead of silently ignoring clicks."
        )
        XCTAssertTrue(
            contentSource.contains("isNavigationLocked: isNavigationLocked")
                && sidebarListSource.contains("alphaValue = isDisabled && !isSelected ? 0.58 : 1")
                && sidebarListSource.contains("isDisabled && !isSelected ? 0.58 : 1"),
            "Conversation rows should look and read as disabled while navigation is locked."
        )
    }
}
