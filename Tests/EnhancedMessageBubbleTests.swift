import XCTest
@testable import RioAgent

final class EnhancedMessageBubbleTests: XCTestCase {
    func testStandaloneToolResultIsShownWhenNoMatchingToolCallExists() {
        let toolCalls = [
            ToolCall(id: "call-1", name: "read_file")
        ]

        XCTAssertFalse(
            EnhancedMessageBubble.shouldDisplayStandaloneToolResult(
                toolCallId: "call-1",
                toolCalls: toolCalls
            )
        )

        XCTAssertTrue(
            EnhancedMessageBubble.shouldDisplayStandaloneToolResult(
                toolCallId: "orphan-result",
                toolCalls: toolCalls
            )
        )

        XCTAssertTrue(
            EnhancedMessageBubble.shouldDisplayStandaloneToolResult(
                toolCallId: "orphan-result",
                toolCalls: nil
            )
        )
    }
}
