import XCTest
@testable import RioAgent

final class ClaudeServiceTests: XCTestCase {
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
