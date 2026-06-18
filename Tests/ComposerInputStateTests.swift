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

    func testUpdateTextDoesNotOpenFilePickerForExternalDraftRestore() {
        let composer = ComposerInputState()

        composer.updateText("请看这个 @")

        XCTAssertFalse(composer.isShowingFilePicker)
    }

    func testUserInputOpensFilePickerOnlyWhenWorkspaceAllowsIt() {
        let composer = ComposerInputState()

        composer.updateTextFromUserInput("请看这个 @", canOpenFilePicker: false)
        XCTAssertFalse(composer.isShowingFilePicker)

        composer.updateTextFromUserInput("请看这个 @", canOpenFilePicker: true)
        XCTAssertTrue(composer.isShowingFilePicker)
    }

    func testUserInputClosesFilePickerWhenAtTriggerIsRemoved() {
        let composer = ComposerInputState()

        composer.updateTextFromUserInput("请看这个 @", canOpenFilePicker: true)
        XCTAssertTrue(composer.isShowingFilePicker)

        composer.updateTextFromUserInput("请看这个", canOpenFilePicker: true)
        XCTAssertFalse(composer.isShowingFilePicker)
    }

    func testUserInputClosesFilePickerWhenWorkspaceBecomesUnavailable() {
        let composer = ComposerInputState()

        composer.updateTextFromUserInput("请看这个 @", canOpenFilePicker: true)
        XCTAssertTrue(composer.isShowingFilePicker)

        composer.updateTextFromUserInput("请看这个 @", canOpenFilePicker: false)
        XCTAssertFalse(composer.isShowingFilePicker)
    }

    func testRemovingFileReferencesOutsideWorkingDirectoryUpdatesTextAndSelection() {
        let composer = ComposerInputState(text: """
        请处理
        @file:/tmp/project/App.swift
        @file:/tmp/old/Legacy.swift
        """)

        composer.removeFileReferencesOutsideWorkingDirectory("/tmp/project")

        XCTAssertEqual(composer.text, "请处理\n@file:/tmp/project/App.swift")
        XCTAssertEqual(composer.selectedFiles, ["/tmp/project/App.swift"])
    }

    func testRemovingFileReferencesWithoutWorkingDirectoryKeepsTaskTextOnly() {
        let composer = ComposerInputState(text: """
        请处理
        @file:/tmp/project/App.swift
        """)

        composer.removeFileReferencesOutsideWorkingDirectory(nil)

        XCTAssertEqual(composer.text, "请处理")
        XCTAssertEqual(composer.selectedFiles, [])
    }

    func testClearInputClosesFilePickerAndClearsSelectedFiles() {
        let composer = ComposerInputState(text: """
        请处理
        @file:/tmp/project/App.swift
        """)
        composer.updateTextFromUserInput("请处理 @", canOpenFilePicker: true)
        XCTAssertTrue(composer.isShowingFilePicker)

        composer.clearInput()

        XCTAssertEqual(composer.text, "")
        XCTAssertEqual(composer.selectedFiles, [])
        XCTAssertFalse(composer.isShowingFilePicker)
    }
}
