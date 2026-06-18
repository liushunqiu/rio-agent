import XCTest
@testable import RioAgent

final class MarkdownRendererTests: XCTestCase {
    func testParserKeepsTripleBackticksInsideLongerFenceCodeBlock() {
        let markdown = """
        before
        ````
        alpha
        ```swift
        print("hello")
        ```
        omega
        ````
        after
        """

        let segments = MarkdownParser.parse(markdown)

        XCTAssertEqual(segments.count, 3)
        guard case .codeBlock(_, let language, let code) = segments[1] else {
            return XCTFail("Expected the middle segment to be a code block.")
        }

        XCTAssertEqual(language, "")
        XCTAssertTrue(code.contains("```swift"))
        XCTAssertTrue(code.contains("print(\"hello\")"))
        XCTAssertTrue(code.contains("omega"))
    }

    func testParserStillHandlesStandardTripleBacktickFence() {
        let markdown = """
        ```swift
        let value = 1
        ```
        """

        let segments = MarkdownParser.parse(markdown)

        XCTAssertEqual(segments.count, 1)
        guard case .codeBlock(_, let language, let code) = segments[0] else {
            return XCTFail("Expected a code block.")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let value = 1")
    }

    func testParserRequiresClosingFenceOnItsOwnLine() {
        let markdown = """
        ```swift
        let text = "inline ``` marker should stay inside code"
        print(text)
        ```
        after
        """

        let segments = MarkdownParser.parse(markdown)

        XCTAssertEqual(segments.count, 2)
        guard case .codeBlock(_, let language, let code) = segments[0] else {
            return XCTFail("Expected the first segment to be a code block.")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("inline ``` marker"))
        XCTAssertTrue(code.contains("print(text)"))
    }

    func testParserAllowsWhitespaceAroundClosingFenceLine() {
        let markdown = """
        ```json
        {"ok": true}
          ```  
        """

        let segments = MarkdownParser.parse(markdown)

        XCTAssertEqual(segments.count, 1)
        guard case .codeBlock(_, let language, let code) = segments[0] else {
            return XCTFail("Expected a code block.")
        }

        XCTAssertEqual(language, "json")
        XCTAssertEqual(code, "{\"ok\": true}")
    }
}
