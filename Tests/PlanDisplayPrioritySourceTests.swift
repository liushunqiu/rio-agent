import XCTest

final class PlanDisplayPrioritySourceTests: XCTestCase {
    func testMultiAgentPlanTakesPriorityOverSingleAgentPlanInSharedChrome() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentView = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let contextPanel = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContextPanel.swift"))

        XCTAssertLessThan(
            try XCTUnwrap(contentView.range(of: "if let currentTaskPlan")?.lowerBound),
            try XCTUnwrap(contentView.range(of: "if let singleAgentPlan")?.lowerBound),
            "Top bar progress should show Multi-Agent task progress when both plan states exist."
        )
        XCTAssertLessThan(
            try XCTUnwrap(contextPanel.range(of: "} else if let taskPlan")?.lowerBound),
            try XCTUnwrap(contextPanel.range(of: "} else if let singleAgentPlan")?.lowerBound),
            "Context panel should render TaskPlanView before falling back to the single-agent plan."
        )
        XCTAssertLessThan(
            try XCTUnwrap(contextPanel.range(of: "if let taskPlan")?.lowerBound),
            try XCTUnwrap(contextPanel.range(of: "if let singleAgentPlan")?.lowerBound),
            "Context activity summary should prefer Multi-Agent task progress over stale single-agent progress."
        )
    }

    func testMultiAgentChromeSummaryIncludesFailedAndCancelledCounts() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentView = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let contextPanel = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContextPanel.swift"))

        for source in [contentView, contextPanel] {
            XCTAssertTrue(
                source.contains("private func multiAgentSummary(for plan: TaskPlan) -> String"),
                "Shared chrome should use an explicit Multi-Agent summary helper instead of showing only completed count."
            )
            XCTAssertTrue(
                source.contains("let failed = plan.subTasks.filter { $0.status == .failed }.count"),
                "Multi-Agent summary should count failed subtasks."
            )
            XCTAssertTrue(
                source.contains("let cancelled = plan.subTasks.filter { $0.status == .cancelled }.count"),
                "Multi-Agent summary should count cancelled subtasks."
            )
            XCTAssertTrue(
                source.contains("parts.append(\"失败 \\(failed)\")"),
                "Failed subtasks should be visible in the compact summary."
            )
            XCTAssertTrue(
                source.contains("parts.append(\"停止 \\(cancelled)\")"),
                "Cancelled subtasks should be visible in the compact summary."
            )
        }
    }
}
