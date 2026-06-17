import SwiftUI
import Observation

@MainActor
@Observable
final class NewChatViewModel {
    var inputText: String = ""
    var isShowingFilePicker = false
    var selectedFiles: [String] = []
    
    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func clearInput() {
        inputText = ""
        selectedFiles.removeAll()
    }
    
    func handleInput(_ text: String) {
        selectedFiles = FileReferenceParser.fileReferences(in: text)

        if text.hasSuffix("@") {
            isShowingFilePicker = true
        }
    }
    
    func addFileReference(_ filePath: String) {
        inputText = FileReferenceParser.appendingReference(to: inputText, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: inputText)
        isShowingFilePicker = false
    }
    
    func removeFileReference(_ filePath: String) {
        inputText = FileReferenceParser.removingReference(from: inputText, path: filePath)
        selectedFiles = FileReferenceParser.fileReferences(in: inputText)
    }
}
