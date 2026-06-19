import Foundation

class ClaudeService: AIService {
    let provider: AIProvider = .claude
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    init(apiKey: String, baseURL: String = "https://api.anthropic.com") {
        self.apiKey = apiKey
        // 自动去除 baseURL 末尾的 /v1，避免拼接时出现 /v1/v1/ 导致 404
        var cleaned = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if cleaned.hasSuffix("/v1") {
            cleaned = String(cleaned.dropLast(3))
        }
        self.baseURL = cleaned
    }

    // MARK: - Non-streaming

    func sendMessage(
        _ messages: [Message],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = AppConstants.maxTokens
    ) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

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
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = buildRequestBody(messages: messages, tools: tools, model: model, stream: true, maxTokens: maxTokens)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var fullContent = ""
        var toolCalls: [ToolCall] = []

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.timeout
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
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var currentToolId = ""
        var currentToolName = ""
        var currentToolInput = ""

        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }

                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                switch type {
                case "content_block_start":
                    if let block = json["content_block"] as? [String: Any],
                       let blockType = block["type"] as? String {
                        if blockType == "tool_use" {
                            currentToolId = block["id"] as? String ?? ""
                            currentToolName = block["name"] as? String ?? ""
                            currentToolInput = ""
                        }
                    }

                case "content_block_delta":
                    if let delta = json["delta"] as? [String: Any],
                       let deltaType = delta["type"] as? String {
                        if deltaType == "text_delta", let text = delta["text"] as? String {
                            fullContent += text
                            await onChunk(text)
                        } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                            currentToolInput += partial
                        }
                    }

                case "content_block_stop":
                    if !currentToolName.isEmpty {
                        var arguments: [String: AnyCodable] = [:]
                        if let inputData = currentToolInput.data(using: .utf8),
                           let inputDict = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] {
                            arguments = inputDict.mapValues { AnyCodable($0) }
                        }
                        toolCalls.append(ToolCall(id: currentToolId, name: currentToolName, arguments: arguments))
                        currentToolId = ""
                        currentToolName = ""
                        currentToolInput = ""
                    }

                default:
                    break
                }
            }
        }

        return AIResponse(
            content: fullContent.isEmpty ? nil : fullContent,
            reasoningContent: nil,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            usage: nil
        )
    }

    // MARK: - Request Builder

    func buildRequestBody(messages: [Message], tools: [[String: Any]], model: String, stream: Bool, maxTokens: Int = AppConstants.maxTokens) -> [String: Any] {
        var apiMessages: [[String: Any]] = []
        var systemPromptParts: [String] = []

        for message in messages {
            // Collect system messages into a system prompt
            if message.role == .system {
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    var contentBlocks: [[String: Any]] = []
                    if !message.content.isEmpty {
                        contentBlocks.append(["type": "text", "text": message.content])
                    }
                    contentBlocks.append(contentsOf: toolResultBlocks(from: toolResults))
                    apiMessages.append([
                        "role": "user",
                        "content": contentBlocks
                    ])
                } else if !message.content.isEmpty {
                    systemPromptParts.append(message.content)
                }
                continue
            }

            let hasToolResults = message.toolResults?.isEmpty == false
            var apiMessage: [String: Any] = [
                "role": hasToolResults || message.role == .user ? "user" : "assistant"
            ]

            // Build content array
            var contentBlocks: [[String: Any]] = []

            if !message.content.isEmpty {
                contentBlocks.append(["type": "text", "text": message.content])
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for tc in toolCalls {
                    contentBlocks.append([
                        "type": "tool_use",
                        "id": tc.id,
                        "name": tc.name,
                        "input": tc.arguments.mapValues { $0.value }
                    ])
                }
            }

            if let toolResults = message.toolResults, !toolResults.isEmpty {
                contentBlocks.append(contentsOf: toolResultBlocks(from: toolResults))
            }

            if contentBlocks.isEmpty && !message.content.isEmpty {
                apiMessage["content"] = message.content
            } else if !contentBlocks.isEmpty {
                apiMessage["content"] = contentBlocks
            } else {
                continue
            }

            apiMessages.append(apiMessage)
        }

        // Convert tools to Claude format
        let claudeTools = tools.compactMap { tool -> [String: Any]? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return [
                "name": function["name"] as? String ?? "",
                "description": function["description"] as? String ?? "",
                "input_schema": function["parameters"] as? [String: Any] ?? [:]
            ]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": apiMessages,
            "stream": stream
        ]

        // Pass system prompt via Claude's dedicated "system" field
        if !systemPromptParts.isEmpty {
            body["system"] = systemPromptParts.joined(separator: "\n\n")
        }

        if !claudeTools.isEmpty {
            body["tools"] = claudeTools
        }

        return body
    }

    private func toolResultBlocks(from toolResults: [ToolResult]) -> [[String: Any]] {
        toolResults.map { tr in
            var resultBlock: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": tr.toolCallId,
                "content": tr.modelContent
            ]
            if tr.status != .success {
                resultBlock["is_error"] = true
            }
            return resultBlock
        }
    }

    // MARK: - Response Parser

    func parseResponse(_ data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        var content: String?
        var toolCalls: [ToolCall]?

        if let contentArray = json["content"] as? [[String: Any]] {
            var textParts: [String] = []
            var calls: [ToolCall] = []

            for block in contentArray {
                if let type = block["type"] as? String {
                    switch type {
                    case "text":
                        if let text = block["text"] as? String {
                            textParts.append(text)
                        }
                    case "tool_use":
                        if let id = block["id"] as? String,
                           let name = block["name"] as? String,
                           let input = block["input"] as? [String: Any] {
                            let arguments = input.mapValues { AnyCodable($0) }
                            calls.append(ToolCall(id: id, name: name, arguments: arguments))
                        }
                    default:
                        break
                    }
                }
            }

            if !textParts.isEmpty { content = textParts.joined(separator: "\n") }
            if !calls.isEmpty { toolCalls = calls }
        }

        var usage: AIResponse.Usage?
        if let usageDict = json["usage"] as? [String: Any],
           let inputTokens = usageDict["input_tokens"] as? Int,
           let outputTokens = usageDict["output_tokens"] as? Int {
            usage = AIResponse.Usage(promptTokens: inputTokens, completionTokens: outputTokens)
        }

        return AIResponse(content: content, reasoningContent: nil, toolCalls: toolCalls, usage: usage)
    }
}

// MARK: - AI Service Errors

enum AIServiceError: LocalizedError {
    case invalidResponse
    case invalidBaseURL(String)
    case apiError(statusCode: Int, message: String)
    case decodingError
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "API 返回了无效的响应格式，请检查端点地址是否正确。"
        case .invalidBaseURL(let url):
            return "API 端点地址无效: \(url)"
        case .apiError(let statusCode, let message):
            switch statusCode {
            case 401:
                return "API Key 无效或已过期 (401)。请前往设置检查 API Key。"
            case 403:
                return "API 访问被拒绝 (403)。请检查 API Key 权限或账户状态。"
            case 429:
                return "API 请求频率超限 (429)。请稍后重试，或降低请求频率。"
            case 500, 502, 503:
                return "API 服务暂时不可用 (\(statusCode))。请稍后重试。"
            default:
                // 提取简洁的错误信息, 避免输出超长的 JSON
                let shortMessage = extractShortError(message)
                return "API 错误 (\(statusCode)): \(shortMessage)"
            }
        case .decodingError:
            return "API 响应解析失败。可能是模型返回了非预期的格式，请重试。"
        case .timeout:
            return "请求超时 (120s)。请检查网络连接，或确认端点地址是否可达。"
        }
    }
    
    private func extractShortError(_ message: String) -> String {
        // 尝试从 JSON 错误中提取简洁信息
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return String(msg.prefix(200))
        }
        return String(message.prefix(200))
    }
}
