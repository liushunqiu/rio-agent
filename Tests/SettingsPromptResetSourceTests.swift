import XCTest

final class SettingsPromptResetSourceTests: XCTestCase {
    func testSingleAgentPromptResetRequiresConfirmation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("@State private var showingPromptResetConfirmation = false"),
            "Settings should stage prompt reset confirmation instead of overwriting custom prompt text immediately."
        )
        XCTAssertTrue(
            source.contains(".alert(\"恢复默认提示词？\", isPresented: $showingPromptResetConfirmation)"),
            "Resetting the single-agent prompt should require an explicit confirmation."
        )
        XCTAssertTrue(
            source.contains("Button(\"恢复默认\") {\n                            showingPromptResetConfirmation = true\n                        }"),
            "The visible reset button should open the confirmation dialog rather than directly replacing the prompt."
        )
        XCTAssertTrue(
            source.contains("Button(\"恢复默认\", role: .destructive) {\n                singleAgentSystemPrompt = AIConfiguration.defaultSingleAgentSystemPrompt\n            }"),
            "The prompt should only be replaced after the user confirms the destructive reset action."
        )
        XCTAssertTrue(
            source.contains("这会用内置单 Agent 提示词覆盖当前编辑内容。设置会自动应用。"),
            "The confirmation copy should explain that custom prompt edits will be overwritten and auto-applied."
        )
        XCTAssertFalse(
            source.contains("Button(\"恢复默认\") {\n                            singleAgentSystemPrompt = AIConfiguration.defaultSingleAgentSystemPrompt\n                        }"),
            "The visible reset button should not directly overwrite the user's custom prompt."
        )
    }
}
