import Foundation
import AppKit

@MainActor
class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    // MARK: - File Access

    func requestFileAccess(for path: String) async -> Bool {
        let panel = NSOpenPanel()
        panel.message = "请选择要访问的文件夹"
        panel.prompt = "允许访问"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false

        if let window = NSApplication.shared.mainWindow {
            return await panel.beginSheetModal(for: window) == .OK
        } else {
            return panel.runModal() == .OK
        }
    }

    // MARK: - Accessibility

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Confirmation Dialogs

    func showConfirmation(title: String, message: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "执行")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }

    func showInput(title: String, message: String, placeholder: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            textField.placeholderString = placeholder
            alert.accessoryView = textField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                continuation.resume(returning: textField.stringValue)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}
