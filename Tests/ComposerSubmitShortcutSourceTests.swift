import XCTest

final class ComposerSubmitShortcutSourceTests: XCTestCase {
    func testMultilineComposersSubmitOnReturnAndReserveShiftReturnForNewline() throws {
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

        // Plain Return submits through an explicit onKeyPress handler. We deliberately avoid
        // .onSubmit so the handler can let Shift+Return fall through (.ignored) as a newline,
        // matching the mainstream chat convention (Return sends, Shift+Return composes).
        XCTAssertTrue(
            inputAreaSource.contains(".onKeyPress(.return"),
            "The main composer should submit on plain Return through an explicit onKeyPress handler."
        )
        XCTAssertFalse(
            inputAreaSource.contains(".onSubmit"),
            "The main composer should not rely on .onSubmit; Return is handled via onKeyPress so Shift+Return can stay a newline."
        )
        XCTAssertTrue(
            inputAreaSource.contains(".shift"),
            "The main composer must reserve Shift+Return for inserting a newline."
        )

        XCTAssertTrue(
            newChatInputCardSource.contains(".onKeyPress(.return"),
            "The landing-page composer should submit on plain Return through an explicit onKeyPress handler."
        )
        XCTAssertFalse(
            newChatInputCardSource.contains(".onSubmit"),
            "The landing-page composer should not rely on .onSubmit; Return is handled via onKeyPress."
        )
        XCTAssertTrue(
            newChatInputCardSource.contains(".shift"),
            "The landing-page composer must reserve Shift+Return for inserting a newline."
        )
    }
}
