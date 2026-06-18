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
            source.contains(".help(activitySummary)"),
            "Session activity summaries should remain discoverable when truncated."
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
            source.contains("if let pendingUserDecision {\n                RuntimeFocusRow("),
            "Pending confirmation should take priority over the current-stage row in the context panel."
        )
        XCTAssertTrue(
            source.contains("return Theme.statusWarning"),
            "Pending confirmation should use warning tone in the context panel so it reads as attention-needed."
        )
    }
}
