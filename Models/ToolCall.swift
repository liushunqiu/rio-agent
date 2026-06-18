import Foundation

struct ToolCall: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]

    init(id: String = UUID().uuidString, name: String, arguments: [String: AnyCodable] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

enum ToolResultStatus: String, Codable {
    case success
    case error
    case cancelled
}

struct ToolResult: Codable, Equatable {
    let toolCallId: String
    let status: ToolResultStatus
    let output: String
    let error: String?

    init(toolCallId: String, status: ToolResultStatus, output: String, error: String? = nil) {
        self.toolCallId = toolCallId
        self.status = status
        self.output = output
        self.error = error
    }

    static func success(toolCallId: String, output: String) -> ToolResult {
        ToolResult(toolCallId: toolCallId, status: .success, output: output)
    }

    static func error(toolCallId: String, error: String) -> ToolResult {
        ToolResult(toolCallId: toolCallId, status: .error, output: "", error: error)
    }

    static func cancelled(toolCallId: String, reason: String = "用户取消") -> ToolResult {
        ToolResult(toolCallId: toolCallId, status: .cancelled, output: "", error: reason)
    }
}

// MARK: - Tool Execution State

enum ToolExecutionState: Identifiable {
    case pending(toolCall: ToolCall)
    case confirming(toolCall: ToolCall)
    case executing(toolCall: ToolCall)
    case completed(toolCall: ToolCall, result: ToolResult)
    case failed(toolCall: ToolCall, error: String)

    var id: String {
        switch self {
        case .pending(let toolCall), .confirming(let toolCall),
             .executing(let toolCall), .completed(let toolCall, _),
             .failed(let toolCall, _):
            return toolCall.id
        }
    }
}
