import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
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

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String? = nil,
        thinkingDuration: TimeInterval? = nil,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        isStreaming: Bool = false
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
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        // 快速路径：同一实例直接返回 true
        guard lhs.id == rhs.id else { return false }
        // 快速路径：长度不同则内容一定不同，避免昂贵的字符串逐字符比较
        guard lhs.content.count == rhs.content.count,
              lhs.thinkingContent?.count == rhs.thinkingContent?.count,
              lhs.thinkingDuration == rhs.thinkingDuration,
              lhs.isStreaming == rhs.isStreaming else { return false }
        // 长度相同时才做完整字符串比较（流式场景下极少见）
        return lhs.content == rhs.content
            && lhs.thinkingContent == rhs.thinkingContent
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }

    static func assistant(_ content: String) -> Message {
        Message(role: .assistant, content: content)
    }

    static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }

    static func streamingAssistant() -> Message {
        Message(role: .assistant, content: "", isStreaming: true)
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

struct AnyCodable: Codable {
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
}
