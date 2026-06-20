import XCTest

final class ContextUsageSourceTests: XCTestCase {
    func testContextUsagePercentIsClampedAndWindowSafe() throws {
        let source = try contextPanelSource()

        XCTAssertTrue(source.contains("private var contextUsagePercent: Int"))
        XCTAssertTrue(source.contains("guard contextWindow > 0, estimatedTokens > 0 else { return 0 }"))
        XCTAssertTrue(source.contains("Double(estimatedTokens) / Double(contextWindow) * 100"))
        XCTAssertTrue(source.contains("guard percentage.isFinite else { return 100 }"))
        XCTAssertTrue(source.contains("min(max(Int(percentage.rounded()), 0), 100)"))
        XCTAssertFalse(source.contains("min(estimatedTokens * 100 / contextWindow, 100)"))
    }

    func testContextBarClampsPercentBeforeDrawingAndColoring() throws {
        let source = try contextPanelSource()

        XCTAssertTrue(source.contains("private var clampedPercent: Int"))
        XCTAssertTrue(source.contains("min(max(usedPercent, 0), 100)"))
        XCTAssertTrue(source.contains("CGFloat(clampedPercent) / 100"))
        XCTAssertTrue(source.contains("if clampedPercent < 50"))
        XCTAssertTrue(source.contains("} else if clampedPercent < 80"))
    }

    func testStreamingUiUsesSnapshotsAndCachedTokenEstimates() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let agentSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))

        XCTAssertTrue(contentSource.contains("private struct ContextPanelSnapshot"))
        XCTAssertTrue(contentSource.contains("let snapshot = ContextPanelSnapshot(agentEngine: agentEngine)"))
        XCTAssertTrue(contentSource.contains("private struct MainContentRuntimeSnapshot"))
        XCTAssertTrue(contentSource.contains("let snapshot = MainContentRuntimeSnapshot(agentEngine: agentEngine)"))
        XCTAssertFalse(
            contentSource.contains("messageCount: agentEngine.messages.filter(\\.isVisibleInTranscript).count"),
            "Streaming message updates should not repeatedly filter messages for every chrome subview."
        )

        XCTAssertTrue(agentSource.contains("private var estimatedMessageTokensCache"))
        XCTAssertTrue(agentSource.contains("let builder = contextBuilder"))
        XCTAssertTrue(agentSource.contains("builder.estimateMessageTokens(message)"))
        XCTAssertTrue(agentSource.contains("estimatedMessageTokensCache.removeAll()"))
        XCTAssertFalse(
            agentSource.contains("return messages.reduce(0) { $0 + estimateMessageTokens($1) }"),
            "Context usage should not rebuild ContextBuilder for every message on every UI refresh."
        )
    }

    private func contextPanelSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContextPanel.swift")
        return try String(contentsOf: sourceURL)
    }
}
