import XCTest
@testable import RioAgent

// MARK: - Token Estimation Tests
// 测试 Token 估算的准确性
// 注意：这是示例测试代码，需要根据项目实际情况调整
// 部分测试需要项目中的 Message 类型，可以根据需要启用或删除

class TokenEstimationTests: XCTestCase {

    var tracker: TokenTracker!

    override func setUp() {
        super.setUp()
        tracker = TokenTracker()
    }

    // MARK: - Pure Text Tests

    func testEnglishTextEstimation() {
        let text = "The quick brown fox jumps over the lazy dog. This is a test of token estimation."
        let estimated = tracker.estimateTokens(text, contentType: .pureText)

        // Expected: ~20 tokens (based on GPT tokenizer)
        // With coefficient 4.2: 82 chars / 4.2 ≈ 19.5 + 1 = 20
        XCTAssertEqual(estimated, 20, accuracy: 2, "English text estimation should be within ±2 tokens")
    }

    func testCJKTextEstimation() {
        let text = "这是一个中文测试句子，用于验证中日韩字符的 Token 估算准确性。"
        let estimated = tracker.estimateTokens(text, contentType: .cjk)

        // Expected: ~18 tokens
        // CJK: 28 chars / 1.8 ≈ 15.5, ASCII: 6 chars / 4.0 ≈ 1.5, total ≈ 17 + 1 = 18
        XCTAssertEqual(estimated, 18, accuracy: 3, "CJK text estimation should be within ±3 tokens")
    }

    func testMixedLanguageEstimation() {
        let text = "Hello 世界！This is a mixed language test with English and 中文。"
        let estimated = tracker.estimateTokens(text, contentType: .mixed)

        // Expected: ~18 tokens
        XCTAssertEqual(estimated, 18, accuracy: 3, "Mixed language estimation should be within ±3 tokens")
    }

    // MARK: - Code Tests

    func testSwiftCodeEstimation() {
        let code = """
        func calculateSum(_ numbers: [Int]) -> Int {
            return numbers.reduce(0, +)
        }
        """
        let estimated = tracker.estimateTokens(code, contentType: .code)

        // Expected: ~27 tokens (code has more symbols and keywords)
        // 80 chars / 3.0 ≈ 26.6 + 1 = 27
        XCTAssertEqual(estimated, 27, accuracy: 4, "Swift code estimation should be within ±4 tokens")
    }

    func testJSONEstimation() {
        let json = """
        {
            "name": "John Doe",
            "age": 30,
            "email": "john@example.com"
        }
        """
        let estimated = tracker.estimateTokens(json, contentType: .json)

        // Expected: ~31 tokens (JSON has lots of structure tokens)
        // 85 chars / 2.8 ≈ 30.3 + 1 = 31
        XCTAssertEqual(estimated, 31, accuracy: 5, "JSON estimation should be within ±5 tokens")
    }

    // MARK: - Content Type Detection Tests

    func testDetectJSONContent() {
        let json = "{\"key\": \"value\"}"
        let type = tracker.detectContentType(json)
        XCTAssertEqual(type, .json, "Should detect JSON content")
    }

    func testDetectCodeContent() {
        let code = "func test() { let x = 10; var y = 20; return x + y }"
        let type = tracker.detectContentType(code)
        XCTAssertEqual(type, .code, "Should detect code content")
    }

    func testDetectCJKContent() {
        let text = "这是一段纯中文文本，没有任何英文字符在里面。"
        let type = tracker.detectContentType(text)
        XCTAssertEqual(type, .cjk, "Should detect CJK content")
    }

    // MARK: - Edge Cases

    func testEmptyStringEstimation() {
        let estimated = tracker.estimateTokens("", contentType: .pureText)
        XCTAssertEqual(estimated, 0, "Empty string should be 0 tokens")
    }

    func testVeryLongTextEstimation() {
        let longText = String(repeating: "test ", count: 1000)
        let estimated = tracker.estimateTokens(longText, contentType: .pureText)

        // 5000 chars / 4.2 ≈ 1190
        XCTAssertGreaterThan(estimated, 1000, "Long text should have many tokens")
        XCTAssertLessThan(estimated, 1500, "Estimation should be in reasonable range")
    }

    // MARK: - Usage Tracking Tests

    func testUsageTracking() {
        tracker.trackUsage(promptTokens: 100, completionTokens: 50)
        XCTAssertEqual(tracker.accumulatedUsage.promptTokens, 100)
        XCTAssertEqual(tracker.accumulatedUsage.completionTokens, 50)
        XCTAssertGreaterThan(tracker.sessionCost, 0)
    }

    func testMultipleUsageTracking() {
        tracker.trackUsage(promptTokens: 100, completionTokens: 50)
        tracker.trackUsage(promptTokens: 200, completionTokens: 100)
        XCTAssertEqual(tracker.accumulatedUsage.promptTokens, 300)
        XCTAssertEqual(tracker.accumulatedUsage.completionTokens, 150)
    }

    func testReset() {
        tracker.trackUsage(promptTokens: 100, completionTokens: 50)
        tracker.reset()
        XCTAssertEqual(tracker.accumulatedUsage.promptTokens, 0)
        XCTAssertEqual(tracker.accumulatedUsage.completionTokens, 0)
        XCTAssertEqual(tracker.sessionCost, 0.0)
    }

    func testSessionSummary() {
        tracker.trackUsage(promptTokens: 1000, completionTokens: 500)
        let summary = tracker.getSessionSummary()
        XCTAssertTrue(summary.contains("1000 in"))
        XCTAssertTrue(summary.contains("500 out"))
        XCTAssertTrue(summary.contains("$"))
    }

    // MARK: - Performance Tests

    func testEstimationPerformance() {
        let text = String(repeating: "Performance test text. ", count: 100)

        measure {
            for _ in 0..<100 {
                _ = tracker.estimateTokens(text, contentType: .mixed)
            }
        }
        // Should complete 100 estimations quickly
    }
}

// MARK: - XCTAssert Extensions for Accuracy

extension XCTestCase {
    func XCTAssertEqual(_ expression1: Int, _ expression2: Int, accuracy: Int, _ message: String) {
        let diff = abs(expression1 - expression2)
        XCTAssertLessThanOrEqual(diff, accuracy, message)
    }
}
