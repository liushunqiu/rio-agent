import XCTest
@testable import RioAgent

final class OpenAIServiceTests: XCTestCase {
    func testBuildRequestBodyIncludesToolResultsBeforeAssistantContent() throws {
        let service = OpenAIService(apiKey: "test")
        let message = Message(
            role: .assistant,
            content: "I ran the tool",
            toolResults: [
                ToolResult.success(toolCallId: "call-1", output: "ok")
            ]
        )

        let body = service.buildRequestBody(
            messages: [message],
            tools: [],
            model: "gpt-test",
            stream: false,
            maxTokens: 123
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "tool")
        XCTAssertEqual(messages[0]["tool_call_id"] as? String, "call-1")
        XCTAssertEqual(messages[0]["content"] as? String, "ok")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[1]["content"] as? String, "I ran the tool")
    }

    func testBuildRequestBodySendsCancellationReasonAsToolContent() throws {
        let service = OpenAIService(apiKey: "test")
        let message = Message(
            role: .system,
            content: "",
            toolResults: [
                .cancelled(toolCallId: "call-1", reason: "用户停止任务")
            ],
            presentation: .internalOnly
        )

        let body = service.buildRequestBody(
            messages: [message],
            tools: [],
            model: "gpt-test",
            stream: false,
            maxTokens: 123
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "tool")
        XCTAssertEqual(messages[0]["tool_call_id"] as? String, "call-1")
        XCTAssertEqual(messages[0]["content"] as? String, "用户停止任务")
    }

    func testParseResponseExtractsUsageReasoningAndToolCalls() throws {
        let json = """
        {
          "choices": [
            {
              "message": {
                "content": "done",
                "reasoning_content": "thought",
                "tool_calls": [
                  {
                    "id": "call-1",
                    "function": {
                      "name": "read_file",
                      "arguments": "{\\"path\\":\\"README.md\\"}"
                    }
                  }
                ]
              }
            }
          ],
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5
          }
        }
        """

        let response = try OpenAIService(apiKey: "test").parseResponse(Data(json.utf8))

        XCTAssertEqual(response.content, "done")
        XCTAssertEqual(response.reasoningContent, "thought")
        XCTAssertEqual(response.usage?.promptTokens, 10)
        XCTAssertEqual(response.usage?.completionTokens, 5)
        XCTAssertEqual(response.toolCalls?.first?.name, "read_file")
        XCTAssertEqual(response.toolCalls?.first?.arguments["path"]?.value as? String, "README.md")
    }

    func testStreamingStateAccumulatesChunkedToolCallArguments() throws {
        var state = OpenAIStreamingState()

        _ = state.consumeSSEDataLine("""
        {"choices":[{"delta":{"content":"hel","reasoning_content":"why ","tool_calls":[{"index":0,"id":"call-1","function":{"name":"read_","arguments":"{\\"path\\":"}}]}}]}
        """)
        _ = state.consumeSSEDataLine("""
        {"choices":[{"delta":{"content":"lo","reasoning_content":"now","tool_calls":[{"index":0,"function":{"name":"file","arguments":"\\"README.md\\"}"}}]}}]}
        """)

        XCTAssertEqual(state.content, "hello")
        XCTAssertEqual(state.reasoningContent, "why now")
        XCTAssertEqual(state.toolCalls?.first?.id, "call-1")
        XCTAssertEqual(state.toolCalls?.first?.name, "read_file")
        XCTAssertEqual(state.toolCalls?.first?.arguments["path"]?.value as? String, "README.md")
    }
}
