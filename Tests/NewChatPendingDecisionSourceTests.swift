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
            newChatSource.contains("return \"等待你的确认\""),
            "NewChatPage should switch its hero title to a waiting-for-confirmation state."
        )
        XCTAssertTrue(
            newChatSource.contains("private var sendButtonTitle: String {\n        pendingUserDecision != nil ? \"提交回复\" : \"开始\"\n    }"),
            "NewChatPage should relabel the primary action while waiting for confirmation."
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
            newChatSource.contains("return \"可以先直接描述任务；需要引用文件或扫描仓库时，再选择工作目录。\""),
            "The landing page should explain that choosing a workspace is optional until the user needs file-aware context."
        )
        XCTAssertTrue(
            newChatSource.contains("return \"直接写下要做的事\""),
            "The landing-page empty-state subtitle should stay short and action-oriented once the detailed workspace guidance already lives in the helper row below."
        )
        XCTAssertTrue(
            newChatSource.contains("return \"开始任务\""),
            "The landing-page hero title should stay concise so the start state reads like a workbench instead of a marketing-style launch screen."
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
            newChatSource.contains("输入是继续多 Agent，输入否改单 Agent，或直接写新任务"),
            "NewChatPage pending hints should keep the new-task escape hatch visible during execution-mode confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains("ModelBadge(modelName: modelName, providerName: providerName)\n                    .frame(maxWidth: 180, alignment: .trailing)"),
            "NewChatPage should constrain long model badges so pending confirmation hints remain visible."
        )
        XCTAssertTrue(
            newChatSource.contains("Text(\"\\(composer.selectedFiles.count) 个文件\")"),
            "The landing-page file context counter should read as compact file context, not as a second verbose metadata badge."
        )
        XCTAssertTrue(
            newChatSource.contains(".background(Theme.bgGlass.opacity(0.58))"),
            "The landing-page file count badge should sit back visually once files are attached."
        )
        XCTAssertTrue(
            newChatSource.contains(".lineLimit(2)"),
            "NewChatPage pending confirmation hints should allow wrapping instead of collapsing into an unreadable single line."
        )
        XCTAssertTrue(
            newChatSource.contains(".layoutPriority(2)"),
            "NewChatPage pending confirmation hints should outrank secondary metadata in the toolbar layout."
        )
        XCTAssertTrue(
            newChatSource.contains(".help(pendingDecisionHint)"),
            "NewChatPage pending confirmation hints should expose the full text on hover when space is tight."
        )
        XCTAssertTrue(
            newChatSource.contains("if let pendingDecisionHint, pendingUserDecision == nil"),
            "Pending confirmation mode should not repeat the same long-form guidance in the toolbar once the dedicated instruction block is visible."
        )
        XCTAssertTrue(
            newChatSource.contains("if pendingUserDecision != nil {\n                HStack(alignment: .top, spacing: 8)"),
            "Quick prompts should be replaced by a dedicated confirmation instruction block."
        )
        XCTAssertTrue(
            newChatSource.contains("} else if shouldShowQuickPromptGrid {"),
            "Quick prompts should only stay visible while the landing-page composer is still empty."
        )
        XCTAssertTrue(
            newChatSource.contains("已开始编辑。发送后会直接执行；清空输入可重新选择模板。"),
            "Once the user has started writing, the landing page should step back from long onboarding copy and switch to a calmer helper state."
        )
        XCTAssertTrue(
            newChatSource.contains("private var shouldShowQuickPromptGrid: Bool {\n        pendingUserDecision == nil && trimmedComposerText.isEmpty\n    }"),
            "Quick-prompt visibility should follow the actual composer state instead of staying visually dominant after editing begins."
        )
        XCTAssertTrue(
            newChatSource.contains("可以先写任务；需要添加文件上下文时，再选择工作目录"),
            "The landing-page file-picker help should avoid implying that workspace selection is a mandatory first step."
        )
        XCTAssertTrue(
            newChatSource.contains("提交回复或新任务 (Cmd+Return)"),
            "The send button help should clarify pending-confirmation submissions."
        )
        XCTAssertTrue(
            newChatSource.contains("if let sendHint {\n                    Text(sendHint)"),
            "The landing-page footer hint should render conditionally so pending confirmation mode can avoid repeating guidance that is already handled by the dedicated confirmation copy."
        )
        XCTAssertTrue(
            newChatSource.contains("pendingUserDecision != nil ? \"当前说明\" : \"任务模板\""),
            "NewChatPage should use a work-oriented templates label instead of marketing-style quick-start framing."
        )
        XCTAssertTrue(
            newChatSource.contains(".background(Theme.bgGlass.opacity(0.36))"),
            "Quick prompts should read as light suggestion rows instead of visually heavy empty-state cards."
        )
        XCTAssertTrue(
            newChatSource.contains(".shadow(color: Theme.shadowStrong.opacity(0.52), radius: 20, x: 0, y: 12)"),
            "The landing-page composer should keep a calmer shadow profile so the start state matches the main work surface."
        )
        XCTAssertTrue(
            newChatSource.contains(".frame(width: 42, height: 42)"),
            "The landing-page header mark should step back visually once the main composer becomes the primary focal point."
        )
        XCTAssertTrue(
            newChatSource.contains(".font(.system(size: 20, weight: .bold, design: .rounded))"),
            "The landing-page title should scale down from hero sizing to a denser workspace heading."
        )
        XCTAssertTrue(
            newChatSource.contains(".cornerRadius(Theme.radiusSM)"),
            "Quick prompts should use the tighter utility radius shared by other compact workbench controls."
        )
        XCTAssertTrue(
            newChatSource.contains(".stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)"),
            "Quick prompts should keep only a faint boundary so the main task composer remains the visual anchor."
        )
        XCTAssertTrue(
            newChatSource.contains(".foregroundColor(Theme.textSecondary)"),
            "Quick prompt icons should sit back visually once the section is framed as secondary suggestions."
        )
        XCTAssertTrue(
            newChatSource.contains("输入“是”或“否”继续，也可以直接写新任务，系统会自动切换。"),
            "NewChatPage confirmation mode should keep the replacement instruction copy visible."
        )
        XCTAssertTrue(
            newChatSource.contains("也可以直接写新任务，系统会自动切换"),
            "NewChatPage confirmation mode should explicitly preserve the new-task escape hatch."
        )
        XCTAssertTrue(
            newChatSource.contains("return hasInput ? \"已填写回复\" : \"等待确认回复\""),
            "NewChatPage summary pills should describe confirmation replies instead of pretending the page is still waiting for a new task."
        )
        XCTAssertTrue(
            newChatSource.contains("if pendingUserDecision != nil {\n            return Theme.statusWarning\n        }"),
            "NewChatPage input summary tone should stay in warning semantics while waiting for confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains("private var canSend: Bool {\n        composer.canSend && canAcceptInput\n    }"),
            "NewChatPage should not present an active send button when the engine cannot accept input."
        )
        XCTAssertTrue(
            newChatSource.contains("private var trimmedComposerText: String"),
            "The landing page should normalize the composer text once and reuse that truth for start-state decisions."
        )
        XCTAssertTrue(
            newChatSource.contains("if shouldShowCompactStartSummary {"),
            "The landing page should collapse its default summary area into a lighter helper row when the session is still completely empty."
        )
        XCTAssertTrue(
            newChatSource.contains("private var shouldShowCompactStartSummary: Bool {\n        pendingUserDecision == nil"),
            "The compact start summary should follow the real empty-state truth rather than always rendering three status pills."
        )
        XCTAssertTrue(
            newChatSource.contains("if shouldShowWorkspaceSummary {"),
            "The landing page should hide its secondary summary band when a pending confirmation already owns the page and there is no real workspace or draft context to summarize."
        )
        XCTAssertTrue(
            newChatSource.contains("private var shouldShowWorkspaceSummary: Bool {\n        if pendingUserDecision != nil\n            && workingDirectory.wrappedValue == nil\n            && composer.selectedFiles.isEmpty\n            && trimmedComposerText.isEmpty {\n            return false\n        }\n        return true\n    }"),
            "Pending confirmation should only keep the workspace summary visible when it carries real context instead of repeating an empty waiting state."
        )
        XCTAssertTrue(
            newChatSource.contains("private var sendHint: String? {\n        guard pendingUserDecision == nil else { return nil }\n        return canSend ? \"Cmd+Return 发送\" : \"先写清楚任务\"\n    }"),
            "Pending confirmation should drop the footer send hint once the page already has a dedicated confirmation title, explanation and primary action."
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
