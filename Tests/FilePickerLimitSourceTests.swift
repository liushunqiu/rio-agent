import XCTest

final class FilePickerLimitSourceTests: XCTestCase {
    func testFilePickerWarnsWhenRepositoryFileListIsTruncated() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("@State private var didHitFileLimit = false"))
        XCTAssertTrue(source.contains("文件列表已截断到前 \\(maxFilesToLoad) 个结果"))
        XCTAssertTrue(source.contains("didHitFileLimit ? \"\\(files.count)+\" : \"\\(files.count)\""))
        XCTAssertTrue(source.contains("didHitFileLimit && !searchText.isEmpty"))
    }
}
