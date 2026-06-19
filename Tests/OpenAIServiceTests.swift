import XCTest
@testable import RioAgent

final class OpenAIServiceTests: XCTestCase {
    func testFactoryPreservesOpenAICompatibleProviderIdentity() {
        let compatibleService = AIServiceFactory.createService(
            provider: .openAICompatible,
            apiKey: "",
            baseURL: "https://gateway.example.com/v1"
        )
        let openAIService = AIServiceFactory.createService(
            provider: .openAI,
            apiKey: "sk-test",
            baseURL: ""
        )

        XCTAssertEqual(compatibleService.provider, .openAICompatible)
        XCTAssertEqual(openAIService.provider, .openAI)
    }

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

        _ = try state.consumeSSEDataLine("""
        {"choices":[{"delta":{"content":"hel","reasoning_content":"why ","tool_calls":[{"index":0,"id":"call-1","function":{"name":"read_","arguments":"{\\"path\\":"}}]}}]}
        """)
        _ = try state.consumeSSEDataLine("""
        {"choices":[{"delta":{"content":"lo","reasoning_content":"now","tool_calls":[{"index":0,"function":{"name":"file","arguments":"\\"README.md\\"}"}}]}}]}
        """)

        XCTAssertEqual(state.content, "hello")
        XCTAssertEqual(state.reasoningContent, "why now")
        let toolCalls = try state.toolCalls
        XCTAssertEqual(toolCalls?.first?.id, "call-1")
        XCTAssertEqual(toolCalls?.first?.name, "read_file")
        XCTAssertEqual(toolCalls?.first?.arguments["path"]?.value as? String, "README.md")
    }

    func testStreamingStateThrowsProviderErrorEvents() {
        var state = OpenAIStreamingState()

        XCTAssertThrowsError(try state.consumeSSEDataLine("""
        {"error":{"message":"quota exceeded for this model","type":"rate_limit"}}
        """)) { error in
            XCTAssertTrue(error.localizedDescription.contains("quota exceeded for this model"))
        }
    }

    func testAPIErrorDescriptionsIncludeProviderMessageForCommonStatuses() {
        let error = AIServiceError.apiError(
            statusCode: 401,
            message: #"{"error":{"message":"Incorrect API key provided"}}"#
        )

        XCTAssertTrue(error.localizedDescription.contains("Incorrect API key provided"))
        XCTAssertTrue(error.localizedDescription.contains("请前往设置检查 API Key"))
    }

    func testParseResponseThrowsWhenToolCallArgumentsAreInvalid() {
        let json = """
        {
          "choices": [
            {
              "message": {
                "content": null,
                "tool_calls": [
                  {
                    "id": "call-1",
                    "function": {
                      "name": "read_file",
                      "arguments": "{bad json"
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        XCTAssertThrowsError(try OpenAIService(apiKey: "test").parseResponse(Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("无法解析的工具参数"))
            XCTAssertTrue(error.localizedDescription.contains("read_file"))
        }
    }

    func testStreamingStateThrowsWhenToolCallArgumentsAreInvalid() throws {
        var state = OpenAIStreamingState()

        _ = try state.consumeSSEDataLine("""
        {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"read_file","arguments":"{bad json"}}]}}]}
        """)

        XCTAssertThrowsError(try state.toolCalls) { error in
            XCTAssertTrue(error.localizedDescription.contains("无法解析的工具参数"))
            XCTAssertTrue(error.localizedDescription.contains("read_file"))
        }
    }
}
