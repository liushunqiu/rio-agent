import XCTest
@testable import RioAgent

final class ClaudeServiceTests: XCTestCase {
    func testStreamingErrorDescriptionExtractsAnthropicErrorMessage() {
        let error = AIServiceError.streamingError(
            message: #"{"type":"error","error":{"type":"overloaded_error","message":"Anthropic is temporarily overloaded"}}"#
        )

        XCTAssertTrue(error.localizedDescription.contains("Anthropic is temporarily overloaded"))
        XCTAssertTrue(error.localizedDescription.contains("流式响应错误"))
    }

    func testBuildRequestBodyUsesDedicatedSystemFieldAndClaudeToolSchema() throws {
        let service = ClaudeService(apiKey: "test")
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "read_file",
                    "description": "Read a file",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string"]
                        ],
                        "required": ["path"]
                    ]
                ]
            ]
        ]

        let body = service.buildRequestBody(
            messages: [
                Message.system("You are concise."),
                Message.user("Read README.md")
            ],
            tools: tools,
            model: "claude-test",
            stream: true,
            maxTokens: 456
        )

        XCTAssertEqual(body["system"] as? String, "You are concise.")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        let claudeTools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(claudeTools.first?["name"] as? String, "read_file")
        XCTAssertNotNil(claudeTools.first?["input_schema"] as? [String: Any])
    }

    func testBuildRequestBodyPreservesSystemToolResultsAsUserToolResultBlocks() throws {
        let service = ClaudeService(apiKey: "test")
        let body = service.buildRequestBody(
            messages: [
                Message.system("Base prompt"),
                Message(
                    role: .assistant,
                    content: "",
                    toolCalls: [ToolCall(id: "call-1", name: "read_file")]
                ),
                Message(
                    role: .system,
                    content: "[Tool Execution Results with Analysis]",
                    toolResults: [
                        .success(toolCallId: "call-1", output: "README content"),
                        .cancelled(toolCallId: "call-2", reason: "用户停止任务")
                    ],
                    presentation: .internalOnly
                )
            ],
            tools: [],
            model: "claude-test",
            stream: false,
            maxTokens: 456
        )

        XCTAssertEqual(body["system"] as? String, "Base prompt")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "assistant")
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let contentBlocks = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(contentBlocks.count, 3)
        XCTAssertEqual(contentBlocks[0]["type"] as? String, "text")
        XCTAssertEqual(contentBlocks[0]["text"] as? String, "[Tool Execution Results with Analysis]")
        XCTAssertEqual(contentBlocks[1]["type"] as? String, "tool_result")
        XCTAssertEqual(contentBlocks[1]["tool_use_id"] as? String, "call-1")
        XCTAssertEqual(contentBlocks[1]["content"] as? String, "README content")
        XCTAssertNil(contentBlocks[1]["is_error"])
        XCTAssertEqual(contentBlocks[2]["tool_use_id"] as? String, "call-2")
        XCTAssertEqual(contentBlocks[2]["content"] as? String, "用户停止任务")
        XCTAssertEqual(contentBlocks[2]["is_error"] as? Bool, true)
    }

    func testBuildRequestBodyUsesUserRoleForAnyClaudeToolResultMessage() throws {
        let body = ClaudeService(apiKey: "test").buildRequestBody(
            messages: [
                Message(
                    role: .assistant,
                    content: "tool result follows",
                    toolResults: [.success(toolCallId: "call-1", output: "ok")]
                )
            ],
            tools: [],
            model: "claude-test",
            stream: false,
            maxTokens: 456
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        let contentBlocks = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(contentBlocks.last?["type"] as? String, "tool_result")
        XCTAssertEqual(contentBlocks.last?["content"] as? String, "ok")
    }

    func testParseResponseExtractsTextToolCallsAndUsage() throws {
        let json = """
        {
          "content": [
            {"type": "text", "text": "done"},
            {"type": "tool_use", "id": "tool-1", "name": "read_file", "input": {"path": "README.md"}}
          ],
          "usage": {
            "input_tokens": 11,
            "output_tokens": 7
          }
        }
        """

        let response = try ClaudeService(apiKey: "test").parseResponse(Data(json.utf8))

        XCTAssertEqual(response.content, "done")
        XCTAssertEqual(response.usage?.promptTokens, 11)
        XCTAssertEqual(response.usage?.completionTokens, 7)
        XCTAssertEqual(response.toolCalls?.first?.id, "tool-1")
        XCTAssertEqual(response.toolCalls?.first?.name, "read_file")
        XCTAssertEqual(response.toolCalls?.first?.arguments["path"]?.value as? String, "README.md")
    }
}
