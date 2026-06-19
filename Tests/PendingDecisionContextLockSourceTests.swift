import XCTest

final class PendingDecisionContextLockSourceTests: XCTestCase {
    func testUnavailableInputLocksContextMutationsAcrossComposerSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let newChatSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift"))

        XCTAssertTrue(
            contentSource.contains("private var canEditContext: Bool {\n        canAcceptInput && pendingUserDecision == nil\n    }"),
            "The main composer should centralize context mutability around both input availability and pending confirmations."
        )
        XCTAssertTrue(
            newChatSource.contains("private var canEditContext: Bool {\n        canAcceptInput && pendingUserDecision == nil\n    }"),
            "The new-chat composer should centralize context mutability around both input availability and pending confirmations."
        )
        XCTAssertTrue(
            contentSource.contains("isLocked: !canEditContext"),
            "The main composer should lock working-directory changes while confirmation is pending or execution is running."
        )
        XCTAssertTrue(
            newChatSource.contains("isLocked: !canEditContext"),
            "The new-chat composer should lock working-directory changes while confirmation is pending or execution is running."
        )
        XCTAssertTrue(
            contentSource.contains(".disabled(workingDirectory == nil || !canEditContext)"),
            "The main composer should disable file attachment buttons whenever context editing is locked."
        )
        XCTAssertTrue(
            newChatSource.contains(".disabled(workingDirectory.wrappedValue == nil || !canEditContext)"),
            "The new-chat composer should disable file attachment buttons whenever context editing is locked."
        )
        XCTAssertTrue(
            contentSource.contains("canOpenFilePicker: workingDirectory != nil && canEditContext"),
            "Typing @ in the main composer should not reopen the file picker while context editing is locked."
        )
        XCTAssertTrue(
            newChatSource.contains("canOpenFilePicker: workingDirectory.wrappedValue != nil && canEditContext"),
            "Typing @ in the new-chat composer should not reopen the file picker while context editing is locked."
        )
        XCTAssertTrue(
            contentSource.contains("isRemovable: canEditContext"),
            "Selected file tags in the main composer should not allow context removal while context editing is locked."
        )
        XCTAssertTrue(
            newChatSource.contains("isRemovable: canEditContext"),
            "Selected file tags in the new-chat composer should not allow context removal while context editing is locked."
        )
        XCTAssertTrue(
            contentSource.contains("当前任务正在执行，完成或停止后再调整文件上下文")
                && newChatSource.contains("当前任务正在执行，完成或停止后再调整文件上下文"),
            "Locked file-context controls should explain that running tasks must finish or stop before context changes."
        )
        XCTAssertTrue(
            contentSource.contains("当前任务正在执行，完成或停止后再调整工作目录")
                && newChatSource.contains("当前任务正在执行，完成或停止后再调整工作目录"),
            "Locked directory controls should explain that running tasks must finish or stop before workspace changes."
        )
        XCTAssertTrue(
            contentSource.contains(".onChange(of: canEditContext)")
                && newChatSource.contains(".onChange(of: canEditContext)")
                && contentSource.contains("composer.isShowingFilePicker = false")
                && newChatSource.contains("composer.isShowingFilePicker = false"),
            "Open file picker sheets should close when context editing becomes locked."
        )
        XCTAssertTrue(
            newChatSource.contains("var isRemovable: Bool = true"),
            "Shared file tags should support non-removable display so pending confirmations can preserve context."
        )
        XCTAssertTrue(
            contentSource.contains("var isLocked: Bool = false"),
            "FolderSelector should support a locked state instead of leaving each caller to partially disable it."
        )
        XCTAssertGreaterThanOrEqual(
            contentSource.components(separatedBy: "guard !isLocked else { return }").count,
            3,
            "FolderSelector actions should defensively no-op while locked, not only rely on disabled button styling."
        )
    }
}
