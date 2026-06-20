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

        // 只有当用户输入恰好以 @ 结尾（且 @ 前是空格、换行或字符串开头）时才触发文件选择器
        // 避免误触发（例如邮箱地址、@ 后继续输入文字等场景）
        if canOpenFilePicker && shouldTriggerFilePicker(for: newValue) {
            isShowingFilePicker = true
        } else {
            isShowingFilePicker = false
        }
    }

    private func shouldTriggerFilePicker(for text: String) -> Bool {
        guard text.hasSuffix("@") else { return false }

        // 如果整个文本就是 "@"，触发
        if text == "@" { return true }

        // 如果 @ 前面是空格或换行符，触发（例如 "hello @"）
        if text.count >= 2 {
            let beforeAt = text[text.index(text.endIndex, offsetBy: -2)]
            return beforeAt.isWhitespace || beforeAt.isNewline
        }

        return false
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

        // 选择文件后自动换行，这样用户继续输入文字时不会和文件路径混在一起
        if !text.isEmpty && !text.hasSuffix("\n") {
            text += "\n"
        }
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
