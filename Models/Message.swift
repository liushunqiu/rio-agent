import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessagePresentation: String, Codable, Hashable {
    case normal
    case internalOnly
}

struct MessageSource: Codable, Hashable {
    var providerName: String?
    var modelName: String?
    var agentName: String?

    init(
        providerName: String? = nil,
        modelName: String? = nil,
        agentName: String? = nil
    ) {
        self.providerName = providerName
        self.modelName = modelName
        self.agentName = agentName
    }
}

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinkingContent: String?
    var thinkingDuration: TimeInterval?
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var toolResults: [ToolResult]?
    var isStreaming: Bool
    var source: MessageSource?
    var presentation: MessagePresentation

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinkingContent, thinkingDuration, timestamp
        case toolCalls, toolResults, isStreaming, source, presentation
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String? = nil,
        thinkingDuration: TimeInterval? = nil,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        isStreaming: Bool = false,
        source: MessageSource? = nil,
        presentation: MessagePresentation = .normal
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.thinkingDuration = thinkingDuration
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
        self.source = source
        self.presentation = presentation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        thinkingContent = try container.decodeIfPresent(String.self, forKey: .thinkingContent)
        thinkingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .thinkingDuration)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolResults = try container.decodeIfPresent([ToolResult].self, forKey: .toolResults)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        source = try container.decodeIfPresent(MessageSource.self, forKey: .source)
        presentation = try container.decodeIfPresent(MessagePresentation.self, forKey: .presentation) ?? .normal
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        // 快速路径：同一实例直接返回 true
        guard lhs.id == rhs.id else { return false }
        // 快速路径：长度不同则内容一定不同，避免昂贵的字符串逐字符比较
        guard lhs.content.count == rhs.content.count,
              lhs.thinkingContent?.count == rhs.thinkingContent?.count,
              lhs.thinkingDuration == rhs.thinkingDuration,
              lhs.role == rhs.role,
              lhs.timestamp == rhs.timestamp,
              lhs.toolCalls?.count == rhs.toolCalls?.count,
              lhs.toolResults?.count == rhs.toolResults?.count,
              lhs.isStreaming == rhs.isStreaming,
              lhs.source == rhs.source,
              lhs.presentation == rhs.presentation else { return false }
        // 长度相同时才做完整字符串比较（流式场景下极少见）
        return lhs.content == rhs.content
            && lhs.thinkingContent == rhs.thinkingContent
            && lhs.toolCalls == rhs.toolCalls
            && lhs.toolResults == rhs.toolResults
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var isVisibleInTranscript: Bool {
        presentation == .normal
    }

    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var singleLineDisplayContent: String {
        trimmedContent.replacingOccurrences(of: "\n", with: " ")
    }

    var isEligibleUserTaskInput: Bool {
        guard role == .user, isVisibleInTranscript else { return false }

        let trimmed = trimmedContent
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return false }

        return !Self.nonTaskUserReplyTokens.contains(trimmed.lowercased())
    }

    private static let nonTaskUserReplyTokens: Set<String> = [
        "是", "yes", "y", "确认", "ok", "好", "继续",
        "否", "不", "no", "n", "取消", "算了", "continue"
    ]

    static func user(
        _ content: String,
        source: MessageSource? = nil,
        presentation: MessagePresentation = .normal
    ) -> Message {
        Message(role: .user, content: content, source: source, presentation: presentation)
    }

    static func assistant(
        _ content: String,
        source: MessageSource? = nil,
        presentation: MessagePresentation = .normal
    ) -> Message {
        Message(role: .assistant, content: content, source: source, presentation: presentation)
    }

    static func system(
        _ content: String,
        source: MessageSource? = nil,
        presentation: MessagePresentation = .normal
    ) -> Message {
        Message(role: .system, content: content, source: source, presentation: presentation)
    }

    static func streamingAssistant(
        source: MessageSource? = nil,
        presentation: MessagePresentation = .normal
    ) -> Message {
        Message(role: .assistant, content: "", isStreaming: true, source: source, presentation: presentation)
    }
}

// MARK: - API Request/Response Models

struct APIRequest: Codable {
    let model: String
    let messages: [APIMessage]
    let maxTokens: Int
    let tools: [APITool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case maxTokens = "max_tokens"
    }
}

struct APIMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [APIToolCall]?
    let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

struct APITool: Codable {
    let type: String
    let function: APIFunction
}

struct APIFunction: Codable {
    let name: String
    let description: String
    let parameters: [String: AnyCodable]
}

struct APIToolCall: Codable {
    let id: String
    let type: String
    let function: APIToolCallFunction
}

struct APIToolCallFunction: Codable {
    let name: String
    let arguments: String
}

struct APIResponse: Codable {
    let id: String
    let choices: [APIChoice]
}

struct APIChoice: Codable {
    let message: APIResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct APIResponseMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [APIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case let (lhs as Int, rhs as Int):
            lhs == rhs
        case let (lhs as Double, rhs as Double):
            lhs == rhs
        case let (lhs as String, rhs as String):
            lhs == rhs
        case let (lhs as Bool, rhs as Bool):
            lhs == rhs
        default:
            false
        }
    }
}
