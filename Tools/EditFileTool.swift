import Foundation

class EditFileTool: Tool {
    let name = "edit_file"
    let description = "Edit a file by searching for specific text and replacing it. Safer than write_file for targeted modifications since it only changes the matched portion. The old_text must appear exactly once in the file — if it appears multiple times or not at all, the edit will fail. Work directory edits auto-execute; cross-directory edits require user confirmation."

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "Absolute path of the file to edit. Must be a full absolute path.", required: true),
        "old_text": ToolParameter(type: "string", description: "The exact text to search for in the file. Must match exactly one occurrence.", required: true),
        "new_text": ToolParameter(type: "string", description: "The text to replace old_text with.", required: true)
    ]

    private var confirmationCallback: ConfirmationCallback?
    private var trustedPaths: Set<FileToolTrustScope> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func addTrustedPath(_ path: String) {
        trustedPaths.insert(trustScope(for: path))
    }

    private func trustScope(for path: String) -> FileToolTrustScope {
        FileToolTrustScope(path: path, workingDirectory: ToolRegistry.shared.workingDirectory)
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            throw ToolError.missingParameter("path")
        }
        guard let oldText = arguments["old_text"] as? String else {
            throw ToolError.missingParameter("old_text")
        }
        guard let newText = arguments["new_text"] as? String else {
            throw ToolError.missingParameter("new_text")
        }
        guard PathSecurity.isAbsolutePath(path) else {
            return ToolResult.error(toolCallId: name, error: "path must be an absolute path. Resolve relative paths from the working directory before calling edit_file.")
        }

        // Confirmation check for cross-directory writes
        let isWithinWorkDir = PathSecurity.isWithinDirectory(path, workingDirectory: ToolRegistry.shared.workingDirectory)

        if isWithinWorkDir {
            // Auto-approve
        } else if trustedPaths.contains(trustScope(for: path)) {
            // Already trusted
        } else if let confirm = confirmationCallback {
            let directoryText = ToolRegistry.shared.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleDirectory = directoryText?.isEmpty == false ? directoryText! : "未指定"
            let preview = "原文本:\n\(String(oldText.prefix(200)))\(oldText.count > 200 ? "..." : "")\n\n替换为:\n\(String(newText.prefix(200)))\(newText.count > 200 ? "..." : "")"
            let result = await confirm(
                "跨目录编辑确认",
                """
                即将编辑工作目录外的文件:
                \(path)

                当前工作目录:
                \(visibleDirectory)

                \(preview)

                选择“信任本会话”只会信任该文件在当前工作目录下再次编辑。

                是否继续？
                """,
                true
            )

            switch result {
            case .approved:
                break
            case .trustedForSession:
                addTrustedPath(path)
            case .denied:
                return ToolResult.cancelled(toolCallId: name, reason: "用户取消编辑")
            }
        } else {
            return ToolResult.error(toolCallId: name, error: "编辑工作目录外文件需要用户确认")
        }

        // Check if file exists after any required cross-directory confirmation.
        guard FileManager.default.fileExists(atPath: path) else {
            return ToolResult.error(toolCallId: name, error: "File not found: \(path)")
        }

        // 将文件读取操作移到后台线程，避免阻塞主线程/UI
        let content: String
        do {
            content = try await Task.detached(priority: .userInitiated) {
                try String(contentsOfFile: path, encoding: .utf8)
            }.value
        } catch {
            return ToolResult.error(toolCallId: name, error: "Cannot read file: \(error.localizedDescription)")
        }

        // Check that old_text exists and is unique
        let components = content.components(separatedBy: oldText)
        let matchCount = components.count - 1

        if matchCount == 0 {
            return ToolResult.error(toolCallId: name, error: "old_text not found in file. Make sure the text matches exactly (including whitespace and indentation).")
        }

        if matchCount > 1 {
            return ToolResult.error(toolCallId: name, error: "old_text found \(matchCount) times in the file. It must be unique. Provide more surrounding context to make it unique.")
        }

        // Perform the replacement
        let newContent = content.replacingOccurrences(of: oldText, with: newText)

        do {
            // 将文件写入操作移到后台线程，避免阻塞主线程/UI
            try await Task.detached(priority: .userInitiated) {
                try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            }.value
            return ToolResult.success(toolCallId: name, output: "File edited successfully: \(path)")
        } catch {
            return ToolResult.error(toolCallId: name, error: "Failed to write file: \(error.localizedDescription)")
        }
    }
}
