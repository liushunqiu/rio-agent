import XCTest

final class FinalAnswerPresentationSourceTests: XCTestCase {
    func testMessageModelExposesFinalAnswerPresentation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Models/Message.swift"))

        XCTAssertTrue(
            source.contains("case finalAnswer"),
            "Message presentation should model final answers explicitly so the UI does not have to guess which assistant reply is the delivered result."
        )
        XCTAssertTrue(
            source.contains("presentation != .internalOnly"),
            "Final answers should remain transcript-visible without overloading the normal/internal-only visibility split."
        )
        XCTAssertTrue(
            source.contains("var isFinalAnswer: Bool"),
            "Message should expose a dedicated final-answer semantic for transcript rendering."
        )
        XCTAssertTrue(
            source.contains("presentation == .finalAnswer"),
            "Final-answer detection should be explicit instead of heuristic-only."
        )
    }

    func testAgentEngineMarksOnlyLatestDeliveredAnswerAsFinal() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        XCTAssertTrue(
            source.contains("presentation: .finalAnswer"),
            "Delivered assistant results should be persisted with final-answer presentation semantics."
        )
        XCTAssertTrue(
            source.contains("messages[priorFinalAnswerIndex].presentation = .normal"),
            "Older delivered answers should fall back to normal transcript styling once a newer final answer arrives."
        )
        XCTAssertTrue(
            source.contains("messages[lastIndex].presentation = .finalAnswer"),
            "Finalized streaming assistant messages should be upgraded to the final-answer presentation."
        )
    }

    func testTranscriptHighlightsDeliveredAnswerWithoutElevatingAllAssistantMessages() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MessageBubble.swift"))

        XCTAssertTrue(
            source.contains("if message.isFinalAnswer"),
            "Assistant message rendering should branch on the explicit final-answer semantic."
        )
        XCTAssertTrue(
            source.contains("Text(\"最终答复\")"),
            "Delivered answers should carry a visible final-answer label in the transcript."
        )
        XCTAssertTrue(
            source.contains("Text(\"已交付\")"),
            "Delivered answers should read as completed output rather than another in-flight assistant turn."
        )
        XCTAssertTrue(
            source.contains("message.isFinalAnswer ? Theme.statusSuccess.opacity(0.34) : Theme.assistantBubbleBorder"),
            "Final-answer cards should use a dedicated completion border instead of blending into ordinary assistant messages."
        )
        XCTAssertTrue(
            source.contains("message.isFinalAnswer ? Theme.bgGlass.opacity(0.72) : Theme.assistantBubbleBg"),
            "Final-answer cards should use a slightly stronger container fill than ordinary assistant messages."
        )
        XCTAssertTrue(
            source.contains("color: message.isFinalAnswer ? Theme.statusSuccess.opacity(0.12) : Theme.shadowSoft"),
            "Delivered result cards should cast a slightly stronger completion-toned shadow than ordinary assistant messages."
        )
        XCTAssertTrue(
            source.contains("Label(\"最终结果\", systemImage: \"flag.checkered.2.crossed\")"),
            "Final-answer footer metadata should reinforce that the message is the delivered result."
        )
    }

    func testEnhancedTranscriptHeaderUsesFinalAnswerSemantics() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedMessageBubble.swift"))

        XCTAssertTrue(
            source.contains("if message.isFinalAnswer {\n            return \"最终答复\""),
            "Enhanced transcript headers should rename delivered assistant output instead of keeping the generic assistant label."
        )
        XCTAssertTrue(
            source.contains("if message.isFinalAnswer {\n            return \"checkmark.seal.fill\""),
            "Final answers should carry a completion icon in the enhanced transcript header."
        )
        XCTAssertTrue(
            source.contains("if message.isFinalAnswer {\n            return Theme.statusSuccess"),
            "Final answers should use completion tone in the enhanced transcript header."
        )
    }
}
