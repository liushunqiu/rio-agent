import XCTest
@testable import RioAgent

final class ToolResultDisplayTests: XCTestCase {
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
}
