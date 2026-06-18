import XCTest

final class PendingDecisionContextLockSourceTests: XCTestCase {
    func testPendingDecisionLocksContextMutationsAcrossComposerSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let newChatSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift"))

        XCTAssertTrue(
            contentSource.contains("isLocked: pendingUserDecision != nil"),
            "The main composer should lock working-directory changes while a confirmation is pending."
        )
        XCTAssertTrue(
            newChatSource.contains("isLocked: pendingUserDecision != nil"),
            "The new-chat composer should lock working-directory changes while a confirmation is pending."
        )
        XCTAssertTrue(
            contentSource.contains(".disabled(workingDirectory == nil || pendingUserDecision != nil)"),
            "The main composer should disable file attachment buttons during pending confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains(".disabled(workingDirectory.wrappedValue == nil || pendingUserDecision != nil)"),
            "The new-chat composer should disable file attachment buttons during pending confirmation."
        )
        XCTAssertTrue(
            contentSource.contains("canOpenFilePicker: workingDirectory != nil && pendingUserDecision == nil"),
            "Typing @ in the main composer should not reopen the file picker during pending confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains("canOpenFilePicker: workingDirectory.wrappedValue != nil && pendingUserDecision == nil"),
            "Typing @ in the new-chat composer should not reopen the file picker during pending confirmation."
        )
        XCTAssertTrue(
            contentSource.contains("isRemovable: pendingUserDecision == nil"),
            "Selected file tags in the main composer should not allow context removal during pending confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains("isRemovable: pendingUserDecision == nil"),
            "Selected file tags in the new-chat composer should not allow context removal during pending confirmation."
        )
        XCTAssertTrue(
            newChatSource.contains("var isRemovable: Bool = true"),
            "Shared file tags should support non-removable display so pending confirmations can preserve context."
        )
        XCTAssertTrue(
            contentSource.contains("var isLocked: Bool = false"),
            "FolderSelector should support a locked state instead of leaving each caller to partially disable it."
        )
    }
}
