import Foundation

// MARK: - Token Tracker Module
// 从 AgentEngine 中提取的独立 Token 追踪模块
// 注意：这是示例代码，需要根据项目实际的 Message 和 AIResponse 类型调整

/// Token 使用追踪器，负责估算和记录 Token 消耗
class TokenTracker {

    // MARK: - Properties

    /// 累积的 Token 使用量
    private(set) var accumulatedUsage: (promptTokens: Int, completionTokens: Int) = (0, 0)

    /// 会话总成本（美元）
    private(set) var sessionCost: Double = 0.0

    /// Token 估算缓存（消息 ID -> Token 数）
    private var tokenCache: [UUID: Int] = [:]

    /// 默认模型（用于定价计算）
    private var defaultModel: String

    // MARK: - Initialization

    init(defaultModel: String = "gpt-4o") {
        self.defaultModel = defaultModel
    }

    // MARK: - Public Methods

    /// 记录 API 响应中的 Token 使用
    /// 注意：需要 AIResponse.Usage 类型，请根据项目实际类型调整
    func trackUsage(promptTokens: Int, completionTokens: Int, model: String? = nil) {
        accumulatedUsage.promptTokens += promptTokens
        accumulatedUsage.completionTokens += completionTokens

        // 计算增量成本
        let modelName = model ?? defaultModel
        let pricing = ModelCapabilities.pricing(for: modelName)
        sessionCost += pricing.cost(
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    /// 重置追踪数据（开始新对话时）
    func reset() {
        accumulatedUsage = (0, 0)
        sessionCost = 0.0
        tokenCache.removeAll()
    }

    /// 获取会话使用摘要
    func getSessionSummary() -> String {
        let totalTokens = accumulatedUsage.promptTokens + accumulatedUsage.completionTokens
        guard totalTokens > 0 else { return "" }

        let costUSD = sessionCost
        let costCNY = costUSD * 7.25

        return "Tokens: \(accumulatedUsage.promptTokens) in / \(accumulatedUsage.completionTokens) out | ~$\(String(format: "%.4f", costUSD)) (≈¥\(String(format: "%.2f", costCNY)))"
    }

    // MARK: - Token Estimation (Improved Algorithm)

    /// 估算文本的 Token 数量（带内容类型检测）
    func estimateTokens(_ text: String) -> Int {
        let contentType = detectContentType(text)
        return estimateTokens(text, contentType: contentType)
    }

    /// 估算文本的 Token 数量（改进的启发式算法）
    func estimateTokens(_ text: String, contentType: ContentType) -> Int {
        guard !text.isEmpty else { return 0 }

        let coefficient = contentType.coefficient
        var asciiCount = 0
        var cjkCount = 0
        var otherCount = 0

        for char in text {
            if char.isASCII {
                asciiCount += 1
            } else if char.unicodeScalars.first.map({ isCJK($0) }) == true {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }

        let asciiTokens = Double(asciiCount) / coefficient.ascii
        let cjkTokens = Double(cjkCount) / coefficient.cjk
        let otherTokens = Double(otherCount) / coefficient.other

        return Int(asciiTokens + cjkTokens + otherTokens) + 1
    }

    /// 检测内容类型以选择合适的系数
    func detectContentType(_ text: String) -> ContentType {
        let sample = String(text.prefix(500))

        // 检测 JSON
        if sample.hasPrefix("{") || sample.hasPrefix("[") {
            return .json
        }

        // 检测代码（关键字密度）
        let codeKeywords = ["func", "class", "import", "struct", "let", "var", "const", "def"]
        let keywordCount = codeKeywords.reduce(0) { count, keyword in
            count + sample.components(separatedBy: keyword).count - 1
        }
        if keywordCount > 3 {
            return .code
        }

        // 检测 CJK 占比
        let cjkCount = sample.filter { char in
            char.unicodeScalars.first.map({ isCJK($0) }) == true
        }.count
        if Double(cjkCount) / Double(sample.count) > 0.3 {
            return .cjk
        }

        return .mixed
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF) ||
               (value >= 0x3400 && value <= 0x4DBF) ||
               (value >= 0x3000 && value <= 0x303F) ||
               (value >= 0xFF00 && value <= 0xFFEF)
    }
}

// MARK: - Content Type

enum ContentType {
    case pureText
    case code
    case json
    case mixed
    case cjk

    var coefficient: TokenCoefficient {
        switch self {
        case .pureText:
            return TokenCoefficient(ascii: 4.2, cjk: 1.8, other: 2.5)
        case .code:
            return TokenCoefficient(ascii: 3.0, cjk: 1.8, other: 2.2)
        case .json:
            return TokenCoefficient(ascii: 2.8, cjk: 1.8, other: 2.0)
        case .mixed:
            return TokenCoefficient(ascii: 3.5, cjk: 1.8, other: 2.3)
        case .cjk:
            return TokenCoefficient(ascii: 4.0, cjk: 1.8, other: 2.4)
        }
    }
}

struct TokenCoefficient {
    let ascii: Double
    let cjk: Double
    let other: Double
}


