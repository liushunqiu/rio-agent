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
            source.contains("title: exceptionalStage.status == .failed ? \"异常焦点\" : \"停止焦点\""),
            "The pipeline banner should distinguish between failures and user-driven cancellation without sounding like a debug console."
        )
        XCTAssertTrue(
            source.contains("title: \"进行中\""),
            "When there is no exception, the pipeline should still expose the active stage with a quieter workbench label."
        )
        XCTAssertTrue(
            source.contains(".help(detail)"),
            "The pipeline insight banner should preserve the full diagnostic guidance on hover."
        )
        XCTAssertTrue(
            source.contains("CompactStatusPill(status: pipeline.overallStatus)"),
            "The pipeline header should use compact status chrome instead of a heavier standalone indicator."
        )
        XCTAssertTrue(
            source.contains("case .singleAgent: return \"单 Agent 流程\""),
            "The pipeline title should stay short and utilitarian."
        )
        XCTAssertTrue(
            source.contains("if !isCollapsed {"),
            "The timeline should be collapsible so finished runs do not dominate the reading flow."
        )
    }
}
