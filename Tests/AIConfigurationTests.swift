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
    }
}
