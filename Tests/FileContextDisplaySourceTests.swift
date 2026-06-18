import XCTest

final class FileContextDisplaySourceTests: XCTestCase {
    func testSelectedFileTagsReceiveWorkingDirectoryInBothComposerSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentView = try String(
            contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift")
        )
        let newChatPage = try String(
            contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift")
        )

        XCTAssertTrue(contentView.contains("workingDirectory: workingDirectory"))
        XCTAssertTrue(newChatPage.contains("workingDirectory: workingDirectory.wrappedValue"))
        XCTAssertTrue(newChatPage.contains("PathSecurity.relativePath(filePath, from: workingDirectory)"))
        XCTAssertTrue(
            newChatPage.contains("helpText: workingDirectory.wrappedValue"),
            "The new-chat workspace summary should expose the full selected path, not only the folder name."
        )
        XCTAssertTrue(
            newChatPage.contains(".help(helpText ?? value)"),
            "Summary pills should keep truncated values discoverable on hover."
        )
        XCTAssertTrue(
            newChatPage.contains(".help(filePath)"),
            "Selected file tags should expose the absolute path, not only the shortened relative label."
        )
        XCTAssertTrue(
            newChatPage.contains("private var selectedFileSummaryHelp: String"),
            "The new-chat compact selected-file count should expose which files are attached."
        )
        XCTAssertTrue(
            newChatPage.contains(".help(selectedFileSummaryHelp)"),
            "The new-chat selected-file count pill should show the attached file list on hover."
        )
        XCTAssertTrue(
            contentView.contains("private var selectedFileSummaryHelp: String"),
            "The main composer compact selected-file count should expose which files are attached."
        )
        XCTAssertTrue(
            contentView.contains(".help(selectedFileSummaryHelp)"),
            "The main composer selected-file count pill should show the attached file list on hover."
        )
    }
}
