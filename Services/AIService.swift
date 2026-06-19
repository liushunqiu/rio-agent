import Foundation

// MARK: - AI Service Protocol

protocol AIService {
    var provider: AIProvider { get }

    func sendMessage(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int
    ) async throws -> AIResponse

    func sendMessageStreaming(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int,
        onChunk: @escaping (String) async -> Void,
        onThinkingChunk: @escaping (String) async -> Void
    ) async throws -> AIResponse
}

// MARK: - AI Response

struct AIResponse {
    let content: String?
    let reasoningContent: String?
    let toolCalls: [ToolCall]?
    let usage: Usage?

    struct Usage {
        let promptTokens: Int
        let completionTokens: Int
    }
}

// MARK: - Streaming Chunk

enum StreamChunk {
    case text(String)
    case toolCall(ToolCall)
    case done
    case error(Error)
}

// MARK: - AI Service Factory

class AIServiceFactory {
    static func createService(provider: AIProvider, apiKey: String, baseURL: String) -> AIService {
        let resolvedBaseURL = provider.resolvedBaseURL(baseURL)
        switch provider {
        case .claude:
            return ClaudeService(apiKey: apiKey, baseURL: resolvedBaseURL)
        case .openAI:
            return OpenAIService(apiKey: apiKey, baseURL: resolvedBaseURL)
        case .openAICompatible:
            return OpenAIService(apiKey: apiKey, baseURL: resolvedBaseURL, provider: provider)
        }
    }
}
