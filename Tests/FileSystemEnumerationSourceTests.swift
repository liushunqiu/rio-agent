import XCTest

final class FileSystemEnumerationSourceTests: XCTestCase {
    func testRecursiveFileEnumerationFailsLoudlyOnTraversalErrors() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/FileSystemToolSupport.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("errorHandler: { url, error in"),
            "Recursive file enumeration should observe traversal failures instead of silently skipping them."
        )
        XCTAssertTrue(
            source.contains("RioLogger.tool.warning"),
            "Traversal failures should be logged so partial repository scans are diagnosable."
        )
        XCTAssertTrue(
            source.contains("throw ToolError.executionFailed(\"Unable to fully enumerate path: \\(rootPath). \\(enumerationFailure.localizedDescription)\")"),
            "Tool-facing repository scans should fail loudly when enumeration becomes incomplete."
        )
    }

    func testFilePickerOnlyShowsReadFailureStateWhenEnumerationProducedNoUsableFiles() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("var encounteredEnumerationError = false"))
        XCTAssertTrue(source.contains("errorHandler: { _, _ in"))
        XCTAssertTrue(source.contains("encounteredEnumerationError = true"))
        XCTAssertTrue(
            source.contains("loadingFailed = filePaths.isEmpty && encounteredEnumerationError"),
            "The picker should distinguish a genuine read failure from a partial scan that still produced files."
        )
    }
}

