import XCTest
@testable import RioAgent

final class ModelCapabilitiesTests: XCTestCase {
    
    // MARK: - Claude Model Tests
    
    func testClaudeSonnet4Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "claude-sonnet-4-20250514")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertEqual(caps.contextWindow, 200000)
        XCTAssertEqual(caps.maxOutputTokens, 8192)
    }
    
    func testClaude35SonnetCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "claude-3-5-sonnet-20241022")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertEqual(caps.contextWindow, 200000)
        XCTAssertEqual(caps.maxOutputTokens, 8192)
    }
    
    func testClaude3OpusCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "claude-3-opus-20240229")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertEqual(caps.contextWindow, 200000)
        XCTAssertEqual(caps.maxOutputTokens, 4096)
    }
    
    // MARK: - OpenAI Model Tests
    
    func testGPT4oCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "gpt-4o")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 128000)
        XCTAssertEqual(caps.maxOutputTokens, 16384)
    }
    
    func testGPT4TurboCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "gpt-4-turbo")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 128000)
    }
    
    func testO1Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "o1")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsThinking) // o1 has reasoning
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 128000)
    }
    
    func testGPT35TurboCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "gpt-3.5-turbo")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 16384)
    }
    
    // MARK: - DeepSeek Model Tests
    
    func testDeepSeekV3Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "deepseek-v3")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 65536)
    }
    
    func testDeepSeekR1Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "deepseek-r1")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsThinking) // R1 has reasoning
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 65536)
    }
    
    // MARK: - Qwen Model Tests
    
    func testQwenMaxCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "qwen-max")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 131072)
    }
    
    func testQwenOtherCapabilities() {
        let caps = ModelCapabilities.capabilities(for: "qwen-turbo")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 32768)
    }
    
    // MARK: - Gemini Model Tests
    
    func testGemini2Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "gemini-2.0-flash")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 1_048_576)
    }
    
    func testGemini15Capabilities() {
        let caps = ModelCapabilities.capabilities(for: "gemini-1.5-pro")
        
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertTrue(caps.supportsVision)
        XCTAssertTrue(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 1_048_576)
    }
    
    // MARK: - Default Fallback Tests
    
    func testUnknownModelDefaults() {
        let caps = ModelCapabilities.capabilities(for: "unknown-model-xyz")
        
        // Should have conservative defaults
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsThinking)
        XCTAssertFalse(caps.supportsVision)
        XCTAssertFalse(caps.supportsJSON)
        XCTAssertEqual(caps.contextWindow, 8192)
        XCTAssertEqual(caps.maxOutputTokens, 4096)
    }
    
    // MARK: - Feature Support Tests
    
    func testSupportsFeature() {
        let caps = ModelCapabilities.capabilities(for: "gpt-4o")
        
        XCTAssertTrue(caps.supports(feature: .toolCalling))
        XCTAssertTrue(caps.supports(feature: .streaming))
        XCTAssertTrue(caps.supports(feature: .vision))
        XCTAssertTrue(caps.supports(feature: .json))
        XCTAssertFalse(caps.supports(feature: .thinking))
    }
    
    // MARK: - Summary Tests
    
    func testCapabilitiesSummary() {
        let caps = ModelCapabilities.capabilities(for: "claude-sonnet-4-20250514")
        let summary = caps.summary
        
        XCTAssertTrue(summary.contains("工具调用"))
        XCTAssertTrue(summary.contains("流式输出"))
        XCTAssertTrue(summary.contains("深度思考"))
        XCTAssertTrue(summary.contains("图像理解"))
    }
    
    // MARK: - ModelInfo Tests
    
    func testClaudeAvailableModels() {
        let models = ModelInfo.availableModels(for: .claude)
        
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.modelId == "claude-sonnet-4-20250514" }))
        XCTAssertTrue(models.contains(where: { $0.modelId == "claude-3-5-sonnet-20241022" }))
    }
    
    func testOpenAIAvailableModels() {
        let models = ModelInfo.availableModels(for: .openAI)
        
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.modelId == "gpt-4o" }))
        XCTAssertTrue(models.contains(where: { $0.modelId == "o1" }))
    }
    
    func testCompatibleAvailableModels() {
        let models = ModelInfo.availableModels(for: .openAICompatible)
        
        XCTAssertFalse(models.isEmpty)
    }
}