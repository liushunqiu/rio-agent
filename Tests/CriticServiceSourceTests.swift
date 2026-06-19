import XCTest

final class CriticServiceSourceTests: XCTestCase {
    func testCriticResultSelectionAvoidsForcedUnwraps() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/CriticService.swift"))

        XCTAssertTrue(
            source.contains("guard let primaryResult, let secondaryResult else"),
            "Merged Critic analysis should bind both optional model outputs before use."
        )
        XCTAssertFalse(
            source.contains("primaryResult!") || source.contains("secondaryResult!"),
            "Critic fallback routing should not force-unwrap optional model outputs."
        )
    }
}
