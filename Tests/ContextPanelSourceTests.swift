import XCTest

final class ContextPanelSourceTests: XCTestCase {
    func testNarrowContextPanelRowsExposeFullTruncatedValues() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContextPanel.swift"))

        XCTAssertTrue(
            source.contains(".help(plan.originalTask)"),
            "The single-agent task summary is line-limited and should expose the full task on hover."
        )
        XCTAssertTrue(
            source.contains(".help(step)"),
            "Plan steps can contain long paths or commands and should expose their full text."
        )
        XCTAssertTrue(
            source.contains(".help(workingDirectory)"),
            "Working directory rows should expose the full path instead of only the visible tail."
        )
        XCTAssertTrue(
            source.contains(".help(file)"),
            "Recent file rows should expose the absolute file path when their labels are truncated."
        )
        XCTAssertTrue(
            source.contains(".help(role.modelName)"),
            "Long model identifiers in the context panel should expose their full value."
        )
        XCTAssertTrue(
            source.contains(".help(role.providerName)"),
            "Provider names should be discoverable after truncation."
        )
        XCTAssertTrue(
            source.contains("ContextSection(title: \"运行态\")"),
            "The context panel should expose a dedicated runtime section instead of burying execution state inside other cards."
        )
        XCTAssertTrue(
            source.contains("RuntimeFocusCard("),
            "The runtime section should render a focused summary card for the current pipeline state."
        )
        XCTAssertTrue(
            source.contains("ContextSection(title: \"会话\")"),
            "The context panel should keep stable session metadata in a dedicated session section."
        )
        XCTAssertTrue(
            source.contains("if let pendingUserDecision {\n                        PendingDecisionPanel"),
            "Pending decisions should remain available as a dedicated panel even after runtime state moves to the top."
        )
        XCTAssertFalse(
            source.contains("} else {\n                        EmptyPlanPanel()"),
            "The context panel should not render a standalone empty plan card when the whole session is still idle."
        )
        XCTAssertTrue(
            source.contains("private var taskPreview: String?"),
            "Pending decision panels should derive an explicit task preview instead of burying the pending task inside a long paragraph."
        )
        XCTAssertTrue(
            source.contains("Text(\"待执行任务\")"),
            "Execution-mode confirmation should surface the pending task in a dedicated preview block for faster scanning."
        )
        XCTAssertTrue(
            source.contains("Text(decisionTitle)"),
            "Pending decision panels should use an action-first title in the header instead of repeating a generic waiting label above the real decision."
        )
        XCTAssertTrue(
            source.contains("Text(\"待确认\")"),
            "Pending decision panels should label the state as awaiting confirmation, not as a vague pending workload."
        )
        XCTAssertTrue(
            source.contains(".help(taskPreview)"),
            "Pending task previews should expose the full task text on hover when truncated."
        )
        XCTAssertTrue(
            source.contains("TaskPlanView(plan: taskPlan)"),
            "The context panel should keep the full task-plan surface available instead of inheriting transcript-specific completion collapse."
        )
        XCTAssertTrue(
            source.contains("workingDirectory: workingDirectory"),
            "The session overview should stay focused on stable context instead of duplicating runtime activity summaries."
        )
        XCTAssertFalse(
            source.contains("activitySummary: activitySummary"),
            "The session overview should not repeat activity-summary text that now belongs in the runtime section."
        )
        XCTAssertFalse(
            source.contains("private var activitySummary: String?"),
            "Runtime and plan state should not be recomputed into a duplicate session-summary string."
        )
        XCTAssertTrue(
            source.contains("if pipeline != nil || pendingUserDecision != nil || singleAgentVerification != nil"),
            "The context panel should keep the runtime section visible even when only pending confirmation or verification state remains."
        )
        XCTAssertTrue(
            source.contains("let pipeline: ExecutionPipeline?"),
            "The runtime focus card should support paused or post-run states even when no active pipeline remains."
        )
        XCTAssertTrue(
            source.contains("taskPlan?.subTasks.filter(\\.needsAttention).count ?? 0"),
            "Runtime attention metrics should use the shared SubTask attention state so blocked subtasks remain visible."
        )
        XCTAssertTrue(
            source.contains("title: \"下一步建议\""),
            "The runtime summary should surface a concrete next action for the user."
        )
        XCTAssertTrue(
            source.contains("title: exceptionalStage.status == .failed ? \"异常阶段\" : \"已停止阶段\""),
            "The runtime summary should call out the most recent exceptional stage explicitly."
        )
        XCTAssertTrue(
            source.contains("taskPlan?.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })"),
            "Runtime recovery guidance should prioritize structured blocked subtasks when choosing the next action."
        )
        XCTAssertTrue(
            source.contains("return recoveryContext.recoveryActionDetail"),
            "Context-panel recovery guidance should route users to a concrete settings destination for blocked subtasks."
        )
        XCTAssertTrue(
            source.contains("if pendingUserDecision != nil {\n            return \"等待确认\""),
            "The context-panel status pill should switch to a waiting-for-user state instead of continuing to read as running while confirmation is pending."
        )
        XCTAssertTrue(
            source.contains("if let singleAgentVerification {\n            return verificationTitle(for: singleAgentVerification.status)\n        }"),
            "The context-panel status pill should prefer verification truth over a neutral runtime label once single-agent execution has already produced a verification outcome."
        )
        XCTAssertTrue(
            source.contains("case .none: return \"运行态\""),
            "The context-panel runtime status should still render a neutral label when no active pipeline is present."
        )
        XCTAssertTrue(
            source.contains("if let pendingUserDecision {\n                RuntimeFocusRow("),
            "Pending confirmation should take priority over the current-stage row in the context panel."
        )
        XCTAssertTrue(
            source.contains("} else if let exceptionalStage {\n                RuntimeFocusRow("),
            "Failed or cancelled runtime states should surface as the primary focus row instead of duplicating a stale current-stage row above them."
        )
        XCTAssertTrue(
            source.contains("value: \"流程已暂停\""),
            "The runtime card should describe pending confirmation as a paused process instead of repeating the detailed decision title."
        )
        XCTAssertTrue(
            source.contains("具体操作见下方待确认卡"),
            "The runtime card should hand off detailed pending-confirmation instructions to the dedicated decision panel below."
        )
        XCTAssertTrue(
            source.contains("if pendingUserDecision == nil {\n                RuntimeFocusRow("),
            "When the panel is already paused on a pending confirmation, it should not repeat the same guidance again as a second next-action card."
        )
        XCTAssertTrue(
            source.contains("} else if let singleAgentVerification {\n                RuntimeFocusRow("),
            "The context-panel focus row should prefer verification state over stale stage framing once execution has already ended."
        )
        XCTAssertTrue(
            source.contains("} else if pipeline?.overallStatus == .completed {\n                RuntimeFocusRow("),
            "Completed runs without a verifier state should still surface a dedicated delivery-review focus row in the context panel."
        )
        XCTAssertFalse(
            source.contains("}\n\n            if let exceptionalStage {\n                RuntimeFocusRow("),
            "Exceptional runtime states should not render as a second stacked focus row after another primary runtime summary."
        )
        XCTAssertTrue(
            source.contains("return \"回复“是”继续多 Agent；回复其他内容会改走单 Agent，也可以直接输入新任务，避免无谓等待。\""),
            "Context-panel next-action guidance should keep the new-task escape hatch visible during execution-mode confirmation."
        )
        XCTAssertTrue(
            source.contains("return \"回复否改单 Agent 或直接改任务\""),
            "Pending decision chips should surface both alternate exits for execution-mode confirmation."
        )
        XCTAssertTrue(
            source.contains("VStack(alignment: .leading, spacing: 8) {\n                DecisionHintChip(icon: \"checkmark.circle\", text: confirmHint, tone: Theme.statusSuccess)\n                DecisionHintChip(icon: \"arrow.triangle.branch\", text: redirectHint, tone: Theme.statusInfo)\n            }"),
            "Pending decision choices should stack vertically so long action labels stay readable in the narrow context panel."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(2)\n                .fixedSize(horizontal: false, vertical: true)"),
            "Decision hint chips should wrap long action labels instead of truncating them into ambiguous fragments."
        )
        XCTAssertTrue(
            source.contains(".help(text)"),
            "Decision hint chips should expose the full action text on hover when space is still tight."
        )
        XCTAssertTrue(
            source.contains("return \"确认是否覆盖 AGENT.md\""),
            "Pending overwrite confirmation should use a direct, action-first title."
        )
        XCTAssertTrue(
            source.contains("return \"确认执行模式\""),
            "Execution-mode confirmation should use a concise, action-first title."
        )
        XCTAssertTrue(
            source.contains("return Theme.statusWarning"),
            "Pending confirmation should use warning tone in the context panel so it reads as attention-needed."
        )
        XCTAssertTrue(
            source.contains("value: verificationFocusValue(for: singleAgentVerification.status)"),
            "The verification summary row should stop repeating the status badge and instead surface a task-oriented review focus."
        )
        XCTAssertTrue(
            source.contains("case .verified:\n                return \"开始下一项任务\""),
            "Verified context-panel next actions should advance to the next task instead of restating that a final-result check exists."
        )
        XCTAssertTrue(
            source.contains("return \"先核对关键文件变更、工具输出和最终结论；确认无误后，直接开始下一项任务。\""),
            "Verified context-panel guidance should remain in a review-and-closeout mode without restating the verified status."
        )
        XCTAssertTrue(
            source.contains("case .verified:\n            return \"优先复核交付结果\""),
            "Verified context-panel focus values should point at the review task rather than echoing the verified badge."
        )
        XCTAssertTrue(
            source.contains("case .unverified:\n            return \"补足完成证据\""),
            "Unverified context-panel focus values should point at the missing work instead of only labeling the state."
        )
        XCTAssertTrue(
            source.contains("case .needsRetry:\n            return \"先修订当前答案\""),
            "Retry-required context-panel focus values should point at the corrective action instead of repeating the warning badge."
        )
        XCTAssertTrue(
            source.contains("title: \"交付摘要\",\n                    value: \"优先复核本次结果\",\n                    detail: \"执行已经结束，先核对关键文件变更、工具输出和验证状态。\""),
            "Completed context-panel focus rows should summarize the review target instead of leaving completion without a focus row."
        )
        XCTAssertTrue(
            source.contains("if pipeline?.overallStatus == .completed {\n            return \"开始下一项任务\"\n        }"),
            "Completed context-panel next actions should move to the next task once review is done."
        )
        XCTAssertTrue(
            source.contains("return \"确认本次结果无误后，直接开始下一项任务；如果还要补查，回到关键文件和工具输出继续核对。\""),
            "Completed context-panel guidance should reserve the next-action row for closeout instead of repeating the review checklist."
        )

        let runtimeRange = try XCTUnwrap(source.range(of: "ContextSection(title: \"运行态\")"))
        let sessionRange = try XCTUnwrap(source.range(of: "ContextSection(title: \"会话\")"))
        let planRange = try XCTUnwrap(source.range(of: "if let pendingUserDecision {"))
        XCTAssertLessThan(
            source.distance(from: source.startIndex, to: runtimeRange.lowerBound),
            source.distance(from: source.startIndex, to: sessionRange.lowerBound),
            "The context panel should surface runtime state before stable session metadata."
        )
        XCTAssertLessThan(
            source.distance(from: source.startIndex, to: sessionRange.lowerBound),
            source.distance(from: source.startIndex, to: planRange.lowerBound),
            "Stable session metadata should appear before deeper plan detail in the sidebar scan order."
        )
    }
}
