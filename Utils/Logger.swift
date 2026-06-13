import Foundation
import os

// MARK: - Rio Logger

/// Unified logging system for Rio Agent using Apple's os.Logger
enum RioLogger {
    private static let subsystem = "com.rioagent.app"

    /// Agent engine operations (conversation loop, tool calls, context management)
    static let agent = Logger(subsystem: subsystem, category: "agent")

    /// AI service API calls (request/response, streaming, errors)
    static let service = Logger(subsystem: subsystem, category: "service")

    /// Tool execution (file ops, shell commands, etc.)
    static let tool = Logger(subsystem: subsystem, category: "tool")

    /// UI events (user interactions, view lifecycle)
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Configuration and persistence
    static let config = Logger(subsystem: subsystem, category: "config")

    /// Network and connectivity
    static let network = Logger(subsystem: subsystem, category: "network")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log a tool execution start
    func toolStarted(_ name: String, args: String? = nil) {
        if let args = args {
            info("🔧 [\(name)] 开始执行 - 参数: \(args, privacy: .private)")
        } else {
            info("🔧 [\(name)] 开始执行")
        }
    }

    /// Log a tool execution completion
    func toolCompleted(_ name: String, success: Bool, outputPreview: String? = nil) {
        if success {
            if let preview = outputPreview {
                info("✅ [\(name)] 执行成功 - \(preview, privacy: .public)")
            } else {
                info("✅ [\(name)] 执行成功")
            }
        } else {
            if let preview = outputPreview {
                error("❌ [\(name)] 执行失败 - \(preview, privacy: .public)")
            } else {
                error("❌ [\(name)] 执行失败")
            }
        }
    }

    /// Log an API request
    func apiRequest(provider: String, model: String, messageCount: Int) {
        info("🌐 [\(provider)] API 请求 - 模型: \(model, privacy: .public), 消息数: \(messageCount)")
    }

    /// Log an API response
    func apiResponse(provider: String, contentLength: Int, toolCallCount: Int) {
        info("📥 [\(provider)] API 响应 - 内容长度: \(contentLength), 工具调用: \(toolCallCount)")
    }
}
