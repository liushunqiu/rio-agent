import XCTest
@testable import RioAgent

@MainActor
final class ComposerInputStateTests: XCTestCase {
    func testUpdateTextRefreshesSelectedFilesFromExternalDraft() {
        let composer = ComposerInputState()

        composer.updateText("""
        请处理这些文件
        @file:/tmp/project/App.swift
        @file:/tmp/project/Model.swift
        """)

        XCTAssertEqual(
            composer.selectedFiles,
            ["/tmp/project/App.swift", "/tmp/project/Model.swift"]
        )
        XCTAssertTrue(composer.canSend)
    }

    func testUpdateTextClearsSelectedFilesWhenDraftIsExternallyReset() {
        let composer = ComposerInputState(text: """
        请处理
        @file:/tmp/project/App.swift
        """)

        composer.updateText("")

        XCTAssertEqual(composer.selectedFiles, [])
        XCTAssertFalse(composer.canSend)
    }
}
