import XCTest

final class ModelBadgeSourceTests: XCTestCase {
    func testModelBadgesExposeFullProviderAndModelInformation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains(".help(modelHelpText)"),
            "Model badges should expose the full provider/model text even when the visible label is truncated."
        )
        XCTAssertTrue(
            source.contains("return \"\\(provider) · \\(model)\""),
            "The compact composer badge should include provider and model in its help text."
        )
        XCTAssertTrue(
            source.contains("return \"\\(provider) · \\(currentModelName)\""),
            "The top-bar model badge should include provider and model in its help text."
        )
        XCTAssertTrue(
            source.contains("guard !trimmed.isEmpty else { return \"未选择模型\" }"),
            "Empty model labels should show a clear fallback instead of a blank badge."
        )
    }
}
