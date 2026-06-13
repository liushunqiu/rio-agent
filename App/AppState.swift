import Foundation
import Combine
import CoreGraphics

// MARK: - App Configuration

struct AppConfiguration: Codable {
    var aiConfiguration: AIConfiguration
    var windowFrame: WindowFrame?
    var lastConversationId: UUID?

    init() {
        self.aiConfiguration = AIConfiguration()
    }
}

struct WindowFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - App Constants

enum AppConstants {
    static let appName = "Rio Agent"
    static let appVersion = "2.0.0"
    static let defaultWindowSize = CGSize(width: 1100, height: 750)
    static let minWindowSize = CGSize(width: 800, height: 550)

    // API 相关
    static let claudeBaseURL = "https://api.anthropic.com"
    static let openAIBaseURL = "https://api.openai.com"
    static let anthropicVersion = "2023-06-01"

    // 工具相关
    static let maxTokens = 4096
    static let commandTimeout: TimeInterval = 30

    // UI 相关
    static let messageBubbleMaxWidth: CGFloat = 650
    static let animationDuration: Double = 0.3
}

// MARK: - App Errors

enum AppError: LocalizedError {
    case configurationMissing
    case apiKeyMissing(AIProvider)
    case networkError(Error)
    case toolExecutionFailed(String)
    case contextOverflow
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "应用配置缺失"
        case .apiKeyMissing(let provider):
            return "请在设置中配置 \(provider.displayName) 的 API Key"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .toolExecutionFailed(let reason):
            return "工具执行失败: \(reason)"
        case .contextOverflow:
            return "上下文窗口已满，请开始新对话"
        case .cancelled:
            return "操作已取消"
        case .unknown:
            return "未知错误"
        }
    }

    /// Whether this error should be shown to the user
    var isUserVisible: Bool {
        switch self {
        case .cancelled:
            return false
        default:
            return true
        }
    }

    /// Suggested recovery action
    var recoverySuggestion: String? {
        switch self {
        case .apiKeyMissing:
            return "请在设置页面配置对应的 API Key"
        case .networkError:
            return "请检查网络连接和 API 端点地址"
        case .contextOverflow:
            return "请开始新对话或使用 /clear 清除历史"
        case .toolExecutionFailed:
            return "请检查命令是否正确，或尝试其他方法"
        default:
            return nil
        }
    }
}
