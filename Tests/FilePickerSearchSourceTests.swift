import XCTest

final class FilePickerSearchSourceTests: XCTestCase {
    func testFilePickerSearchUsesDisplayedRelativePathsAndRankedResults() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("displayRelativePath(for: filePath).lowercased()"))
        XCTAssertFalse(source.contains("let relativePath = filePath.lowercased()"))
        XCTAssertTrue(source.contains("fileName.hasPrefix(query)"))
        XCTAssertTrue(source.contains("fileName.contains(query)"))
        XCTAssertTrue(source.contains("relativePath.hasPrefix(query)"))
        XCTAssertTrue(source.contains("relativePath.contains(query)"))
    }

    func testFilePickerLoadedFilesSortByDisplayedRelativePath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("PathSecurity.relativePath($0, from: workingDirectory)"))
        XCTAssertTrue(source.contains("localizedStandardCompare(PathSecurity.relativePath($1, from: workingDirectory))"))
        XCTAssertFalse(source.contains("files = filePaths.sorted()"))
    }

    func testFilePickerRowsExposeFullPathsWhenLabelsAreTruncated() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("helpText: workingDirectory"),
            "The file picker workspace summary should expose the full selected directory."
        )
        XCTAssertTrue(
            source.contains(".help(helpText ?? value)"),
            "Picker summary pills should keep line-limited values discoverable."
        )
        XCTAssertTrue(
            source.contains(".help(filePath)"),
            "File picker rows should expose the absolute file path when file names or relative paths are truncated."
        )
        XCTAssertTrue(
            source.contains(".truncationMode(.middle)"),
            "Long file paths should preserve both leading and trailing context in narrow rows."
        )
    }
}
