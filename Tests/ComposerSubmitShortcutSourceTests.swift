import XCTest

final class ComposerSubmitShortcutSourceTests: XCTestCase {
    func testMultilineComposersOnlySubmitThroughExplicitCommandReturnShortcut() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))
        let newChatSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/NewChatPage.swift"))

        let inputAreaSource = try XCTUnwrap(
            contentSource.range(of: "struct InputArea: View")
                .flatMap { start in
                    contentSource.range(of: "// MARK: - Folder Selector", range: start.upperBound..<contentSource.endIndex)
                        .map { end in String(contentSource[start.lowerBound..<end.lowerBound]) }
                }
        )
        let newChatInputCardSource = try XCTUnwrap(
            newChatSource.range(of: "private var inputCard: some View")
                .flatMap { start in
                    newChatSource.range(of: "private var sendButton: some View", range: start.upperBound..<newChatSource.endIndex)
                        .map { end in String(newChatSource[start.lowerBound..<end.lowerBound]) }
                }
        )

        XCTAssertFalse(
            inputAreaSource.contains(".onSubmit"),
            "The main multiline composer should not submit on plain Return; the UI advertises Cmd+Return so plain Return must remain available for composing longer tasks."
        )
        XCTAssertTrue(
            inputAreaSource.contains(".keyboardShortcut(.return, modifiers: .command)"),
            "The main composer should keep the explicit Cmd+Return submit shortcut on the send button."
        )

        XCTAssertFalse(
            newChatInputCardSource.contains(".onSubmit"),
            "The landing-page multiline composer should follow the same explicit Cmd+Return submit behavior."
        )
        XCTAssertTrue(
            newChatSource.contains(".keyboardShortcut(.return, modifiers: .command)"),
            "The landing-page send button should keep Cmd+Return as the explicit keyboard submit path."
        )
    }
}
