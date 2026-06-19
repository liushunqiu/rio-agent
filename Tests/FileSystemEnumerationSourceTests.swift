import XCTest

final class FileSystemEnumerationSourceTests: XCTestCase {
    func testRecursiveFileEnumerationContinuesWithPartialScanWarning() throws {
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
            source.contains("return true"),
            "Recursive enumeration should continue after a per-directory traversal error so usable matches are not discarded."
        )
        XCTAssertTrue(
            source.contains("static func partialScanWarning(for scan: RecursiveFileScan) -> String"),
            "Tool-facing repository scans should surface a partial-result warning when some directories could not be read."
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

    func testSearchToolsAppendPartialScanWarningsToOutputs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let findSource = try String(contentsOf: repoRoot.appendingPathComponent("Tools/FindFilesTool.swift"))
        let searchSource = try String(contentsOf: repoRoot.appendingPathComponent("Tools/SearchFilesTool.swift"))

        XCTAssertTrue(findSource.contains("FileSystemToolSupport.partialScanWarning(for: scan)"))
        XCTAssertTrue(searchSource.contains("FileSystemToolSupport.partialScanWarning(for: scan)"))
        XCTAssertTrue(
            findSource.contains("output: \"No files found matching pattern: \\(pattern)\\(warning)\""),
            "find_files should show partial-scan diagnostics even when the matched file list is empty."
        )
        XCTAssertTrue(
            searchSource.contains("output: \"No matches found for pattern: \\(pattern)\\(diagnostics)\""),
            "search_files should show partial-scan diagnostics even when no matching line was found."
        )
        XCTAssertTrue(
            searchSource.contains("diagnostics += \"\\n\\n⚠️ 部分文件无法读取，搜索结果可能不完整：\""),
            "search_files should also diagnose files that were enumerated but could not be decoded."
        )
    }
}
