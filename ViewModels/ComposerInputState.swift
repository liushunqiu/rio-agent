import SwiftUI
import Observation

@MainActor
@Observable
final class ComposerInputState {
    var text: String
    var isShowingFilePicker = false
    var selectedFiles: [String] = []

    init(text: String = "") {
        self.text = text
        self.selectedFiles = FileReferenceParser.fileReferences(in: text)
    }

    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateText(_ newValue: String) {
        setText(newValue)
    }

    func updateTextFromUserInput(_ newValue: String, canOpenFilePicker: Bool) {
        setText(newValue)

        if canOpenFilePicker && newValue.hasSuffix("@") {
            isShowingFilePicker = true
        } else {
            isShowingFilePicker = false
        }
    }

    private func setText(_ newValue: String) {
        text = newValue
        selectedFiles = FileReferenceParser.fileReferences(in: newValue)
    }

    func clearInput() {
        text = ""
        selectedFiles.removeAll()
        isShowingFilePicker = false
    }

    func addFileReference(_ filePath: String) {
        text = FileReferenceParser.appendingReference(to: text, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: text)
        isShowingFilePicker = false
    }

    func removeFileReference(_ filePath: String) {
        text = FileReferenceParser.removingReference(from: text, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: text)
    }

    func removeFileReferencesOutsideWorkingDirectory(_ workingDirectory: String?) {
        let cleanedText = FileReferenceParser.removingReferencesOutsideWorkingDirectory(
            from: text,
            workingDirectory: workingDirectory
        )
        guard cleanedText != text else { return }
        updateText(cleanedText)
    }
}
