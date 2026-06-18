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

    private func contextPanelSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContextPanel.swift")
        return try String(contentsOf: sourceURL)
    }
}
