import Foundation

class FileWriteTool: Tool {
    let name = "write_file"
    let description = "写入文件内容。用于创建新文件或覆盖已有文件。工作目录内的写入自动执行无需确认；写入工作目录外的文件会触发用户确认（可信任该路径）。写入前会自动创建不存在的父目录。注意：此工具会完全覆盖目标文件，而不是追加内容。"

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "文件绝对路径（必须提供完整绝对路径，请勿使用相对路径）。当用户提及相对路径时，应拼接工作目录构成绝对路径。路径对应父目录不存在时会自动创建。", required: true),
        "content": ToolParameter(type: "string", description: "要写入文件的完整内容。注意：这会完全覆盖文件已有内容，而非追加。", required: true)
    ]

    private var confirmationCallback: ConfirmationCallback?
    private var trustedPaths: Set<String> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func setTrustedPaths(_ paths: Set<String>) {
        self.trustedPaths = paths
    }

    func addTrustedPath(_ path: String) {
        trustedPaths.insert(path)
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            throw ToolError.missingParameter("path")
        }
        guard let content = arguments["content"] as? String else {
            throw ToolError.missingParameter("content")
        }

        // Check if path is within working directory — auto-allow
        let isWithinWorkDir: Bool = {
            guard let workDir = ToolRegistry.shared.workingDirectory else { return false }
            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            let resolvedWorkDir = URL(fileURLWithPath: workDir).resolvingSymlinksInPath().path
            return resolvedPath.hasPrefix(resolvedWorkDir)
        }()

        if isWithinWorkDir {
            // 工作目录内写入自动执行，无需确认
        } else if trustedPaths.contains(path) {
            // Already trusted, skip confirmation
        } else if let confirm = confirmationCallback {
            let title = "⚠️ 跨目录写入确认"
            let message = "即将写入工作目录外的文件:\n\(path)\n\n内容预览:\n\(String(content.prefix(200)))\(content.count > 200 ? "..." : "")\n\n是否继续？"

            let result = await confirm(title, message)

            switch result {
            case .approved:
                break
            case .trustedForSession:
                addTrustedPath(path)
            case .denied:
                return ToolResult.cancelled(toolCallId: "write_file", reason: "用户取消写入")
            }
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
