import XCTest

final class AgentActivityGroupSourceTests: XCTestCase {
    func testActivityGroupKeepsTruncatedSummaryAndToolNamesDiscoverable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedMessageBubble.swift"))

        XCTAssertTrue(
            source.contains(".help(summaryText)"),
            "Collapsed activity summaries should expose the full text when truncated."
        )
        XCTAssertTrue(
            source.contains(".help(toolCall.name)"),
            "Activity tool rows should expose full tool names when narrow layouts truncate them."
        )
        XCTAssertTrue(
            source.contains("ToolResultOutputBlock(result: result, fontSize: 10, contentPadding: 8)"),
            "Activity tool results should reuse the copyable expandable output block."
        )
        XCTAssertTrue(
            source.contains("ActivityFailureSummaryCard("),
            "Failed activity groups should render a compact failure summary before the per-tool details."
        )
        XCTAssertTrue(
            source.contains("if hasFailure { return \"执行异常\" }"),
            "Failed activity groups should expose an explicit failure title in the collapsed header."
        )
        XCTAssertTrue(
            source.contains("if hasCancellation { return \"执行已停止\" }"),
            "Cancelled activity groups should expose a distinct stopped state instead of blending into normal execution history."
        )
        XCTAssertTrue(
            source.contains("if hasFailure { return \"exclamationmark.triangle.fill\" }"),
            "Failed activity groups should use an alert icon instead of a success icon in the collapsed header."
        )
        XCTAssertTrue(
            source.contains("if hasCancellation { return \"slash.circle\" }"),
            "Cancelled activity groups should use a stopped-state icon in the collapsed header."
        )
        XCTAssertTrue(
            source.contains("isExpanded = hasFailure || hasCancellation || isRunning"),
            "Failed or cancelled activity groups should auto-expand so users can immediately see the blocking reason."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: hasCancellation) { _, cancelled in\n            if cancelled {\n                hasManualExpansionOverride = false\n                isExpanded = true\n            }\n        }"),
            "Activity groups should automatically open when a cancellation lands, not only while tools are actively running."
        )
        XCTAssertTrue(
            source.contains("private var isCompletedCleanly: Bool {\n        !hasFailure && !hasCancellation && !isRunning && completedCount > 0\n    }"),
            "Activity groups should distinguish clean completion from failure or cancellation when deciding how much detail to keep open."
        )
        XCTAssertTrue(
            source.contains("if isCompletedCleanly { return \"执行完成\" }"),
            "Cleanly completed activity groups should read as done instead of looking like generic execution history."
        )
        XCTAssertTrue(
            source.contains("hasManualExpansionOverride = true"),
            "Manual expand/collapse intent should be remembered so automatic state transitions do not fight the user."
        )
        XCTAssertTrue(
            source.contains("} else if isCompletedCleanly && !hasManualExpansionOverride {\n                isExpanded = false\n            }"),
            "Cleanly completed activity groups should auto-collapse after execution finishes unless the user explicitly chose otherwise."
        )
        XCTAssertTrue(
            source.contains("let isSupportingDetail: Bool"),
            "Activity groups should know when they are being shown as supporting detail after a final answer."
        )
        XCTAssertTrue(
            source.contains("if isSupportingDetail && isCompletedCleanly { return \"执行记录\" }"),
            "Cleanly completed tool traces that sit behind a delivered answer should be relabeled as execution records instead of competing with the final result."
        )
        XCTAssertTrue(
            source.contains("if isSupportingDetail && completedCount > 0 { return \"list.bullet.rectangle.portrait\" }"),
            "Supporting execution records should use a calmer record icon instead of the main completion icon."
        )
        XCTAssertTrue(
            source.contains("private var isSupportingRecord: Bool {\n        isSupportingDetail && isCompletedCleanly\n    }"),
            "Activity groups should derive an explicit supporting-record state once a clean tool trace sits behind a delivered answer."
        )
        XCTAssertTrue(
            source.contains("Text(\"按需展开\")"),
            "Supporting execution records should advertise that their detail is secondary and optional."
        )
        XCTAssertTrue(
            source.contains("Theme.bgSecondary.opacity(0.34)"),
            "Supporting execution records should render with a lighter container tone than primary activity cards."
        )
        XCTAssertTrue(
            source.contains("Theme.bgGlass.opacity(0.14)"),
            "Collapsed supporting execution records should use a subtler header fill so they stop competing with the delivered answer."
        )
        XCTAssertTrue(
            source.contains("Text(\"异常摘要\")"),
            "The activity failure summary should clearly label itself for fast scanning."
        )
        XCTAssertTrue(
            source.contains("title: \"下一步建议\""),
            "The activity failure summary should include a concrete next action."
        )
        XCTAssertTrue(
            source.contains("title: \"最近失败工具\""),
            "The activity failure summary should identify the most recent failed tool."
        )
        XCTAssertFalse(
            source.contains("Text(text)\n                                .font(.system(size: 10, design: .monospaced))"),
            "Activity tool results should not fall back to a plain, non-copyable text block."
        )
    }
}
