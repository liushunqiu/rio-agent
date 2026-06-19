import XCTest

final class CopyFeedbackSourceTests: XCTestCase {
    func testCopyFeedbackResetIgnoresStaleDelayedCallbacks() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdown = try String(contentsOf: repoRoot.appendingPathComponent("Views/MarkdownRenderer.swift"))
        let messageBubble = try String(contentsOf: repoRoot.appendingPathComponent("Views/MessageBubble.swift"))
        let toolCard = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))
        let contentView = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            markdown.contains("@State private var copyResetID: UUID?")
                && markdown.contains("guard copyResetID == resetID else { return }"),
            "Code-block copy feedback should ignore stale delayed resets after repeated copy clicks."
        )
        XCTAssertTrue(
            messageBubble.contains("@State private var copyResetID: UUID?")
                && messageBubble.contains("guard copyResetID == resetID else { return }"),
            "Message copy feedback should ignore stale delayed resets after repeated copy clicks."
        )
        XCTAssertGreaterThanOrEqual(
            toolCard.components(separatedBy: "@State private var copyResetID: UUID?").count - 1,
            2,
            "Tool output and argument copy controls should each track their own delayed reset token."
        )
        XCTAssertGreaterThanOrEqual(
            toolCard.components(separatedBy: "guard copyResetID == resetID else { return }").count - 1,
            2,
            "Tool copy controls should ignore stale delayed resets after repeated copy clicks."
        )
        XCTAssertTrue(
            contentView.contains("@State private var copyResetID: UUID?")
                && contentView.contains("copyResetID = nil")
                && contentView.contains("guard copyResetID == resetID else { return }"),
            "Error-banner copy feedback should reset cleanly when the message changes and ignore stale delayed resets."
        )
    }
}
