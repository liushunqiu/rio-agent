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
