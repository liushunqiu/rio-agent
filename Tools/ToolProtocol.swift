import Foundation

// MARK: - Tool Protocol

protocol Tool {
    var name: String { get }
    var description: String { get }
    var parameters: [String: ToolParameter] { get }

    func execute(arguments: [String: Any]) async throws -> ToolResult
}

struct ToolParameter {
    let type: String
    let description: String
    let required: Bool

    init(type: String, description: String, required: Bool = false) {
        self.type = type
        self.description = description
        self.required = required
    }
}

// MARK: - Tool Errors

enum ToolError: LocalizedError {
    case missingParameter(String)
    case invalidParameter(String)
    case executionFailed(String)
    case permissionDenied(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingParameter(let name):
            return "缺少必要参数: \(name)"
        case .invalidParameter(let name):
            return "无效参数: \(name)"
        case .executionFailed(let reason):
            return "执行失败: \(reason)"
        case .permissionDenied(let reason):
            return "权限被拒绝: \(reason)"
        case .timeout:
            return "执行超时"
        }
    }
}

// MARK: - Confirmation

enum ConfirmationResult {
    case approved
    case denied
    case trustedForSession
}

typealias ConfirmationCallback = (_ title: String, _ message: String) async -> ConfirmationResult

// MARK: - Command Risk Level

enum CommandRiskLevel {
    case safe
    case normal
    case dangerous
}

// MARK: - Command Classifier

struct CommandClassifier {
    private static let safeCommands: Set<String> = [
        // 只读文件操作
        "ls", "ll", "la", "tree", "file", "stat", "du", "df",
        "cat", "head", "tail", "less", "more", "wc", "sort", "uniq",
        "diff", "comm", "jq",
        
        // 信息查询
        "echo", "printf", "date", "cal", "env", "printenv", "which", "whereis", "type",
        "pwd", "dirname", "basename", "realpath",
        
        // 查找命令
        "find", "grep", "rg", "ag", "fd", "locate",
        
        // Git 只读操作
        "git status", "git log", "git diff", "git show", "git branch", "git tag",
        "git remote", "git stash list", "git blame", "git shortlog",
        
        // 版本查询
        "swift --version", "python --version", "python3 --version", "node --version",
        "npm --version", "cargo --version", "go version", "java -version",
        
        // 系统信息
        "uname", "hostname", "whoami", "id"
    ]

    private static let dangerousPatterns: [String] = [
        // 文件删除（需要更严格的匹配）
        "rm -rf", "rm -fr", "rm -r", "rm -f",
        "rm ~", "rm /", "rm ~/",
        
        // 系统管理
        "sudo ", "su ",
        
        // 网络下载（可能下载恶意内容）
        "curl ", "wget ", "curl|", "wget|",
        
        // 磁盘操作
        "dd ", "mkfs", "fdisk", "mount", "umount",
        
        // 权限修改
        "chmod 777", "chmod -R 777", "chown", "chgrp",
        
        // 执行外部代码
        "eval ", "exec ",
        
        // 系统控制
        "shutdown", "reboot", "halt", "poweroff",
        
        // 进程管理
        "kill -9", "killall", "pkill",
        
        // 网络/防火墙
        "iptables", "ufw", "firewall",
        
        // 写入设备
        "> /dev/", ">> /dev/",
        
        // 管道到解释器（可能执行恶意代码）
        "| sh", "| bash", "| zsh", "| python", "| node",
        "|sh", "|bash", "|zsh", "|python", "|node",

        // 常见会修改文件的选项
        "sed -i", "perl -i", "tee "
    ]

    private static let shellControlOperators = ["&&", "||", ";"]
    private static let redirectionPatterns = [">", ">>", "1>", "2>", "&>"]

    static func classify(_ command: String, workingDirectory: String? = nil) -> CommandRiskLevel {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .normal }

        let lowercased = trimmed.lowercased()

        // 检查危险模式
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return .dangerous
            }
        }

        if containsShellControlOperator(trimmed) {
            let parts = splitShellControlSegments(trimmed)
            guard parts.count > 1, parts.allSatisfy({ !$0.isEmpty }) else {
                return .normal
            }

            let classifications = parts.map { classify($0, workingDirectory: workingDirectory) }
            if classifications.contains(.dangerous) {
                return .dangerous
            }
            return classifications.allSatisfy { $0 == .safe } ? .safe : .normal
        }

        if containsRedirection(trimmed) {
            return classifyRedirectedCommand(trimmed, workingDirectory: workingDirectory)
        }

        // 管道命令：如果包含管道，检查整体是否安全
        if trimmed.contains("|") {
            let parts = trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            let classifications = parts.map { classify($0, workingDirectory: workingDirectory) }
            if classifications.contains(.dangerous) {
                return .dangerous
            }
            if classifications.allSatisfy({ $0 == .safe }) {
                return .safe
            }
            return .normal
        }

        // 检查安全命令 - O(1) lookup
        let baseCommand = extractBaseCommand(trimmed)
        if safeCommands.contains(baseCommand) {
            return .safe
        }

        // 检查 Git 子命令
        if trimmed.hasPrefix("git ") {
            let parts = trimmed.split(separator: " ")
            if parts.count >= 2 {
                let subcommand = String(parts[1])
                let safeGitSubcommands = ["status", "log", "diff", "show", "blame", "shortlog"]
                if safeGitSubcommands.contains(subcommand) {
                    return .safe
                }
                if subcommand == "stash",
                   parts.count >= 3,
                   String(parts[2]).lowercased() == "list" {
                    return .safe
                }
            }
        }

        // 默认为 normal
        return .normal
    }

    private static func containsShellControlOperator(_ command: String) -> Bool {
        shellControlOperators.contains { command.contains($0) }
    }

    private static func splitShellControlSegments(_ command: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var index = command.startIndex

        while index < command.endIndex {
            if command[index...].hasPrefix("&&") || command[index...].hasPrefix("||") {
                segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                index = command.index(index, offsetBy: 2)
            } else if command[index] == ";" {
                segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                index = command.index(after: index)
            } else {
                current.append(command[index])
                index = command.index(after: index)
            }
        }

        segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return segments
    }

    private static func containsRedirection(_ command: String) -> Bool {
        redirectionPatterns.contains { command.contains($0) }
    }

    private static func classifyRedirectedCommand(_ command: String, workingDirectory: String?) -> CommandRiskLevel {
        guard let parsed = splitCommandAndRedirectionTargets(command) else {
            return .normal
        }

        let baseClassification = classify(parsed.baseCommand, workingDirectory: workingDirectory)
        guard baseClassification == .safe else {
            return baseClassification == .dangerous ? .dangerous : .normal
        }

        guard let workingDirectory, !workingDirectory.isEmpty else {
            return .normal
        }

        let targetsAreWithinWorkDir = parsed.targets.allSatisfy { target in
            guard isPlainRedirectionTarget(target) else { return false }

            let absoluteTarget: String
            if target.hasPrefix("/") || target.hasPrefix("~") {
                absoluteTarget = target
            } else {
                absoluteTarget = (workingDirectory as NSString).appendingPathComponent(target)
            }

            return PathSecurity.isWithinDirectory(absoluteTarget, workingDirectory: workingDirectory)
        }

        return targetsAreWithinWorkDir ? .safe : .normal
    }

    private static func splitCommandAndRedirectionTargets(_ command: String) -> (baseCommand: String, targets: [String])? {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var baseTokens: [String] = []
        var targets: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if let target = inlineRedirectionTarget(in: token) {
                if !target.isEmpty {
                    targets.append(target)
                    index += 1
                } else {
                    guard index + 1 < tokens.count else { return nil }
                    targets.append(tokens[index + 1])
                    index += 2
                }
            } else {
                baseTokens.append(token)
                index += 1
            }
        }

        guard !baseTokens.isEmpty, !targets.isEmpty else { return nil }
        return (baseTokens.joined(separator: " "), targets)
    }

    private static func inlineRedirectionTarget(in token: String) -> String? {
        for redirection in ["2>>", "1>>", "&>>", ">>", "2>", "1>", "&>", ">"] {
            if token == redirection {
                return ""
            }
            if token.hasPrefix(redirection) {
                return String(token.dropFirst(redirection.count))
            }
        }
        return nil
    }

    private static func isPlainRedirectionTarget(_ target: String) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("-") else { return false }

        let dynamicShellCharacters = CharacterSet(charactersIn: "$`*?[]{}()|&;<>")
        return target.rangeOfCharacter(from: dynamicShellCharacters) == nil
    }

    /// Extract the base command (1-2 word prefix) from a shell command string
    private static func extractBaseCommand(_ command: String) -> String {
        let parts = command.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return command }

        // For git commands, include the subcommand (e.g., "git status")
        if parts[0] == "git", parts.count >= 2 {
            return "\(parts[0]) \(parts[1])"
        }

        // For version checks, include the flag (e.g., "swift --version")
        if parts.count >= 2 && parts[1].hasPrefix("--version") {
            return "\(parts[0]) --version"
        }
        if parts.count >= 2 && parts[1].hasPrefix("-version") {
            return "\(parts[0]) -version"
        }

        return String(parts[0])
    }
}
