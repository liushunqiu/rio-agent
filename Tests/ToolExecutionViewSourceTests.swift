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
}
