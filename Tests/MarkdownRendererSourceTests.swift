import XCTest

final class MarkdownRendererSourceTests: XCTestCase {
    func testCodeBlocksAlwaysExposeHeaderAndButtonTooltips() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MarkdownRenderer.swift"))

        XCTAssertTrue(
            source.contains("private var displayLanguage: String"),
            "Code blocks should have a fallback header label when the language is omitted."
        )
        XCTAssertTrue(
            source.contains("return trimmed.isEmpty ? \"code\" : trimmed"),
            "Unlabeled code blocks should render a neutral CODE label instead of an empty header."
        )
        XCTAssertTrue(
            source.contains(".help(isExpanded ? \"收起代码块\" : \"展开完整代码块\")"),
            "The expand/collapse action should expose a clear tooltip."
        )
        XCTAssertTrue(
            source.contains(".help(isCopied ? \"代码已复制\" : \"复制代码\")"),
            "The copy action should expose a clear tooltip and copied state."
        )
    }
}
