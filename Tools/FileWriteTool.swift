import Foundation

class FileWriteTool: Tool {
    let name = "write_file"
    let description = "写入文件内容。用于创建新文件或覆盖已有文件。工作目录内的写入自动执行无需确认；写入工作目录外的文件会触发用户确认（可信任该路径）。写入前会自动创建不存在的父目录。注意：此工具会完全覆盖目标文件，而不是追加内容。"

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "文件绝对路径（必须提供完整绝对路径，请勿使用相对路径）。当用户提及相对路径时，应拼接工作目录构成绝对路径。路径对应父目录不存在时会自动创建。", required: true),
        "content": ToolParameter(type: "string", description: "要写入文件的完整内容。注意：这会完全覆盖文件已有内容，而非追加。", required: true)
    ]

    private var confirmationCallback: ConfirmationCallback?
    private var trustedPaths: Set<FileToolTrustScope> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func setTrustedPaths(_ paths: Set<String>) {
        trustedPaths = Set(paths.map { trustScope(for: $0) })
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
        guard let content = arguments["content"] as? String else {
            throw ToolError.missingParameter("content")
        }
        guard PathSecurity.isAbsolutePath(path) else {
            return ToolResult.error(toolCallId: "write_file", error: "path must be an absolute path. Resolve relative paths from the working directory before calling write_file.")
        }

        // Check if path is within working directory — auto-allow
        let isWithinWorkDir = PathSecurity.isWithinDirectory(path, workingDirectory: ToolRegistry.shared.workingDirectory)

        if isWithinWorkDir {
            // 工作目录内写入自动执行，无需确认
        } else if trustedPaths.contains(trustScope(for: path)) {
            // Already trusted, skip confirmation
        } else if let confirm = confirmationCallback {
            let title = "⚠️ 跨目录写入确认"
            let directoryText = ToolRegistry.shared.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleDirectory = directoryText?.isEmpty == false ? directoryText! : "未指定"
            let message = """
            即将写入工作目录外的文件:
            \(path)

            当前工作目录:
            \(visibleDirectory)

            内容预览:
            \(String(content.prefix(200)))\(content.count > 200 ? "..." : "")

            选择“信任本会话”只会信任该文件在当前工作目录下再次写入。

            是否继续？
            """

            let result = await confirm(title, message, true)

            switch result {
            case .approved:
                break
            case .trustedForSession:
                addTrustedPath(path)
            case .denied:
                return ToolResult.cancelled(toolCallId: "write_file", reason: "用户取消写入")
            }
        } else {
            return ToolResult.error(toolCallId: "write_file", error: "写入工作目录外文件需要用户确认")
        }

        do {
            // 将文件写入操作移到后台线程，避免阻塞主线程/UI
            try await Task.detached(priority: .userInitiated) {
                // 创建目录（如果不存在）
                let directory = (path as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }.value
            
            return ToolResult.success(toolCallId: "write_file", output: "文件已写入: \(path)")
        } catch {
            return ToolResult.error(toolCallId: "write_file", error: "无法写入文件: \(error.localizedDescription)")
        }
    }
}
