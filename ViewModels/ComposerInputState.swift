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
        text = newValue
        selectedFiles = FileReferenceParser.fileReferences(in: newValue)

        if newValue.hasSuffix("@") {
            isShowingFilePicker = true
        }
    }

    func clearInput() {
        text = ""
        selectedFiles.removeAll()
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
}
