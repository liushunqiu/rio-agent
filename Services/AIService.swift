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
        switch provider {
        case .claude:
            return ClaudeService(apiKey: apiKey, baseURL: baseURL)
        case .openAI, .openAICompatible:
            return OpenAIService(apiKey: apiKey, baseURL: baseURL)
        }
    }
}

// MARK: - SSE Parser

class SSEParser {
    /// Parse a Server-Sent Events stream from URLSession bytes
    static func parse(
        _ data: Data,
        onEvent: (String, String) -> Void
    ) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")

        var currentEvent = ""
        var currentData = ""

        for line in lines {
            if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                currentData = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.isEmpty && !currentData.isEmpty {
                onEvent(currentEvent, currentData)
                currentEvent = ""
                currentData = ""
            }
        }

        // Handle remaining data
        if !currentData.isEmpty {
            onEvent(currentEvent, currentData)
        }
    }
}
