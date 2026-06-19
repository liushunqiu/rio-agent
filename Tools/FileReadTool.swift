import Foundation

class FileReadTool: Tool {
    let name = "read_file"
    let description = "读取文件内容。工作目录内的读取自动执行；读取工作目录外的文件需要用户确认。当用户想要查看、检查文件内容时应优先使用此工具，而非执行 shell 命令。自动返回行数和完整内容。适用于文本文件（如源代码、配置文件、文档等）。"

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "文件绝对路径（必须提供完整绝对路径，请勿使用相对路径）。当用户提及相对路径时，应拼接工作目录构成绝对路径。", required: true),
        "encoding": ToolParameter(type: "string", description: "文件编码（默认 UTF-8）。仅当文件使用其他编码时才需指定。"),
        "max_lines": ToolParameter(type: "integer", description: "最大返回行数（默认 500）。超过此限制时截断内容。设为 0 表示无限制。"),
        "offset": ToolParameter(type: "integer", description: "从第几行开始读取（从 0 开始，默认 0）。配合 max_lines 实现分页读取。")
    ]

    /// Maximum output characters to prevent token overflow
    private static let maxOutputChars = 50_000
    /// Default maximum lines to return
    private static let defaultMaxLines = 500
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
        guard PathSecurity.isAbsolutePath(path) else {
            return ToolResult.error(toolCallId: "read_file", error: "path must be an absolute path. Resolve relative paths from the working directory before calling read_file.")
        }

        let encodingName = (arguments["encoding"] as? String) ?? "utf-8"
        guard let encoding = Self.encoding(named: encodingName) else {
            return ToolResult.error(toolCallId: "read_file", error: "Unsupported encoding: \(encodingName)")
        }
        let maxLines = (arguments["max_lines"] as? Int) ?? Self.defaultMaxLines
        let offset = (arguments["offset"] as? Int) ?? 0
        guard maxLines >= 0 else {
            return ToolResult.error(toolCallId: "read_file", error: "max_lines must be greater than or equal to 0")
        }
        guard offset >= 0 else {
            return ToolResult.error(toolCallId: "read_file", error: "offset must be greater than or equal to 0")
        }
        let isWithinWorkDir = PathSecurity.isWithinDirectory(path, workingDirectory: ToolRegistry.shared.workingDirectory)

        if isWithinWorkDir {
            // 工作目录内读取自动执行
        } else if trustedPaths.contains(trustScope(for: path)) {
            // 已信任路径跳过确认
        } else if let confirm = confirmationCallback {
            let directoryText = ToolRegistry.shared.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleDirectory = directoryText?.isEmpty == false ? directoryText! : "未指定"
            let result = await confirm(
                "读取文件确认",
                """
                即将读取工作目录外的文件:
                \(path)

                当前工作目录:
                \(visibleDirectory)

                选择“信任本会话”只会信任该文件在当前工作目录下再次读取。

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
                return ToolResult.cancelled(toolCallId: "read_file", reason: "用户取消读取")
            }
        } else {
            return ToolResult.error(toolCallId: "read_file", error: "读取工作目录外文件需要用户确认")
        }

        do {
            // 将文件读取操作移到后台线程，避免阻塞主线程/UI
            let content: String
            let totalLines: Int
            let rawContent = try await Task.detached(priority: .userInitiated) { () -> String in
                try String(contentsOfFile: path, encoding: encoding)
            }.value

            let allLines = rawContent.isEmpty ? [] : rawContent.components(separatedBy: .newlines)
            totalLines = allLines.count

            let startLine = min(offset, totalLines)
            let endLine = maxLines > 0 ? min(startLine + maxLines, totalLines) : totalLines
            let selectedLines = Array(allLines[startLine..<endLine])
            content = selectedLines.joined(separator: "\n")

            // Truncate if output is still too large
            var output = content
            var truncated = false
            if output.count > Self.maxOutputChars {
                let endIndex = output.index(output.startIndex, offsetBy: Self.maxOutputChars)
                output = String(output[..<endIndex])
                truncated = true
            }

            let displayedLines = selectedLines.count
            var header = "文件: \(path)\n总行数: \(totalLines)"
            if displayedLines > 0 && (offset > 0 || (maxLines > 0 && offset + displayedLines < totalLines)) {
                header += "\n显示: 第 \(offset + 1)-\(offset + displayedLines) 行"
            }
            header += "\n---\n"

            var footer = ""
            if truncated {
                footer += "\n\n⚠️ 输出被截断（超过 \(Self.maxOutputChars / 1000)k 字符限制）。使用 offset 和 max_lines 参数分页读取。"
            } else if maxLines > 0 && offset + displayedLines < totalLines {
                footer += "\n\n💡 文件还有更多内容。使用 offset: \(offset + displayedLines) 继续读取。"
            }

            return ToolResult.success(toolCallId: "read_file", output: header + output + footer)
        } catch {
            return ToolResult.error(toolCallId: "read_file", error: "无法读取文件: \(error.localizedDescription)")
        }
    }

    private static func encoding(named name: String) -> String.Encoding? {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "utf-16", "utf16":
            return .utf16
        case "utf-16le", "utf16le":
            return .utf16LittleEndian
        case "utf-16be", "utf16be":
            return .utf16BigEndian
        case "ascii", "us-ascii":
            return .ascii
        case "latin1", "iso-8859-1", "iso latin 1":
            return .isoLatin1
        default:
            return nil
        }
    }
}
