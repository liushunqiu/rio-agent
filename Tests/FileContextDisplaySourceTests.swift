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
            newChatPage.contains("helpText: workspaceHelpText"),
            "The new-chat workspace summary should route hover text through a dedicated helper so it can explain optional workspace selection before a directory is chosen."
        )
        XCTAssertTrue(
            newChatPage.contains("return \"可以先直接描述任务；需要引用文件或扫描仓库时，再选择工作目录。\""),
            "When no workspace is selected, the landing page should explain that directory selection is optional until file-aware context is needed."
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
