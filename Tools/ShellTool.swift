import Foundation

class ShellTool: Tool {
    let name = "execute_command"
    let description = "在终端中执行 shell 命令。支持管道、重定向、变量等标准 shell 特性。安全命令（ls/cat/grep/git status等）自动执行无需确认；普通命令需用户确认（可信任本会话）；危险命令（rm/sudo/curl等）始终需确认且不可信任。优先使用此工具进行文件搜索、目录列表、git 操作、包管理等文件读写工具无法完成的操作。不要用此工具读取文件内容——请改用 read_file。"

    let parameters: [String: ToolParameter] = [
        "command": ToolParameter(type: "string", description: "要执行的 shell 命令。使用标准 shell 语法，支持管道和重定向。安全命令自动执行，危险命令会触发额外确认。", required: true),
        "working_directory": ToolParameter(type: "string", description: "命令执行的工作目录（绝对路径）。不指定则使用当前工作目录。")
    ]

    private struct TrustedCommandScope: Hashable {
        let command: String
        let workingDirectory: String?
    }

    private var confirmationCallback: ConfirmationCallback?
    private var trustedCommands: Set<TrustedCommandScope> = []

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func setTrustedCommands(_ commands: Set<String>) {
        trustedCommands = Set(commands.map { trustScope(for: $0, workingDirectory: nil) })
    }

    func addTrustedCommand(_ command: String) {
        addTrustedCommand(command, workingDirectory: nil)
    }

    func addTrustedCommand(_ command: String, workingDirectory: String?) {
        trustedCommands.insert(trustScope(for: command, workingDirectory: workingDirectory))
    }

    private func isCommandTrusted(_ command: String, workingDirectory: String?) -> Bool {
        trustedCommands.contains(trustScope(for: command, workingDirectory: workingDirectory))
    }

    private func trustScope(for command: String, workingDirectory: String?) -> TrustedCommandScope {
        TrustedCommandScope(
            command: normalizedTrustedCommand(command),
            workingDirectory: normalizedTrustedWorkingDirectory(workingDirectory)
        )
    }

    private func normalizedTrustedCommand(_ command: String) -> String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTrustedWorkingDirectory(_ workingDirectory: String?) -> String? {
        guard let workingDirectory else { return nil }
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return PathSecurity.normalizedPath(trimmed)
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let command = arguments["command"] as? String else {
            throw ToolError.missingParameter("command")
        }

        // Use argument working_directory, fall back to ToolRegistry's workingDirectory
        let workDir = (arguments["working_directory"] as? String) ?? ToolRegistry.shared.workingDirectory
        if let workDir {
            guard PathSecurity.isAbsolutePath(workDir) else {
                return ToolResult.error(toolCallId: "shell", error: "working_directory must be an absolute path")
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workDir, isDirectory: &isDirectory), isDirectory.boolValue else {
                return ToolResult.error(toolCallId: "shell", error: "working_directory does not exist or is not a directory: \(workDir)")
            }
        }

        // Check risk level
        let riskLevel = CommandClassifier.classify(command, workingDirectory: workDir)

        switch riskLevel {
        case .safe:
            // Auto-approve safe commands
            break

        case .normal:
            // Check if already trusted for this session (with fuzzy matching)
            if isCommandTrusted(command, workingDirectory: workDir) {
                break
            }

            // Ask for confirmation
            if let confirm = confirmationCallback {
                let result = await confirm(
                    "执行命令确认",
                    normalCommandConfirmationMessage(command: command, workingDirectory: workDir),
                    true
                )

                switch result {
                case .approved:
                    break
                case .trustedForSession:
                    addTrustedCommand(command, workingDirectory: workDir)
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
                    "即将执行危险命令:\n\n\(command)\n\n此操作可能不可逆，是否继续？",
                    false
                )

                switch result {
                case .approved:
                    break
                case .trustedForSession:
                    return ToolResult.cancelled(toolCallId: "shell", reason: "危险命令不能信任本会话")
                case .denied:
                    return ToolResult.cancelled(toolCallId: "shell", reason: "用户取消执行")
                }
            } else {
                return ToolResult.error(toolCallId: "shell", error: "执行危险命令需要用户确认")
            }
        }

        return try await runCommand(command, workingDirectory: workDir)
    }

    private func normalCommandConfirmationMessage(command: String, workingDirectory: String?) -> String {
        let directory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryText = directory?.isEmpty == false ? directory! : "未指定"
        return """
        即将执行命令:

        \(command)

        工作目录:
        \(directoryText)

        选择“信任本会话”只会信任该命令在当前工作目录下再次执行。

        是否继续？
        """
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
