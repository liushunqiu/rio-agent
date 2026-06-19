import Foundation

struct OpenAIStreamingState {
    private(set) var fullContent = ""
    private(set) var fullReasoning = ""
    private var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]

    var content: String? {
        fullContent.isEmpty ? nil : fullContent
    }

    var reasoningContent: String? {
        fullReasoning.isEmpty ? nil : fullReasoning
    }

    var toolCalls: [ToolCall]? {
        let calls = toolCallAccumulators
            .sorted(by: { $0.key < $1.key })
            .compactMap { _, acc -> ToolCall? in
                guard !acc.id.isEmpty, !acc.name.isEmpty else { return nil }
                var arguments: [String: AnyCodable] = [:]
                if let argsData = acc.args.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                    arguments = argsDict.mapValues { AnyCodable($0) }
                }
                return ToolCall(id: acc.id, name: acc.name, arguments: arguments)
            }
        return calls.isEmpty ? nil : calls
    }

    mutating func consumeSSEDataLine(_ jsonStr: String) -> (content: String?, reasoning: String?) {
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return (nil, nil)
        }

        var contentChunk: String?
        if let content = delta["content"] as? String, !content.isEmpty {
            fullContent += content
            contentChunk = content
        }

        var reasoningChunk: String?
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            fullReasoning += reasoning
            reasoningChunk = reasoning
        }

        if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
            for tcDelta in toolCallDeltas {
                let index = tcDelta["index"] as? Int ?? 0
                var acc = toolCallAccumulators[index] ?? (id: "", name: "", args: "")

                if let id = tcDelta["id"] as? String {
                    acc.id = id
                }

                if let function = tcDelta["function"] as? [String: Any] {
                    if let name = function["name"] as? String {
                        acc.name += name
                    }
                    if let args = function["arguments"] as? String {
                        acc.args += args
                    }
                }

                toolCallAccumulators[index] = acc
            }
        }

        return (contentChunk, reasoningChunk)
    }
}

class OpenAIService: AIService {
    let provider: AIProvider
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    init(apiKey: String, baseURL: String = "https://api.openai.com", provider: AIProvider = .openAI) {
        self.apiKey = apiKey
        // Strip trailing slashes and any trailing /v1 path to avoid duplication
        var cleaned = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if cleaned.hasSuffix("/v1") {
            cleaned = String(cleaned.dropLast(3))
        }
        self.baseURL = cleaned
        self.provider = provider
    }

    // MARK: - Non-streaming

    func sendMessage(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = AppConstants.maxTokens
    ) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = buildRequestBody(messages: messages, tools: tools, model: model, stream: false, maxTokens: maxTokens)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.timeout
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return try parseResponse(data)
    }

    // MARK: - Streaming

    func sendMessageStreaming(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = AppConstants.maxTokens,
        onChunk: @escaping (String) async -> Void,
        onThinkingChunk: @escaping (String) async -> Void
    ) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        RioLogger.service.apiRequest(provider: "OpenAI", model: model, messageCount: messages.count)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = buildRequestBody(messages: messages, tools: tools, model: model, stream: true, maxTokens: maxTokens)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var streamState = OpenAIStreamingState()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.timeout
        } catch {
            RioLogger.service.error("❌ 请求失败: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            RioLogger.service.error("❌ API 错误 (\(httpResponse.statusCode)): \(errorBody, privacy: .public)")
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }

            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }

            let chunks = streamState.consumeSSEDataLine(jsonStr)
            if let content = chunks.content {
                await onChunk(content)
            }
            if let reasoning = chunks.reasoning {
                await onThinkingChunk(reasoning)
            }
        }

        RioLogger.service.apiResponse(provider: "OpenAI", contentLength: streamState.fullContent.count, toolCallCount: streamState.toolCalls?.count ?? 0)

        return AIResponse(
            content: streamState.content,
            reasoningContent: streamState.reasoningContent,
            toolCalls: streamState.toolCalls,
            usage: nil
        )
    }

    // MARK: - Request Builder

    func buildRequestBody(messages: [Message], tools: [[String: Any]], model: String, stream: Bool, maxTokens: Int = AppConstants.maxTokens) -> [String: Any] {
        var apiMessages: [[String: Any]] = []

        for message in messages {
            var apiMessage: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content
            ]

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                apiMessage["tool_calls"] = toolCalls.map { tc in
                    let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments.mapValues { $0.value })) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                    return [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": argsString
                        ]
                    ]
                }
            }

            if let toolResults = message.toolResults, !toolResults.isEmpty {
                for tr in toolResults {
                    let resultMsg: [String: Any] = [
                        "role": "tool",
                        "tool_call_id": tr.toolCallId,
                        "content": tr.modelContent
                    ]
                    apiMessages.append(resultMsg)
                }
                if !message.content.isEmpty {
                    apiMessages.append(apiMessage)
                }
            } else {
                apiMessages.append(apiMessage)
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "stream": stream
        ]

        if !tools.isEmpty {
            body["tools"] = tools
        }

        return body
    }

    // MARK: - Response Parser

    func parseResponse(_ data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let content = message["content"] as? String

        var toolCalls: [ToolCall]?
        if let calls = message["tool_calls"] as? [[String: Any]] {
            toolCalls = calls.compactMap { call in
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let argumentsString = function["arguments"] as? String else {
                    return nil
                }

                guard let argumentsData = argumentsString.data(using: .utf8),
                      let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
                    return nil
                }

                let codableArguments = arguments.mapValues { AnyCodable($0) }
                return ToolCall(id: id, name: name, arguments: codableArguments)
            }
        }

        let reasoningContent = message["reasoning_content"] as? String

        var usage: AIResponse.Usage?
        if let usageDict = json["usage"] as? [String: Any],
           let promptTokens = usageDict["prompt_tokens"] as? Int,
           let completionTokens = usageDict["completion_tokens"] as? Int {
            usage = AIResponse.Usage(promptTokens: promptTokens, completionTokens: completionTokens)
        }

        return AIResponse(content: content, reasoningContent: reasoningContent, toolCalls: toolCalls, usage: usage)
    }
}
