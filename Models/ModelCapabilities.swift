import Foundation

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
    
    /// Get capabilities for a specific model
    static func capabilities(for model: String) -> ModelCapabilities {
        let lowercased = model.lowercased()
        
        // Claude Models
        if lowercased.contains("claude-sonnet-4") || lowercased.contains("claude-4") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: true,
                supportsVision: true,
                supportsJSON: false,
                contextWindow: 200000,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("claude-3.5-sonnet") || lowercased.contains("claude-3-5-sonnet") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: false,
                contextWindow: 200000,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("claude-3-opus") || lowercased.contains("claude-3.5-opus") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: false,
                contextWindow: 200000,
                maxOutputTokens: 4096
            )
        }
        
        if lowercased.contains("claude-3-haiku") || lowercased.contains("claude-3-5-haiku") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: false,
                contextWindow: 200000,
                maxOutputTokens: 4096
            )
        }
        
        // OpenAI GPT-4o Models
        if lowercased.contains("gpt-4o") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 128000,
                maxOutputTokens: 16384
            )
        }
        
        // OpenAI GPT-4.1 Models
        if lowercased.contains("gpt-4.1") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 1047000,
                maxOutputTokens: 32768
            )
        }
        
        // OpenAI o1/o3 Reasoning Models
        if lowercased.contains("o1") || lowercased.contains("o3") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: true,  // Reasoning models have built-in thinking
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 128000,
                maxOutputTokens: 32768
            )
        }
        
        // OpenAI GPT-4 Turbo
        if lowercased.contains("gpt-4-turbo") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 128000,
                maxOutputTokens: 4096
            )
        }
        
        // OpenAI GPT-4
        if lowercased.contains("gpt-4") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 8192,
                maxOutputTokens: 8192
            )
        }
        
        // OpenAI GPT-3.5 Turbo
        if lowercased.contains("gpt-3.5") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 16384,
                maxOutputTokens: 4096
            )
        }
        
        // DeepSeek Models
        if lowercased.contains("deepseek-v3") || lowercased.contains("deepseek-r1") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: lowercased.contains("r1"),  // R1 has reasoning
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 65536,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("deepseek") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 65536,
                maxOutputTokens: 8192
            )
        }
        
        // Qwen Models
        if lowercased.contains("qwen-max") || lowercased.contains("qwen2.5-72b") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 131072,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("qwen") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: true,
                contextWindow: 32768,
                maxOutputTokens: 8192
            )
        }
        
        // Gemini Models
        if lowercased.contains("gemini-2.0") || lowercased.contains("gemini-2.5") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: true,  // Gemini 2.0+ supports thinking
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 1_048_576,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("gemini-1.5") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 1_048_576,
                maxOutputTokens: 8192
            )
        }
        
        if lowercased.contains("gemini") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: true,
                supportsJSON: true,
                contextWindow: 32768,
                maxOutputTokens: 8192
            )
        }
        
        // Yi Models
        if lowercased.contains("yi-") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: false,
                contextWindow: 200000,
                maxOutputTokens: 4096
            )
        }
        
        // Million context models (mimo, glm, minimax)
        if lowercased.contains("mimo") || lowercased.contains("glm") || 
           lowercased.contains("mini-max") || lowercased.contains("minimax") {
            return ModelCapabilities(
                supportsToolCalling: true,
                supportsStreaming: true,
                supportsThinking: false,
                supportsVision: false,
                supportsJSON: false,
                contextWindow: 1_000_000,
                maxOutputTokens: 16384
            )
        }
        
        // Default fallback (conservative)
        return ModelCapabilities(
            supportsToolCalling: true,
            supportsStreaming: true,
            supportsThinking: false,
            supportsVision: false,
            supportsJSON: false,
            contextWindow: 8192,
            maxOutputTokens: 4096
        )
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
