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
    private static let safeCommands: [String] = [
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

        // 常见会修改文件的选项
        "sed -i", "perl -i", "tee "
    ]

    static func classify(_ command: String) -> CommandRiskLevel {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()

        // 检查危险模式
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return .dangerous
            }
        }

        // 检查安全命令
        for safeCmd in safeCommands {
            if trimmed == safeCmd || trimmed.hasPrefix(safeCmd + " ") || trimmed.hasPrefix(safeCmd + "\t") {
                return .safe
            }
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

        // 管道命令：如果包含管道，检查整体是否安全
        if trimmed.contains("|") {
            let parts = trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            // 如果所有部分都是安全命令，则整体安全
            let allSafe = parts.allSatisfy { part in
                classify(part) == .safe
            }
            if allSafe {
                return .safe
            }
        }

        // 默认为 normal
        return .normal
    }
}
