import XCTest

final class ContentViewSourceTests: XCTestCase {
    func testMainChatReceivesCurrentTaskPlanForMultiAgentVisibility() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("currentTaskPlan: agentEngine.currentTaskPlan"),
            "EnhancedChatView must receive the active task plan so Multi-Agent progress is visible in the main transcript."
        )
        XCTAssertTrue(
            source.contains("currentPipeline: agentEngine.currentPipeline"),
            "EnhancedChatView should receive the active pipeline so the main transcript can render runtime guidance."
        )
        XCTAssertTrue(
            source.contains("pendingUserDecision: agentEngine.pendingUserDecision"),
            "EnhancedChatView should receive pending confirmation state so transcript runtime guidance does not keep advertising an in-flight pipeline after execution pauses for user input."
        )
        XCTAssertFalse(
            source.contains("currentTaskPlan: nil"),
            "Passing nil hides TaskPlanView even while a Multi-Agent task is running."
        )
    }

    func testWorkingDirectoryBadgesExposeFullPath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains(".help(currentWorkingDirectory)"),
            "Top-bar workspace badges should expose the full path when the visible folder name is compact."
        )
        XCTAssertTrue(
            source.contains("if messageCount > 0 {\n                HStack(spacing: 5)"),
            "The top bar should hide zero-value message counts so empty sessions do not carry decorative but uninformative chrome."
        )
        XCTAssertTrue(
            source.contains(".help(workingDirectory)"),
            "Empty-state workspace badges should expose the full path."
        )
        XCTAssertTrue(
            source.contains("private var folderHelpText: String"),
            "The input folder selector should have provider-specific help text for selected and unselected states."
        )
        XCTAssertTrue(
            source.contains("return \"当前工作目录：\\(dir)\""),
            "The folder selector should show the full selected path in its tooltip."
        )
        XCTAssertTrue(
            source.contains(".truncationMode(.middle)"),
            "Long workspace folder names should truncate safely instead of pushing nearby controls."
        )
        XCTAssertTrue(
            source.contains("if shouldShowSecondaryRuntimeSummaries, let focusSummary"),
            "The top bar should surface a separate focus summary when detailed runtime state is not already owned by the main transcript."
        )
        XCTAssertTrue(
            source.contains("Text(topBarModelLabel)"),
            "The top bar should collapse provider and model into one compact primary badge instead of splitting them into parallel chips."
        )
        XCTAssertFalse(
            source.contains("Image(systemName: \"cpu\")"),
            "The top bar should avoid a second model chip once the provider badge already carries the active model label."
        )
        XCTAssertTrue(
            source.contains("singleAgentVerification: agentEngine.singleAgentVerificationSummary"),
            "The top bar should receive the single-agent verification state so finalized answers can still surface missing evidence."
        )
        XCTAssertTrue(
            source.contains("if pipeline != nil || pendingUserDecision != nil || singleAgentVerification != nil"),
            "The top bar should keep its primary status badge visible when only single-agent verification state remains."
        )
        XCTAssertTrue(
            source.contains("var singleAgentVerification: VerifierService.VerificationOutcome?"),
            "TopBar should explicitly model single-agent verification as first-class runtime state."
        )
        XCTAssertTrue(
            source.contains("prefersCompactRuntimeChrome: hasVisibleTranscript && (\n                    agentEngine.currentPipeline != nil ||\n                    agentEngine.pendingUserDecision != nil ||\n                    agentEngine.singleAgentVerificationSummary != nil\n                )"),
            "Once the transcript already carries the runtime card, the top bar should retreat to compact ambient status instead of repeating the same execution and focus details."
        )
        XCTAssertTrue(
            source.contains("var prefersCompactRuntimeChrome = false"),
            "TopBar should accept an explicit compact-runtime mode rather than inferring it indirectly from unrelated state."
        )
        XCTAssertTrue(
            source.contains("private var shouldShowSecondaryRuntimeSummaries: Bool {\n        !prefersCompactRuntimeChrome\n    }"),
            "TopBar should suppress secondary runtime badges when the transcript already owns the detailed runtime narrative."
        )
        XCTAssertTrue(
            source.contains("if shouldShowSecondaryRuntimeSummaries, let executionSummary"),
            "Execution summary badges should disappear once the transcript runtime card is visible."
        )
        XCTAssertTrue(
            source.contains("if shouldShowSecondaryRuntimeSummaries, let focusSummary"),
            "Focus summary badges should disappear once the transcript runtime card is visible."
        )
        XCTAssertTrue(
            source.contains("return \"未验证\""),
            "Top-bar pipeline status should call out unverified single-agent results instead of silently looking completed."
        )
        XCTAssertTrue(
            source.contains("case .verified:\n                return \"已验证\""),
            "Top-bar pipeline status should read as verified once single-agent validation has passed."
        )
        XCTAssertTrue(
            source.contains("return \"答案需要修订\""),
            "Top-bar focus summary should surface revision-required verification outcomes."
        )
        XCTAssertTrue(
            source.contains("case .verified:\n                return nil"),
            "Top-bar focus summary should drop away once verification is healthy instead of duplicating the primary verified state."
        )
        XCTAssertTrue(
            source.contains("if singleAgentVerification != nil {\n            return nil\n        }"),
            "Top-bar execution summaries should disappear entirely once verification state is already represented by the primary status and focus chrome."
        )
        XCTAssertTrue(
            source.contains("case .overwriteAgentFile:\n                return nil"),
            "Pending confirmation should not render a second summary badge that repeats the primary waiting state."
        )
        XCTAssertTrue(
            source.contains("case .chooseExecutionModeForTask:\n                return nil"),
            "Execution-mode confirmation should keep the top bar compact by dropping redundant summary copy."
        )
        XCTAssertTrue(
            source.contains("return \"继续多 Agent 或改单 Agent\""),
            "Pending execution-mode confirmations should use the focus badge for the actual decision the user needs to make."
        )
        XCTAssertTrue(
            source.contains("currentTaskPlan.subTasks.filter(\\.needsAttention).count"),
            "Top-bar focus summary should use the shared SubTask attention state so blocked and cancelled subtasks are counted consistently."
        )
        XCTAssertTrue(
            source.contains("if currentTaskPlan.status == .completed {\n                return nil\n            }"),
            "Completed healthy Multi-Agent runs should drop the extra top-bar summary instead of continuing to look busy after delivery."
        )
        XCTAssertTrue(
            source.contains("if focusSummary == currentStage.type.title {\n                return nil\n            }"),
            "Top-bar execution summaries should not repeat the same current-stage label that already appears in the focus badge."
        )
        XCTAssertTrue(
            source.contains("if pipeline?.overallStatus == .running {\n                return nil\n            }"),
            "While a pipeline is actively running, the focus badge should disappear if it would only repeat the current stage."
        )
        XCTAssertTrue(
            source.contains("if pendingUserDecision != nil {\n            return Theme.statusWarning\n        }\n        if let singleAgentVerification"),
            "Top-bar execution summary should switch to warning tone when the system is paused for user confirmation."
        )
        XCTAssertTrue(
            source.contains("Text(\"最近会话\")"),
            "Sidebar header should frame the left rail as a conversation list instead of a dashboard hero."
        )
        XCTAssertTrue(
            source.contains("Text(\"新建\")"),
            "Sidebar should reduce the new-conversation control to a compact utility action."
        )
    }

    func testInternalActivityStopsAnimatingWhenWaitingForConfirmation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains(".symbolEffect(.pulse, options: .repeating, value: shouldAnimateActivity)"),
            "Internal activity should not keep pulsing once execution has paused for a user confirmation."
        )
        XCTAssertTrue(
            source.contains("private var shouldAnimateActivity: Bool {\n        isProcessing && pendingUserDecision == nil\n    }"),
            "Internal activity animation should reflect active processing only, not paused confirmation state."
        )
        XCTAssertTrue(
            source.contains("系统已完成执行模式判断，正在等待你选择继续多 Agent 或改用单 Agent。你也可以直接输入新的任务，系统会自动切换。"),
            "Internal activity confirmation guidance should preserve the same new-task escape hatch as the other pending-decision surfaces."
        )
        XCTAssertTrue(
            source.contains("hasVisibleTranscript || agentEngine.pendingUserDecision != nil"),
            "The bottom input area should stay hidden during pure internal startup activity so the app does not advertise a second parallel action surface before the first visible result appears."
        )
        XCTAssertTrue(
            source.contains("private var hasInternalActivity: Bool {\n        !hasVisibleTranscript && (\n            agentEngine.isProcessing ||\n            agentEngine.pendingUserDecision != nil\n        )\n    }"),
            "Internal activity should only own the main surface while work is truly running or explicitly waiting for confirmation; hidden internal messages alone should not trap the session in a non-interactive state."
        )
        XCTAssertTrue(
            source.contains("Text(\"停止当前任务\")"),
            "Internal startup activity should expose a direct stop action when execution is already running but no transcript content is visible yet."
        )
        XCTAssertTrue(
            source.contains("完成第一步后会自动切换到主阅读流"),
            "Internal startup activity should explain that the current view is a temporary preparation state rather than a stalled empty chat."
        )
    }

    func testResumeEditingPrefersCurrentDraftBeforeOlderTaskText() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("private var resumableTaskInput: String? {\n        let draft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)\n        if !draft.isEmpty {\n            return draft\n        }"),
            "Error recovery should prefer the current unsent draft before falling back to an older task from transcript history."
        )
        XCTAssertTrue(
            source.contains("private func restoreResumableTaskInput() {\n        guard let resumableTaskInput, !resumableTaskInput.isEmpty else { return }\n        inputText = resumableTaskInput"),
            "The resume action should restore the shared resumable input source instead of assuming only transcript-backed tasks exist."
        )
        XCTAssertTrue(
            source.contains("help(\"优先恢复当前草稿；如果没有草稿，则恢复最近一条真实任务\")"),
            "The error banner should explain that resume will preserve in-progress edits when they exist."
        )
        XCTAssertTrue(
            source.contains("Text(\"恢复任务\")"),
            "Blocking errors should present task recovery as the primary action instead of generic editing."
        )
    }
}
