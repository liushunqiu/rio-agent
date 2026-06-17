import XCTest
@testable import RioAgent

final class AIConfigurationTests: XCTestCase {
    func testDecodingMissingModernFieldsFallsBackToDefaults() throws {
        let data = """
        {
          "planningConfigSetId": null,
          "executionConfigSetId": null
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertEqual(configuration.maxContextMessages, 999)
        XCTAssertTrue(configuration.enableStreaming)
        XCTAssertEqual(configuration.singleAgentSystemPrompt, AIConfiguration.defaultSingleAgentSystemPrompt)
    }

    func testDecodingLegacyConfigurationDoesNotFail() throws {
        let data = """
        {
          "activeProvider": "openAICompatible",
          "planningProvider": "claude",
          "executionProvider": "openAI",
          "maxContextMessages": 50
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertNil(configuration.planningConfigSetId)
        XCTAssertNil(configuration.executionConfigSetId)
        XCTAssertEqual(configuration.maxContextMessages, 50)
        XCTAssertTrue(configuration.enableStreaming)
        XCTAssertEqual(configuration.singleAgentSystemPrompt, AIConfiguration.defaultSingleAgentSystemPrompt)
    }

    func testEncodingAndDecodingPreservesSingleAgentSystemPrompt() throws {
        var configuration = AIConfiguration()
        configuration.singleAgentSystemPrompt = "custom prompt"

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertEqual(decoded.singleAgentSystemPrompt, "custom prompt")
    }

    func testDecodingLegacySingleAgentPromptMigratesToLayeredBasePrompt() throws {
        let data = """
        {
          "singleAgentSystemPrompt": \(String(reflecting: AIConfiguration.legacyDefaultSingleAgentSystemPrompt))
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertEqual(configuration.singleAgentSystemPrompt, AIConfiguration.defaultSingleAgentSystemPrompt)
    }
}
