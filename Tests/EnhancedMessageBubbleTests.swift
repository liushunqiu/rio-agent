import XCTest
@testable import RioAgent

final class EnhancedMessageBubbleTests: XCTestCase {
    func testDistanceFromBottomIncreasesWhenContentBottomIsBelowViewport() {
        XCTAssertEqual(
            EnhancedChatView.distanceFromBottom(contentBottom: 600, viewportHeight: 600),
            0
        )
        XCTAssertEqual(
            EnhancedChatView.distanceFromBottom(contentBottom: 960, viewportHeight: 600),
            360
        )
        XCTAssertEqual(
            EnhancedChatView.distanceFromBottom(contentBottom: 560, viewportHeight: 600),
            0
        )
    }

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
