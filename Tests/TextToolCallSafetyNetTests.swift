import XCTest
@testable import RioAgent

final class TextToolCallSafetyNetTests: XCTestCase {

    // MARK: - Natural language patterns (the case from the screenshot)

    func testDetectsChineseUseToolPattern() {
        // This is the exact kind of text the model produced in the screenshot
        let content = "我来帮你分析如何入手火车票业务代码。首先查看当前目录结构，了解项目整体情况。使用 list_directory 工具。"
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content),
                       "Should detect '使用 list_directory 工具' pattern")
    }

    func testDetectsChineseCallToolPattern() {
        let content = "让我先调用 read_file 来查看配置文件的内容。"
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content),
                       "Should detect '调用 read_file' pattern")
    }

    func testDetectsEnglishUseToolPattern() {
        let content = "Let me use the list_directory tool to explore the project structure."
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content),
                       "Should detect 'use the list_directory tool' pattern")
    }

    func testDetectsEnglishCallToolPattern() {
        let content = "First, I'll call read_file to inspect the configuration."
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content),
                       "Should detect 'call read_file' pattern")
    }

    // MARK: - Structured text patterns

    func testDetectsXMLStyleToolCall() {
        let content = "Let me check the directory.\n<functioncall name=\"list_directory\" args=\"{}\">"
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content))
    }

    func testDetectsJsonToolLabel() {
        let content = #"{"name": "list_directory", "arguments": {}}"#
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content))
    }

    // MARK: - Negative cases (should NOT trigger)

    func testDoesNotTriggerOnNormalAnswer() {
        let content = "根据我对代码的分析，这个项目采用了 MVC 架构。建议你从 Models 目录开始了解数据结构。"
        XCTAssertFalse(AgentEngine.containsTextBasedToolCalls(content),
                        "Normal answer without tool intent should not trigger")
    }

    func testDoesNotTriggerOnLongAnswerMentioningTools() {
        // A long answer that casually mentions a tool name but is clearly not a tool call attempt
        let longAnswer = String(repeating: "这是一段很长的回答，包含了很多关于项目的分析内容。", count: 30)
            + "在之前的对话中我们用过 read_file 来查看文件。接下来可以继续分析。"
        XCTAssertFalse(AgentEngine.containsTextBasedToolCalls(longAnswer),
                        "Long answer merely referencing a tool should not trigger")
    }

    func testDetectsStandaloneToolNameBlockInsideLongAnswer() {
        let content = """
        我现在要接手别人写的火车票业务，我要怎么入手？你有什么建议

        LIST_DIRECTORY
        /Users/liushunqiu/Desktop/ota
        """
        XCTAssertTrue(AgentEngine.containsTextBasedToolCalls(content))
    }

    @MainActor
    func testRedirectHidesRepeatedTextToolCallAssistantDrafts() {
        let engine = makeIsolatedAgentEngine(testCase: self)
        let content = "我先使用 list_directory 工具查看目录结构。"

        engine.appendMessage(.assistant(content))

        XCTAssertTrue(engine.handleTextToolCallRedirect(content))
        XCTAssertTrue(engine.handleTextToolCallRedirect(content))

        let matchingAssistantMessages = engine.messages.filter {
            $0.role == .assistant && $0.content == content
        }
        let visibleAssistantMessages = matchingAssistantMessages.filter(\.isVisibleInTranscript)

        XCTAssertEqual(matchingAssistantMessages.count, 1)
        XCTAssertTrue(visibleAssistantMessages.isEmpty)
        XCTAssertEqual(
            engine.messages.filter { $0.content.contains("[System Correction]") }.count,
            2
        )
    }
}
