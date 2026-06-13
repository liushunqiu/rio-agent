import Foundation

class ShellTool: Tool {
    let name = "execute_command"
    let description = "在终端中执行 shell 命令。支持管道、重定向、变量等标准 shell 特性。安全命令（ls/cat/grep/git status等）自动执行无需确认；普通命令需用户确认（可信任本会话）；危险命令（rm/sudo/curl等）始终需确认且不可信任。优先使用此工具进行文件搜索、目录列表、git 操作、包管理等文件读写工具无法完成的操作。不要用此工具读取文件内容——请改用 read_file。"

    let parameters: [String: ToolParameter] = [
        "command": ToolParameter(type: "string", description: "要执行的 shell 命令。使用标准 shell 语法，支持管道和重定向。安全命令自动执行，危险命令会触发额外确认。", required: true),
        "working_directory": ToolParameter(type: "string", description: "命令执行的工作目录（绝对路径）。不指定则使用当前工作目录。")
    ]

    private var confirmationCallback: ConfirmationCallback?
    private var trustedCommands: Set<String> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func setTrustedCommands(_ commands: Set<String>) {
        self.trustedCommands = commands
    }

    func addTrustedCommand(_ command: String) {
        trustedCommands.insert(command)
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let command = arguments["command"] as? String else {
            throw ToolError.missingParameter("command")
        }

        // Check risk level
        let riskLevel = CommandClassifier.classify(command)

        switch riskLevel {
        case .safe:
            // Auto-approve safe commands
            break

        case .normal:
            // Check if already trusted for this session
            if trustedCommands.contains(command) {
                break
            }

            // Ask for confirmation
            if let confirm = confirmationCallback {
                let result = await confirm(
                    "执行命令确认",
                    "即将执行命令:\n\n\(command)\n\n是否继续？"
                )

                switch result {
                case .approved:
                    break
                case .trustedForSession:
                    addTrustedCommand(command)
                case .denied:
                    return ToolResult.cancelled(toolCallId: "shell", reason: "用户取消执行")
                }
            }

        case .dangerous:
            // Always ask for confirmation
            if let confirm = confirmationCallback {
                let result = await confirm(
                    "⚠️ 危险命令确认",
                    "即将执行危险命令:\n\n\(command)\n\n此操作可能不可逆，是否继续？"
                )

                switch result {
                case .approved, .trustedForSession:
                    break
                case .denied:
                    return ToolResult.cancelled(toolCallId: "shell", reason: "用户取消执行")
                }
            }
        }

        // Use argument working_directory, fall back to ToolRegistry's workingDirectory
        let workDir = (arguments["working_directory"] as? String) ?? ToolRegistry.shared.workingDirectory
        return try await runCommand(command, workingDirectory: workDir)
    }

    /// Maximum output characters to prevent token overflow
    private static let maxOutputChars = 30_000

    private func runCommand(_ command: String, workingDirectory: String?) async throws -> ToolResult {
        // 将整个命令执行移到后台线程，避免阻塞主线程/UI
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            if let workDir = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            }
            
            do {
                try process.run()
                
                // 使用异步方式读取输出，避免阻塞
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                process.waitUntilExit()
                
                var output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                // Truncate large outputs to prevent token overflow
                var truncated = false
                if output.count > Self.maxOutputChars {
                    let endIndex = output.index(output.startIndex, offsetBy: Self.maxOutputChars)
                    output = String(output[..<endIndex])
                    truncated = true
                }
                
                if process.terminationStatus == 0 {
                    if truncated {
                        output += "\n\n⚠️ 输出被截断（超过 \(Self.maxOutputChars / 1000)k 字符）。如需完整输出，请通过管道写入文件后读取。"
                    }
                    return ToolResult.success(toolCallId: "shell", output: output)
                } else {
                    var errorResult = errorOutput.isEmpty ? "命令执行失败 (退出码: \(process.terminationStatus))" : errorOutput
                    if errorResult.count > Self.maxOutputChars {
                        let endIndex = errorResult.index(errorResult.startIndex, offsetBy: Self.maxOutputChars)
                        errorResult = String(errorResult[..<endIndex]) + "\n⚠️ 错误输出被截断"
                    }
                    return ToolResult.error(toolCallId: "shell", error: errorResult)
                }
            } catch {
                return ToolResult.error(toolCallId: "shell", error: "无法执行命令: \(error.localizedDescription)")
            }
        }.value
    }
}
