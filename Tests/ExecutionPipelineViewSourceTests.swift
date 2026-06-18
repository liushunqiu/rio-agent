import XCTest

final class ExecutionPipelineViewSourceTests: XCTestCase {
    func testPipelineDetailsStayReadableForFailuresAndLargeToolLists() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ExecutionPipelineView.swift"))

        XCTAssertTrue(
            source.contains("private var stageSummaryLineLimit: Int"),
            "Failed and cancelled stages should allow more than one summary line."
        )
        XCTAssertTrue(
            source.contains(".textSelection(.enabled)"),
            "Failure and cancellation details should be selectable so users can copy exact diagnostics."
        )
        XCTAssertTrue(
            source.contains("return Array(toolCalls.prefix(12))"),
            "Large tool lists should be capped to keep the pipeline panel scannable."
        )
        XCTAssertTrue(
            source.contains("另有 \\(hiddenToolCallCount) 个工具调用"),
            "When tool calls are capped, the UI should disclose how many are hidden."
        )
        XCTAssertTrue(
            source.contains("Text(\"工具列表\")"),
            "The execution detail should label the tool list explicitly."
        )
        XCTAssertTrue(
            source.contains(".help(stageSummary)"),
            "Truncated stage summaries should expose the full diagnostic text on hover."
        )
        XCTAssertTrue(
            source.contains(".help(tool)"),
            "Middle-truncated tool call names should expose their full value on hover."
        )
        XCTAssertTrue(
            source.contains(".help(substep.title)"),
            "Substep titles can contain long commands or file paths and should be discoverable after truncation."
        )
        XCTAssertTrue(
            source.contains(".help(value)"),
            "Detail rows should preserve full values even when the visible text is line-limited."
        )
        XCTAssertTrue(
            source.contains("PipelineInsightBanner("),
            "The pipeline view should render a compact top-level insight banner for the current or exceptional stage."
        )
        XCTAssertTrue(
            source.contains("title: exceptionalStage.status == .failed ? \"异常总览\" : \"停止总览\""),
            "The pipeline banner should distinguish between failures and user-driven cancellation."
        )
        XCTAssertTrue(
            source.contains("title: \"当前焦点\""),
            "When there is no exception, the pipeline should still expose the current focus stage in a readable summary banner."
        )
        XCTAssertTrue(
            source.contains(".help(detail)"),
            "The pipeline insight banner should preserve the full diagnostic guidance on hover."
        )
    }
}
