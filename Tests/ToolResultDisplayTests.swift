import XCTest
@testable import RioAgent

final class ToolResultDisplayTests: XCTestCase {
    func testModelContentUsesErrorAndCancellationReason() {
        XCTAssertEqual(
            ToolResult.error(toolCallId: "call-1", error: "Permission denied").modelContent,
            "Permission denied"
        )
        XCTAssertEqual(
            ToolResult.cancelled(toolCallId: "call-2", reason: "用户停止任务").modelContent,
            "用户停止任务"
        )
    }

    func testErrorResultDisplaysErrorMessageInsteadOfEmptyOutput() {
        let result = ToolResult.error(toolCallId: "call-1", error: "Permission denied")

        XCTAssertEqual(ToolResultDisplay.label(for: result), "错误")
        XCTAssertEqual(ToolResultDisplay.text(for: result), "Permission denied")
    }

    func testCancelledResultDisplaysCancellationReason() {
        let result = ToolResult.cancelled(toolCallId: "call-1", reason: "用户停止任务")

        XCTAssertEqual(ToolResultDisplay.label(for: result), "取消原因")
        XCTAssertEqual(ToolResultDisplay.text(for: result), "用户停止任务")
    }

    func testSuccessfulEmptyResultDisplaysExplicitPlaceholder() {
        let result = ToolResult.success(toolCallId: "call-1", output: "")

        XCTAssertEqual(ToolResultDisplay.label(for: result), "输出")
        XCTAssertEqual(ToolResultDisplay.text(for: result), ToolResultDisplay.emptyOutputPlaceholder)
    }

    func testLongResultShouldCollapse() {
        let result = ToolResult.success(
            toolCallId: "call-1",
            output: (0..<12).map { "line \($0)" }.joined(separator: "\n")
        )

        XCTAssertTrue(ToolResultDisplay.shouldCollapse(result))
    }

    func testLongDiagnosticResultShouldCollapseWithLargerPreview() {
        let shortError = ToolResult.error(
            toolCallId: "call-1",
            error: (0..<10).map { "stack line \($0)" }.joined(separator: "\n")
        )
        let longError = ToolResult.error(
            toolCallId: "call-2",
            error: (0..<14).map { "stack line \($0)" }.joined(separator: "\n")
        )

        XCTAssertEqual(ToolResultDisplay.collapsedLineLimit(for: shortError), 12)
        XCTAssertFalse(ToolResultDisplay.shouldCollapse(shortError))
        XCTAssertTrue(ToolResultDisplay.shouldCollapse(longError))
    }
}
