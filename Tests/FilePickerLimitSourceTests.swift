import XCTest

final class FilePickerLimitSourceTests: XCTestCase {
    func testFilePickerWarnsWhenRepositoryFileListIsTruncated() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("@State private var didHitFileLimit = false"))
        XCTAssertTrue(source.contains("@State private var loadingFailed = false"))
        XCTAssertTrue(source.contains("文件列表已截断到前 \\(maxFilesToLoad) 个结果"))
        XCTAssertTrue(source.contains("didHitFileLimit ? \"\\(files.count)+\" : \"\\(files.count)\""))
        XCTAssertTrue(source.contains("didHitFileLimit && isSearching"))
        XCTAssertTrue(source.contains("if didHitFileLimit && isSearching { return \"未匹配到已加载文件\" }"))
        XCTAssertTrue(source.contains("if didHitFileLimit && isSearching { return \"当前只搜索已加载的前 \\(maxFilesToLoad) 个文件；如果没找到，请缩小工作目录或直接输入 @file: 绝对路径\" }"))
        XCTAssertTrue(source.contains("if hasWorkingDirectory {"))
        XCTAssertTrue(source.contains("if shouldShowRecentFilesSummary {"))
        XCTAssertTrue(source.contains("private var hasWorkingDirectory: Bool {\n        workingDirectory != nil\n    }"))
        XCTAssertTrue(source.contains("private var shouldShowRecentFilesSummary: Bool {\n        hasWorkingDirectory && !recentFiles.isEmpty\n    }"))
        XCTAssertTrue(source.contains("if workingDirectory == nil { return \"还没有工作目录\" }"))
        XCTAssertTrue(source.contains("if loadingFailed { return \"暂时无法读取文件\" }"))
        XCTAssertTrue(source.contains("if workingDirectory == nil { return \"可以先写任务；需要文件上下文时再选择目录\" }"))
        XCTAssertTrue(source.contains("if loadingFailed { return \"检查工作目录权限或路径是否仍然可用，然后重新打开这里\" }"))
        XCTAssertTrue(source.contains("可以先关闭这里继续写任务；需要文件上下文时，再从输入框下方选择目录。"))
        XCTAssertTrue(source.contains("return \"需要文件上下文时，再选择工作目录\""))
        XCTAssertTrue(source.contains("loadingFailed = true"))
        XCTAssertTrue(source.contains("loadingFailed = false"))
    }
}
