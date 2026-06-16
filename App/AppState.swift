import Foundation
import Combine
import CoreGraphics

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
