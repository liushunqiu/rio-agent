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
    /// 按前缀信任: "git push" 信任后, "git push origin main" 也信任
    private var trustedPrefixes: Set<String> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func setTrustedCommands(_ commands: Set<String>) {
        self.trustedCommands = commands
    }

    func addTrustedCommand(_ command: String) {
        trustedCommands.insert(command)
        // 提取命令前缀用于模糊匹配 (最多前2段)
        let parts = command.split(separator: " ", maxSplits: 2)
        if parts.count >= 2 {
            trustedPrefixes.insert("\(parts[0]) \(parts[1])")
        }
    }

    private func isCommandTrusted(_ command: String) -> Bool {
        if trustedCommands.contains(command) { return true }
        // 模糊匹配: 如果 "npm install" 被信任, "npm install lodash" 也信任
        let parts = command.split(separator: " ", maxSplits: 2)
        if parts.count >= 2 {
            let prefix = "\(parts[0]) \(parts[1])"
            if trustedPrefixes.contains(prefix) { return true }
        }
        return false
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
            // Check if already trusted for this session (with fuzzy matching)
            if isCommandTrusted(command) {
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
            } else {
                return ToolResult.error(toolCallId: "shell", error: "执行此命令需要用户确认")
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
            } else {
                return ToolResult.error(toolCallId: "shell", error: "执行危险命令需要用户确认")
            }
        }

        // Use argument working_directory, fall back to ToolRegistry's workingDirectory
        let workDir = (arguments["working_directory"] as? String) ?? ToolRegistry.shared.workingDirectory
        return try await runCommand(command, workingDirectory: workDir)
    }

    /// Maximum output characters to prevent token overflow
    private static let maxOutputChars = 30_000

    private func runCommand(_ command: String, workingDirectory: String?) async throws -> ToolResult {
        do {
            let result = try await ProcessRunner.shared.run(
                command: command,
                workingDirectory: workingDirectory,
                timeout: AppConstants.commandTimeout
            )

            var output = result.output
            var truncated = false
            if output.count > Self.maxOutputChars {
                let endIndex = output.index(output.startIndex, offsetBy: Self.maxOutputChars)
                output = String(output[..<endIndex])
                truncated = true
            }

            if result.isSuccess {
                if truncated {
                    output += "\n\n⚠️ 输出被截断（超过 \(Self.maxOutputChars / 1000)k 字符）。如需完整输出，请通过管道写入文件后读取。"
                }
                return ToolResult.success(toolCallId: "shell", output: output)
            }

            var errorResult = result.error.isEmpty ? "命令执行失败 (退出码: \(result.exitCode))" : result.error
            if errorResult.count > Self.maxOutputChars {
                let endIndex = errorResult.index(errorResult.startIndex, offsetBy: Self.maxOutputChars)
                errorResult = String(errorResult[..<endIndex]) + "\n⚠️ 错误输出被截断"
            }
            return ToolResult.error(toolCallId: "shell", error: errorResult)
        } catch ProcessError.timeout {
            return ToolResult.error(toolCallId: "shell", error: ProcessError.timeout.localizedDescription)
        } catch {
            return ToolResult.error(toolCallId: "shell", error: "无法执行命令: \(error.localizedDescription)")
        }
    }
}
