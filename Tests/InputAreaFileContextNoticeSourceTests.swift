import XCTest

final class InputAreaFileContextNoticeSourceTests: XCTestCase {
    func testInputAreaExplainsAtFileContextRequiresWorkingDirectory() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("private var fileContextNotice: String?"),
            "InputArea should compute a contextual notice for file-reference entry failures."
        )
        XCTAssertTrue(
            source.contains("guard workingDirectory == nil else { return nil }"),
            "The notice should only appear when no workspace is selected."
        )
        XCTAssertTrue(
            source.contains("guard composer.text.hasSuffix(\"@\") else { return nil }"),
            "The notice should appear when the user is trying to add a file reference with @."
        )
        XCTAssertTrue(
            source.contains("先选择工作目录，才能添加文件上下文。"),
            "The notice should tell the user exactly how to unblock file-context selection."
        )
    }

    func testPendingDecisionHintKeepsPriorityOverModelBadge() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("ModelBadge(modelName: modelName, providerName: providerName)\n                        .frame(maxWidth: 180, alignment: .trailing)"),
            "Long model names should be constrained so they do not push status hints out of the input toolbar."
        )
        XCTAssertTrue(
            source.contains(".layoutPriority(2)"),
            "Pending confirmation hints should have higher layout priority than secondary metadata."
        )
    }
}
