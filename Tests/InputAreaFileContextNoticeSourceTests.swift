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
            source.contains("可以先写任务；需要添加文件上下文时，再选择工作目录。"),
            "The notice should clarify that selecting a workspace is only required for file context, not for starting the task itself."
        )
    }

    func testNewChatPageMatchesMainComposerFileContextNotice() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift"))

        XCTAssertTrue(
            source.contains("private var fileContextNotice: String?"),
            "The landing-page composer should expose the same file-context notice logic as the main composer."
        )
        XCTAssertTrue(
            source.contains("guard workingDirectory.wrappedValue == nil else { return nil }"),
            "The landing-page file-context notice should only appear when no workspace is selected."
        )
        XCTAssertTrue(
            source.contains("guard composer.text.hasSuffix(\"@\") else { return nil }"),
            "The landing-page file-context notice should appear when the user is trying to start an @ file reference."
        )
        XCTAssertTrue(
            source.contains("Image(systemName: \"folder.badge.questionmark\")"),
            "The landing-page notice should use the same compact file-context affordance as the main composer."
        )
        XCTAssertTrue(
            source.contains("可以先写任务；需要添加文件上下文时，再选择工作目录。"),
            "The landing-page notice should clarify that workspace selection is only required for file context."
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
        XCTAssertTrue(
            source.contains(".lineLimit(2)"),
            "Pending confirmation hints in the main composer should allow wrapping instead of collapsing into a single truncated line."
        )
        XCTAssertTrue(
            source.contains(".help(pendingDecisionHint)"),
            "Pending confirmation hints in the main composer should expose the full text on hover."
        )
        XCTAssertTrue(
            source.contains("Image(systemName: \"questionmark.circle\")"),
            "Pending confirmation hints in the main composer should carry an explicit visual affordance instead of reading like plain metadata."
        )
        XCTAssertTrue(
            source.contains("Text(\"\\(composer.selectedFiles.count) 个文件\")"),
            "The main composer file counter should stay concise once files are attached."
        )
        XCTAssertTrue(
            source.contains(".background(Theme.bgGlass.opacity(0.58))"),
            "The main composer file count badge should sit back visually instead of reading like a primary action."
        )
    }
}
