import Foundation

// MARK: - Model Pattern (data-driven capability matching)

private struct ModelPattern {
    let match: (String) -> Bool
    let capabilities: ModelCapabilities
}

private struct PricingPattern {
    let match: (String) -> Bool
    let pricing: ModelPricing
}

/// Model capability matrix for feature detection
struct ModelCapabilities {
    
    // MARK: - Properties
    
    let supportsToolCalling: Bool
    let supportsStreaming: Bool
    let supportsThinking: Bool  // Claude extended thinking
    let supportsVision: Bool    // Image understanding
    let supportsJSON: Bool      // JSON mode
    let contextWindow: Int
    let maxOutputTokens: Int
    
    // MARK: - Initialization
    
    init(
        supportsToolCalling: Bool = true,
        supportsStreaming: Bool = true,
        supportsThinking: Bool = false,
        supportsVision: Bool = false,
        supportsJSON: Bool = false,
        contextWindow: Int = 8192,
        maxOutputTokens: Int = 4096
    ) {
        self.supportsToolCalling = supportsToolCalling
        self.supportsStreaming = supportsStreaming
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.supportsJSON = supportsJSON
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
    
    // MARK: - Static Model Database
    
    private static let defaultCapabilities = ModelCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        contextWindow: 8192, maxOutputTokens: 4096
    )
    
    private static let capabilityPatterns: [ModelPattern] = [
        // Claude
        .init(match: { $0.contains("claude-sonnet-4") || $0.contains("claude-4") },
              capabilities: .init(supportsThinking: true, supportsVision: true, contextWindow: 200000, maxOutputTokens: 8192)),
        .init(match: { $0.contains("claude-3.5-sonnet") || $0.contains("claude-3-5-sonnet") },
              capabilities: .init(supportsVision: true, contextWindow: 200000, maxOutputTokens: 8192)),
        .init(match: { $0.contains("claude-3-opus") || $0.contains("claude-3.5-opus") },
              capabilities: .init(supportsVision: true, contextWindow: 200000, maxOutputTokens: 4096)),
        .init(match: { $0.contains("claude-3-haiku") || $0.contains("claude-3-5-haiku") },
              capabilities: .init(supportsVision: true, contextWindow: 200000, maxOutputTokens: 4096)),
        // OpenAI (gpt-4.1 before gpt-4o to avoid substring conflicts)
        .init(match: { $0.contains("gpt-4.1") },
              capabilities: .init(supportsVision: true, supportsJSON: true, contextWindow: 1047000, maxOutputTokens: 32768)),
        .init(match: { $0.contains("gpt-4o") },
              capabilities: .init(supportsVision: true, supportsJSON: true, contextWindow: 128000, maxOutputTokens: 16384)),
        .init(match: { $0.contains("o1") || $0.contains("o3") },
              capabilities: .init(supportsThinking: true, supportsVision: true, supportsJSON: true, contextWindow: 128000, maxOutputTokens: 32768)),
        .init(match: { $0.contains("gpt-4-turbo") },
              capabilities: .init(supportsVision: true, supportsJSON: true, contextWindow: 128000, maxOutputTokens: 4096)),
        .init(match: { $0.contains("gpt-4") },
              capabilities: .init(supportsJSON: true, contextWindow: 8192, maxOutputTokens: 8192)),
        .init(match: { $0.contains("gpt-3.5") },
              capabilities: .init(supportsJSON: true, contextWindow: 16384, maxOutputTokens: 4096)),
        // DeepSeek (r1 before v3/general for correct thinking support)
        .init(match: { $0.contains("deepseek-r1") },
              capabilities: .init(supportsThinking: true, supportsJSON: true, contextWindow: 65536, maxOutputTokens: 8192)),
        .init(match: { $0.contains("deepseek-v3") || $0.contains("deepseek") },
              capabilities: .init(supportsJSON: true, contextWindow: 65536, maxOutputTokens: 8192)),
        // Qwen
        .init(match: { $0.contains("qwen-max") || $0.contains("qwen2.5-72b") },
              capabilities: .init(supportsJSON: true, contextWindow: 131072, maxOutputTokens: 8192)),
        .init(match: { $0.contains("qwen") },
              capabilities: .init(supportsJSON: true, contextWindow: 32768, maxOutputTokens: 8192)),
        // Gemini
        .init(match: { $0.contains("gemini-2.0") || $0.contains("gemini-2.5") },
              capabilities: .init(supportsThinking: true, supportsVision: true, supportsJSON: true, contextWindow: 1_048_576, maxOutputTokens: 8192)),
        .init(match: { $0.contains("gemini-1.5") },
              capabilities: .init(supportsVision: true, supportsJSON: true, contextWindow: 1_048_576, maxOutputTokens: 8192)),
        .init(match: { $0.contains("gemini") },
              capabilities: .init(supportsVision: true, supportsJSON: true, contextWindow: 32768, maxOutputTokens: 8192)),
        // Yi
        .init(match: { $0.contains("yi-") },
              capabilities: .init(contextWindow: 200000, maxOutputTokens: 4096)),
        // Million-context models
        .init(match: { $0.contains("mimo") || $0.contains("glm") || $0.contains("mini-max") || $0.contains("minimax") },
              capabilities: .init(contextWindow: 1_000_000, maxOutputTokens: 16384)),
    ]
    
    /// Get capabilities for a specific model
    static func capabilities(for model: String) -> ModelCapabilities {
        let lower = model.lowercased()
        for pattern in capabilityPatterns {
            if pattern.match(lower) { return pattern.capabilities }
        }
        return defaultCapabilities
    }
    
    // MARK: - Convenience Methods
    
    /// Check if the model supports a specific feature
    func supports(feature: ModelFeature) -> Bool {
        switch feature {
        case .toolCalling: return supportsToolCalling
        case .streaming: return supportsStreaming
        case .thinking: return supportsThinking
        case .vision: return supportsVision
        case .json: return supportsJSON
        }
    }
    
    /// Get a human-readable summary of capabilities
    var summary: String {
        var features: [String] = []
        if supportsToolCalling { features.append("工具调用") }
        if supportsStreaming { features.append("流式输出") }
        if supportsThinking { features.append("深度思考") }
        if supportsVision { features.append("图像理解") }
        if supportsJSON { features.append("JSON模式") }
        return features.joined(separator: ", ")
    }
}

// MARK: - Model Pricing

struct ModelPricing {
    /// Cost per million input tokens (USD)
    let inputPerMillion: Double
    /// Cost per million output tokens (USD)
    let outputPerMillion: Double
    
    /// Calculate cost for given token counts
    func cost(promptTokens: Int, completionTokens: Int) -> Double {
        let inputCost = Double(promptTokens) / 1_000_000.0 * inputPerMillion
        let outputCost = Double(completionTokens) / 1_000_000.0 * outputPerMillion
        return inputCost + outputCost
    }
}

extension ModelCapabilities {
    
    private static let defaultPricing = ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0)
    
    private static let pricingPatterns: [PricingPattern] = [
        // Claude
        .init(match: { $0.contains("claude-sonnet-4") || $0.contains("claude-4") }, pricing: .init(inputPerMillion: 3.0, outputPerMillion: 15.0)),
        .init(match: { $0.contains("claude-3-opus") || $0.contains("claude-3.5-opus") || $0.contains("opus-4") }, pricing: .init(inputPerMillion: 15.0, outputPerMillion: 75.0)),
        .init(match: { $0.contains("claude-3-5-haiku") || $0.contains("claude-3.5-haiku") }, pricing: .init(inputPerMillion: 0.80, outputPerMillion: 4.0)),
        .init(match: { $0.contains("claude-3-haiku") }, pricing: .init(inputPerMillion: 0.25, outputPerMillion: 1.25)),
        .init(match: { $0.contains("claude-3-5-sonnet") || $0.contains("claude-3.5-sonnet") }, pricing: .init(inputPerMillion: 3.0, outputPerMillion: 15.0)),
        // OpenAI (specific models before general to avoid substring conflicts)
        .init(match: { $0.contains("gpt-4o-mini") }, pricing: .init(inputPerMillion: 0.15, outputPerMillion: 0.60)),
        .init(match: { $0.contains("gpt-4o") }, pricing: .init(inputPerMillion: 2.50, outputPerMillion: 10.0)),
        .init(match: { $0.contains("gpt-4.1-mini") }, pricing: .init(inputPerMillion: 0.40, outputPerMillion: 1.60)),
        .init(match: { $0.contains("gpt-4.1") }, pricing: .init(inputPerMillion: 2.0, outputPerMillion: 8.0)),
        .init(match: { $0.contains("o3-mini") }, pricing: .init(inputPerMillion: 1.10, outputPerMillion: 4.40)),
        .init(match: { $0.contains("o3") }, pricing: .init(inputPerMillion: 10.0, outputPerMillion: 40.0)),
        .init(match: { $0.contains("o1") }, pricing: .init(inputPerMillion: 15.0, outputPerMillion: 60.0)),
        // DeepSeek (specific variants before general)
        .init(match: { $0.contains("deepseek-v3") || $0.contains("deepseek-chat") }, pricing: .init(inputPerMillion: 0.27, outputPerMillion: 1.10)),
        .init(match: { $0.contains("deepseek-r1") || $0.contains("deepseek-reasoner") }, pricing: .init(inputPerMillion: 0.55, outputPerMillion: 2.19)),
        .init(match: { $0.contains("deepseek") }, pricing: .init(inputPerMillion: 0.44, outputPerMillion: 0.87)),
        // Gemini
        .init(match: { $0.contains("gemini-2.5-flash") || $0.contains("gemini-3-flash") }, pricing: .init(inputPerMillion: 0.50, outputPerMillion: 3.0)),
        .init(match: { $0.contains("gemini-2.5-pro") || $0.contains("gemini-3.1-pro") }, pricing: .init(inputPerMillion: 1.25, outputPerMillion: 10.0)),
        .init(match: { $0.contains("gemini-2.0-flash") }, pricing: .init(inputPerMillion: 0.10, outputPerMillion: 0.40)),
        .init(match: { $0.contains("gemini-1.5-pro") }, pricing: .init(inputPerMillion: 1.25, outputPerMillion: 5.0)),
        .init(match: { $0.contains("gemini-1.5-flash") }, pricing: .init(inputPerMillion: 0.075, outputPerMillion: 0.30)),
        // Qwen
        .init(match: { $0.contains("qwen-max") || $0.contains("qwen2.5-72b") }, pricing: .init(inputPerMillion: 1.60, outputPerMillion: 4.80)),
        .init(match: { $0.contains("qwen-plus") }, pricing: .init(inputPerMillion: 0.40, outputPerMillion: 1.20)),
        .init(match: { $0.contains("qwen-turbo") || $0.contains("qwen3.6-flash") }, pricing: .init(inputPerMillion: 0.05, outputPerMillion: 0.20)),
        // Kimi
        .init(match: { $0.contains("kimi-k2") || $0.contains("moonshot") }, pricing: .init(inputPerMillion: 0.95, outputPerMillion: 4.0)),
        // GLM
        .init(match: { $0.contains("glm-4") || $0.contains("glm-5") }, pricing: .init(inputPerMillion: 0.70, outputPerMillion: 2.80)),
    ]
    
    /// Get pricing information for a model (USD per million tokens)
    /// Based on publicly available pricing as of June 2026
    static func pricing(for model: String) -> ModelPricing {
        let lower = model.lowercased()
        for pattern in pricingPatterns {
            if pattern.match(lower) { return pattern.pricing }
        }
        return defaultPricing
    }
}

// MARK: - Model Features Enum

enum ModelFeature: String, CaseIterable {
    case toolCalling = "tool_calling"
    case streaming = "streaming"
    case thinking = "thinking"
    case vision = "vision"
    case json = "json"
    
    var displayName: String {
        switch self {
        case .toolCalling: return "工具调用"
        case .streaming: return "流式输出"
        case .thinking: return "深度思考"
        case .vision: return "图像理解"
        case .json: return "JSON模式"
        }
    }
}

// MARK: - Model Info

struct ModelInfo: Identifiable {
    let id = UUID()
    let provider: AIProvider
    let modelId: String
    let displayName: String
    let capabilities: ModelCapabilities
    
    /// Get all available models for a provider
    static func availableModels(for provider: AIProvider) -> [ModelInfo] {
        switch provider {
        case .claude:
            return [
                ModelInfo(provider: .claude, modelId: "claude-sonnet-4-20250514", 
                         displayName: "Claude Sonnet 4", 
                         capabilities: .capabilities(for: "claude-sonnet-4-20250514")),
                ModelInfo(provider: .claude, modelId: "claude-3-5-sonnet-20241022", 
                         displayName: "Claude 3.5 Sonnet", 
                         capabilities: .capabilities(for: "claude-3-5-sonnet-20241022")),
                ModelInfo(provider: .claude, modelId: "claude-3-5-haiku-20241022",
                         displayName: "Claude 3.5 Haiku",
                         capabilities: .capabilities(for: "claude-3-5-haiku-20241022")),
                ModelInfo(provider: .claude, modelId: "claude-3-opus-20240229", 
                         displayName: "Claude 3 Opus", 
                         capabilities: .capabilities(for: "claude-3-opus-20240229")),
                ModelInfo(provider: .claude, modelId: "claude-3-haiku-20240307", 
                         displayName: "Claude 3 Haiku", 
                         capabilities: .capabilities(for: "claude-3-haiku-20240307"))
            ]
            
        case .openAI:
            return [
                ModelInfo(provider: .openAI, modelId: "gpt-4o", 
                         displayName: "GPT-4o", 
                         capabilities: .capabilities(for: "gpt-4o")),
                ModelInfo(provider: .openAI, modelId: "gpt-4o-mini",
                         displayName: "GPT-4o Mini",
                         capabilities: .capabilities(for: "gpt-4o-mini")),
                ModelInfo(provider: .openAI, modelId: "gpt-4-turbo", 
                         displayName: "GPT-4 Turbo", 
                         capabilities: .capabilities(for: "gpt-4-turbo")),
                ModelInfo(provider: .openAI, modelId: "gpt-4", 
                         displayName: "GPT-4", 
                         capabilities: .capabilities(for: "gpt-4")),
                ModelInfo(provider: .openAI, modelId: "gpt-3.5-turbo", 
                         displayName: "GPT-3.5 Turbo", 
                         capabilities: .capabilities(for: "gpt-3.5-turbo")),
                ModelInfo(provider: .openAI, modelId: "o1", 
                         displayName: "o1 (Reasoning)", 
                         capabilities: .capabilities(for: "o1")),
                ModelInfo(provider: .openAI, modelId: "o3", 
                         displayName: "o3 (Reasoning)", 
                         capabilities: .capabilities(for: "o3"))
            ]
            
        case .openAICompatible:
            // Custom endpoints - return common models
            return [
                ModelInfo(provider: .openAICompatible, modelId: "gpt-4o", 
                         displayName: "GPT-4o (兼容)", 
                         capabilities: .capabilities(for: "gpt-4o")),
                ModelInfo(provider: .openAICompatible, modelId: "gpt-4o-mini",
                         displayName: "GPT-4o Mini (兼容)",
                         capabilities: .capabilities(for: "gpt-4o-mini")),
                ModelInfo(provider: .openAICompatible, modelId: "deepseek-chat", 
                         displayName: "DeepSeek Chat", 
                         capabilities: .capabilities(for: "deepseek-chat")),
                ModelInfo(provider: .openAICompatible, modelId: "qwen-max", 
                         displayName: "通义千问 Max", 
                         capabilities: .capabilities(for: "qwen-max")),
                ModelInfo(provider: .openAICompatible, modelId: "yi-large", 
                         displayName: "Yi Large", 
                         capabilities: .capabilities(for: "yi-large"))
            ]
        }
    }
}
