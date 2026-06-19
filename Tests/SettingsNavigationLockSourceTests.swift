import XCTest

final class SettingsNavigationLockSourceTests: XCTestCase {
    func testSettingsEntryPointsAreLockedDuringActiveProcessing() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "private var isRuntimeConfigurationLocked: Bool {\n        agentEngine.isProcessing && agentEngine.pendingUserDecision == nil\n    }").count - 1,
            2,
            "Both root and main content should use the same active-processing settings lock so settings remain available while paused for user confirmation."
        )
        XCTAssertTrue(
            source.contains("guard !isRuntimeConfigurationLocked else {\n            agentEngine.error = \"当前任务运行中，完成或停止后再修改设置。\"\n            return\n        }"),
            "Root settings requests should be centrally guarded so indirect settings entry points cannot mutate runtime configuration mid-task."
        )
        XCTAssertTrue(
            source.contains("isSettingsLocked: isRuntimeConfigurationLocked"),
            "Settings lock state should be passed into visible settings entry points instead of being inferred by child controls."
        )
        XCTAssertTrue(
            source.contains("let isSettingsLocked: Bool"),
            "SidebarView should receive the settings lock explicitly."
        )
        XCTAssertTrue(
            source.contains("var isSettingsLocked = false"),
            "TopBar should receive the settings lock explicitly while preserving its default initializer ergonomics."
        )
        XCTAssertTrue(
            source.contains("Button(action: {\n                guard !isSettingsLocked else { return }\n                settingsInitialTab = .ai"),
            "Top-bar settings should no-op while active execution is running."
        )
        XCTAssertTrue(
            source.contains(".disabled(isSettingsLocked)\n            .opacity(isSettingsLocked ? 0.52 : 1)\n            .hoverHighlight()\n            .help(settingsHelpText)"),
            "Top-bar settings should expose disabled state and a hover reason while locked."
        )
        XCTAssertTrue(
            source.contains("guard !isRuntimeConfigurationLocked else {\n                agentEngine.error = \"当前任务运行中，完成或停止后再修改设置。\"\n                return\n            }\n\n            settingsInitialTab = launchContext.tab"),
            "Error-banner settings recovery should not bypass the runtime configuration lock."
        )
        XCTAssertTrue(
            source.contains("isSettingsLocked ? \"当前任务运行中，完成或停止后再修改设置\" : \"设置\""),
            "Locked settings controls should explain why settings are temporarily unavailable."
        )
    }
}
