import SwiftUI
import Observation

@MainActor
@Observable
final class NewChatViewModel {
    var composer: ComposerInputState

    init(inputText: String = "") {
        composer = ComposerInputState(text: inputText)
    }

    var inputText: String {
        get { composer.text }
        set { composer.updateText(newValue) }
    }

    var isShowingFilePicker: Bool {
        get { composer.isShowingFilePicker }
        set { composer.isShowingFilePicker = newValue }
    }

    var selectedFiles: [String] {
        composer.selectedFiles
    }

    var canSend: Bool {
        composer.canSend
    }

    func clearInput() {
        composer.clearInput()
    }

    func handleInput(_ text: String) {
        composer.updateText(text)
    }

    func addFileReference(_ filePath: String) {
        composer.addFileReference(filePath)
    }

    func removeFileReference(_ filePath: String) {
        composer.removeFileReference(filePath)
    }
}
