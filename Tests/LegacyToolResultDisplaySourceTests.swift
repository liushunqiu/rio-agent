import XCTest

final class LegacyToolResultDisplaySourceTests: XCTestCase {
    func testLegacyToolResultCardsUseUnifiedDisplayFormatting() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let messageBubble = try String(contentsOf: repoRoot.appendingPathComponent("Views/MessageBubble.swift"))
        let enhancedToolCard = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))
        let executionView = try String(contentsOf: repoRoot.appendingPathComponent("Views/ToolExecutionView.swift"))

        XCTAssertTrue(
            messageBubble.contains("ToolResultOutputBlock(result: result"),
            "Legacy ToolResultCard should use the shared output block instead of duplicating result formatting."
        )
        XCTAssertTrue(
            enhancedToolCard.contains("ToolResultDisplay.label(for: result)"),
            "The shared output block should use the same labels as enhanced tool cards."
        )
        XCTAssertTrue(
            enhancedToolCard.contains("ToolResultDisplay.text(for: result)"),
            "The shared output block should show placeholders and cancellation reasons consistently."
        )
        XCTAssertTrue(
            enhancedToolCard.contains("ToolResultDisplay.shouldCollapse(result)"),
            "The shared output block should use the shared collapse rule."
        )
        XCTAssertTrue(
            executionView.contains("ToolResultDisplay.text(for: result)"),
            "Compact tool execution summaries should not show blank text for empty success output."
        )
        XCTAssertFalse(
            executionView.contains("result.error ?? \"未知错误\""),
            "Compact tool execution summaries should use the shared fallback text for errors and cancellations."
        )
    }
}
