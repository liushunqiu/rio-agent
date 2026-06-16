import Foundation

// MARK: - Improved Model Capabilities (层次化分类)
// 使用模型家族分类代替线性模式匹配，提升可维护性和查找性能

/// 模型家族枚举
enum ModelFamily {
    case claude(generation: Int, tier: ClaudeTier)
    case openAI(generation: GPTGeneration)
    case deepSeek(variant: DeepSeekVariant)
    case qwen(variant: QwenVariant)
    case gemini(generation: Int, tier: GeminiTier)
    case yi
    case millionContext(provider: String) // GLM, Mimo, MiniMax
    case unknown

    // MARK: - Sub-types

    enum ClaudeTier {
        case opus, sonnet, haiku
    }

    enum GPTGeneration {
        case gpt4o
        case gpt41
        case gpt4Turbo
        case gpt4
        case gpt35
        case o1, o3 // Reasoning models
    }

    enum DeepSeekVariant {
        case v3, r1, chat
    }

    enum QwenVariant {
        case max, plus, turbo
    }

    enum GeminiTier {
        case pro, flash
    }

    // MARK: - Detection

    /// 从模型名称检测模型家族
    static func detect(from modelName: String) -> ModelFamily {
        let lower = modelName.lowercased()

        // Claude
        if lower.contains("claude") {
            let generation: Int
            if lower.contains("claude-4") || lower.contains("claude-sonnet-4") {
                generation = 4
            } else if lower.contains("claude-3") {
                generation = 3
            } else {
                generation = 3 // default
            }

            let tier: ClaudeTier
            if lower.contains("opus") {
                tier = .opus
            } else if lower.contains("sonnet") {
                tier = .sonnet
            } else if lower.contains("haiku") {
                tier = .haiku
            } else {
                tier = .sonnet // default
            }

            return .claude(generation: generation, tier: tier)
        }

        // OpenAI
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") {
            if lower.contains("gpt-4.1") {
                return .openAI(generation: .gpt41)
            } else if lower.contains("gpt-4o") {
                return .openAI(generation: .gpt4o)
            } else if lower.contains("gpt-4-turbo") {
                return .openAI(generation: .gpt4Turbo)
            } else if lower.contains("gpt-4") {
                return .openAI(generation: .gpt4)
            } else if lower.contains("gpt-3.5") {
                return .openAI(generation: .gpt35)
            } else if lower.contains("o3") {
                return .openAI(generation: .o3)
            } else if lower.contains("o1") {
                return .openAI(generation: .o1)
            }
        }

        // DeepSeek
        if lower.contains("deepseek") {
            if lower.contains("r1") || lower.contains("reasoner") {
                return .deepSeek(variant: .r1)
            } else if lower.contains("v3") {
                return .deepSeek(variant: .v3)
            } else {
                return .deepSeek(variant: .chat)
            }
        }

        // Qwen
        if lower.contains("qwen") {
            if lower.contains("max") {
                return .qwen(variant: .max)
            } else if lower.contains("plus") {
                return .qwen(variant: .plus)
            } else {
                return .qwen(variant: .turbo)
            }
        }

        // Gemini
        if lower.contains("gemini") {
            let generation: Int
            if lower.contains("2.5") || lower.contains("3") {
                generation = 3
            } else if lower.contains("2.0") {
                generation = 2
            } else {
                generation = 1
            }

            let tier: GeminiTier = lower.contains("pro") ? .pro : .flash
            return .gemini(generation: generation, tier: tier)
        }

        // Yi
        if lower.contains("yi-") {
            return .yi
        }

        // Million-context models
        if lower.contains("glm") || lower.contains("mimo") || lower.contains("minimax") {
            return .millionContext(provider: lower.contains("glm") ? "GLM" : "Other")
        }

        return .unknown
    }

    // MARK: - Base Capabilities

    var baseCapabilities: ModelCapabilities {
        switch self {
        case .claude(let generation, let tier):
            return claudeCapabilities(generation: generation, tier: tier)
        case .openAI(let generation):
            return openAICapabilities(generation: generation)
        case .deepSeek(let variant):
            return deepSeekCapabilities(variant: variant)
        case .qwen(let variant):
            return qwenCapabilities(variant: variant)
        case .gemini(let generation, let tier):
            return geminiCapabilities(generation: generation, tier: tier)
        case .yi:
            return ModelCapabilities(contextWindow: 200000, maxOutputTokens: 4096)
        case .millionContext:
            return ModelCapabilities(contextWindow: 1_000_000, maxOutputTokens: 16384)
        case .unknown:
            return ModelCapabilities()
        }
    }

    // MARK: - Family-specific Capabilities

    private func claudeCapabilities(generation: Int, tier: ClaudeTier) -> ModelCapabilities {
        let thinking = generation >= 4
        return ModelCapabilities(
            supportsThinking: thinking,
            supportsVision: true,
            contextWindow: 200000,
            maxOutputTokens: generation >= 4 ? 8192 : 4096
        )
    }

    private func openAICapabilities(generation: GPTGeneration) -> ModelCapabilities {
        switch generation {
        case .gpt4o:
            return ModelCapabilities(
                supportsVision: true, supportsJSON: true,
                contextWindow: 128000, maxOutputTokens: 16384
            )
        case .gpt41:
            return ModelCapabilities(
                supportsVision: true, supportsJSON: true,
                contextWindow: 1_047_000, maxOutputTokens: 32768
            )
        case .gpt4Turbo:
            return ModelCapabilities(
                supportsVision: true, supportsJSON: true,
                contextWindow: 128000, maxOutputTokens: 4096
            )
        case .gpt4:
            return ModelCapabilities(
                supportsJSON: true,
                contextWindow: 8192, maxOutputTokens: 8192
            )
        case .gpt35:
            return ModelCapabilities(
                supportsJSON: true,
                contextWindow: 16384, maxOutputTokens: 4096
            )
        case .o1, .o3:
            return ModelCapabilities(
                supportsThinking: true, supportsVision: true, supportsJSON: true,
                contextWindow: 128000, maxOutputTokens: 32768
            )
        }
    }

    private func deepSeekCapabilities(variant: DeepSeekVariant) -> ModelCapabilities {
        let thinking = variant == .r1
        return ModelCapabilities(
            supportsThinking: thinking,
            supportsJSON: true,
            contextWindow: 65536,
            maxOutputTokens: 8192
        )
    }

    private func qwenCapabilities(variant: QwenVariant) -> ModelCapabilities {
        let contextWindow = variant == .max ? 131072 : 32768
        return ModelCapabilities(
            supportsJSON: true,
            contextWindow: contextWindow,
            maxOutputTokens: 8192
        )
    }

    private func geminiCapabilities(generation: Int, tier: GeminiTier) -> ModelCapabilities {
        let thinking = generation >= 2
        return ModelCapabilities(
            supportsThinking: thinking,
            supportsVision: true,
            supportsJSON: true,
            contextWindow: 1_048_576,
            maxOutputTokens: 8192
        )
    }
}

// MARK: - Improved ModelCapabilities Extension

extension ModelCapabilities {
    /// 获取模型能力（使用层次化检测）
    static func capabilitiesV2(for model: String) -> ModelCapabilities {
        let family = ModelFamily.detect(from: model)
        return family.baseCapabilities
    }
}

