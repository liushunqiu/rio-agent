import XCTest

final class ToolResultOutputBlockSourceTests: XCTestCase {
    func testToolResultOutputBlockSupportsCopyAndIndependentExpansion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))

        XCTAssertTrue(
            source.contains("struct ToolResultOutputBlock: View"),
            "Tool result text should live in a shared component instead of being duplicated across result cards."
        )
        XCTAssertTrue(
            source.contains("@State private var isOutputExpanded = false"),
            "Long output expansion should be independent from the card-level expanded state."
        )
        XCTAssertTrue(
            source.contains("NSPasteboard.general.setString(displayText, forType: .string)"),
            "Tool output blocks should allow copying the full displayed output/error/cancellation reason."
        )
        XCTAssertTrue(
            source.contains("Text(didCopy ? \"已复制\" : \"复制\")"),
            "The copy action should give immediate feedback."
        )
        XCTAssertTrue(
            source.contains(".help(\"复制完整\\(ToolResultDisplay.label(for: result))\")"),
            "The copy button should expose a clear tooltip for accessibility."
        )
    }

    func testEnhancedAndLegacyToolResultCardsUseSharedOutputBlock() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let enhanced = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))
        let legacy = try String(contentsOf: repoRoot.appendingPathComponent("Views/MessageBubble.swift"))

        XCTAssertTrue(
            enhanced.contains("ToolResultOutputBlock(result: result)"),
            "Enhanced tool result cards should use the shared output block."
        )
        XCTAssertTrue(
            legacy.contains("ToolResultOutputBlock(result: result, fontSize: 12, contentPadding: 10)"),
            "Legacy tool result cards should use the same output interaction behavior."
        )
    }

    func testCancelledToolResultsUseWarningVisualTone() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))

        XCTAssertTrue(
            source.contains("private var outputBackgroundColor: Color"),
            "Tool result blocks should centralize output background color by result status."
        )
        XCTAssertTrue(
            source.contains("case .cancelled:\n            return Theme.statusWarning")
                && source.contains("case .cancelled:\n            return Theme.statusWarning.opacity(0.08)"),
            "Cancelled tool results should use warning semantics instead of looking like ordinary successful output."
        )
        XCTAssertTrue(
            source.contains(".background(outputBackgroundColor)"),
            "The shared output block should apply the status-specific background color."
        )
    }

    func testToolArgumentsUseSharedExpandableCopyableRows() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let enhancedToolCard = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedToolCallCard.swift"))
        let enhancedBubble = try String(contentsOf: repoRoot.appendingPathComponent("Views/EnhancedMessageBubble.swift"))
        let legacyBubble = try String(contentsOf: repoRoot.appendingPathComponent("Views/MessageBubble.swift"))

        XCTAssertTrue(
            enhancedToolCard.contains("struct ToolArgumentRow: View"),
            "Tool arguments should have a shared row component so long paths and JSON values behave consistently."
        )
        XCTAssertTrue(enhancedToolCard.contains(".help(displayValue)"))
        XCTAssertTrue(enhancedToolCard.contains(".help(\"复制完整参数\")"))
        XCTAssertTrue(enhancedToolCard.contains(".help(isExpanded ? \"收起参数\" : \"展开完整参数\")"))
        XCTAssertTrue(enhancedToolCard.contains("NSPasteboard.general.setString(displayValue, forType: .string)"))

        XCTAssertTrue(enhancedToolCard.contains("ToolArgumentRow(name: key, value: value.value)"))
        XCTAssertTrue(enhancedBubble.contains("ToolArgumentRow(name: key, value: value.value, keyWidth: 86, fontSize: 10)"))
        XCTAssertTrue(legacyBubble.contains("ToolArgumentRow(name: key, value: value.value, fontSize: 12)"))

        XCTAssertFalse(enhancedToolCard.contains("Text(String(describing: value.value))"))
        XCTAssertFalse(enhancedBubble.contains("Text(String(describing: value.value))"))
        XCTAssertFalse(legacyBubble.contains("Text(String(describing: value.value))"))
    }
}
