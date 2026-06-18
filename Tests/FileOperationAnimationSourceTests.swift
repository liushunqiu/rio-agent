import XCTest

final class FileOperationAnimationSourceTests: XCTestCase {
    func testFileOperationAnimationsExposeTruncatedExecutionDetails() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/FileOperationAnimationView.swift"))

        XCTAssertTrue(
            source.contains(".help(fileName)"),
            "File operation cards should expose full paths or file names when the visible label is truncated."
        )
        XCTAssertTrue(
            source.contains(".help(diffLine.text)"),
            "Diff previews should expose the full line after one-line truncation."
        )
        XCTAssertTrue(
            source.contains(".help(toolName)"),
            "Enhanced tool execution rows should expose long tool names."
        )
        XCTAssertTrue(
            source.contains(".help(detail)"),
            "Enhanced tool execution rows should expose full detail text."
        )
    }

    func testEnhancedToolExecutionProgressIsClampedBeforeDrawing() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/FileOperationAnimationView.swift"))

        XCTAssertTrue(
            source.contains("private func clampedProgress(_ progress: Double) -> Double"),
            "Progress rendering should clamp caller-provided values before converting them to width."
        )
        XCTAssertTrue(
            source.contains("guard progress.isFinite else { return 0 }"),
            "Non-finite progress values should not produce invalid bar widths."
        )
        XCTAssertTrue(
            source.contains("return min(max(progress, 0), 1)"),
            "Progress values should stay within the 0...1 drawing range."
        )
        XCTAssertTrue(
            source.contains("geometry.size.width * clampedProgress(progress)"),
            "The progress bar should draw from the clamped value."
        )
    }
}
