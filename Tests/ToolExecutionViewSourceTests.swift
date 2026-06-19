import XCTest

final class ToolExecutionViewSourceTests: XCTestCase {
    func testCompactToolExecutionMessagesKeepFailureDetailsUsable() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ToolExecutionView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("private var statusMessageLineLimit: Int"))
        XCTAssertTrue(source.contains("case .error, .cancelled: return 4"))
        XCTAssertTrue(source.contains("case .failed:"))
        XCTAssertTrue(source.contains("private func statusDetail(for toolCall: ToolCall, result: ToolResult) -> String"))
        XCTAssertTrue(source.contains("private func failureDetail(for toolCall: ToolCall, error: String) -> String"))
        XCTAssertTrue(source.contains("建议先检查 \\(toolCall.name) 的输入和当前工作目录"))
        XCTAssertTrue(source.contains("建议先检查 \\(toolCall.name) 的前置条件或权限配置"))
        XCTAssertTrue(source.contains(".textSelection(.enabled)"))
        XCTAssertTrue(source.contains(".help(statusMessage)"))
        XCTAssertFalse(source.contains("ToolResultDisplay.text(for: result).prefix(80)"))
    }

    func testCompactToolExecutionOnlyTruncatesLongSuccessOutput() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ToolExecutionView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("private func compactStatusMessage(for result: ToolResult) -> String"))
        XCTAssertTrue(source.contains("guard result.status == .success, text.count > 160 else"))
        XCTAssertTrue(source.contains("return String(text.prefix(160)) + \"...\""))
    }

    func testToolExecutionStatesDistinguishQueuedWorkFromUserConfirmation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ToolExecutionView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("case .pending:\n            return \"已加入工具队列，等待当前步骤开始。\""),
            "Queued tools should not be described as waiting for user confirmation."
        )
        XCTAssertTrue(
            source.contains("case .confirming(let toolCall):\n            return confirmationDetail(for: toolCall)"),
            "Confirming tools should surface the concrete action that needs approval."
        )
        XCTAssertTrue(
            source.contains("private func confirmationDetail(for toolCall: ToolCall) -> String")
                && source.contains("等待确认命令：\\(shortened(command))")
                && source.contains("等待确认文件：\\(shortened(path))")
                && source.contains("等待确认补丁：涉及 \\(fileCount) 个文件。"),
            "Confirmation details should help users identify the command, file, or patch scope before approving."
        )
        XCTAssertTrue(
            source.contains("case .confirming:\n            return 4"),
            "Confirmation details should have enough vertical room for long commands or paths."
        )
    }
}
