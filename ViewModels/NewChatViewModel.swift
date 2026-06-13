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
        // 检查是否输入了@符号
        if text.hasSuffix("@") {
            isShowingFilePicker = true
        }
    }
    
    func addFileReference(_ filePath: String) {
        // 移除末尾的@符号，添加文件引用
        if inputText.hasSuffix("@") {
            inputText = String(inputText.dropLast())
        }
        
        // 添加文件引用到输入文本
        let fileRef = "@file:\(filePath)"
        inputText += fileRef
        
        // 记录选择的文件
        if !selectedFiles.contains(filePath) {
            selectedFiles.append(filePath)
        }
        
        isShowingFilePicker = false
    }
    
    func removeFileReference(_ filePath: String) {
        // 从输入文本中移除文件引用
        let fileRef = "@file:\(filePath)"
        inputText = inputText.replacingOccurrences(of: fileRef, with: "")
        
        // 从选择的文件列表中移除
        selectedFiles.removeAll { $0 == filePath }
    }
}
