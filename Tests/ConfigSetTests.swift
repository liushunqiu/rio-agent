import XCTest
@testable import RioAgent

final class ConfigSetTests: XCTestCase {
    func testCompatibleEndpointWithoutAPIKeyIsTreatedAsConfigured() {
        let configSet = ConfigSet(
            name: "Local Gateway",
            provider: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            model: "custom-model"
        )

        XCTAssertTrue(configSet.isConfigured)
    }

    func testCompatibleEndpointWithBlankBaseURLIsNotConfigured() {
        let configSet = ConfigSet(
            name: "Broken Gateway",
            provider: .openAICompatible,
            baseURL: "   ",
            model: "custom-model"
        )

        XCTAssertFalse(configSet.isConfigured)
    }

    func testHostedProviderWithoutAPIKeyIsNotConfigured() {
        let configSet = ConfigSet(
            name: "Claude",
            provider: .claude,
            baseURL: "https://api.anthropic.com",
            model: "claude-sonnet-4-20250514"
        )

        XCTAssertFalse(configSet.isConfigured)
    }
}
