import XCTest
@testable import RioAgent

final class ConfigSetTests: XCTestCase {
    override func tearDown() {
        ConfigSetManager.shared.configSets.removeAll()
        super.tearDown()
    }

    func testCompatibleEndpointWithoutAPIKeyIsTreatedAsConfigured() {
        let configSet = ConfigSet(
            name: "Local Gateway",
            provider: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            model: "custom-model"
        )

        XCTAssertTrue(configSet.isConfigured)
        XCTAssertNil(configSet.readinessIssue)
    }

    func testCompatibleEndpointWithoutModelIsNotConfigured() {
        let configSet = ConfigSet(
            name: "Local Gateway",
            provider: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            model: "   "
        )

        XCTAssertFalse(configSet.isConfigured)
        XCTAssertEqual(configSet.readinessIssue, "缺少模型标识")
    }

    func testCompatibleEndpointWithBlankBaseURLIsNotConfigured() {
        let configSet = ConfigSet(
            name: "Broken Gateway",
            provider: .openAICompatible,
            baseURL: "   ",
            model: "custom-model"
        )

        XCTAssertFalse(configSet.isConfigured)
        XCTAssertEqual(configSet.readinessIssue, "缺少 API 端点")
    }

    func testHostedProviderWithoutAPIKeyIsNotConfigured() {
        let configSet = ConfigSet(
            name: "Claude",
            provider: .claude,
            baseURL: "https://api.anthropic.com",
            model: "claude-sonnet-4-20250514"
        )

        XCTAssertFalse(configSet.isConfigured)
        XCTAssertEqual(configSet.readinessIssue, "缺少 API Key")
    }

    func testHostedProviderWithBlankBaseURLUsesOfficialDefaultEndpoint() {
        XCTAssertEqual(
            AIProvider.claude.resolvedBaseURL("   "),
            "https://api.anthropic.com"
        )
        XCTAssertEqual(
            AIProvider.openAI.resolvedBaseURL("   "),
            "https://api.openai.com"
        )
        XCTAssertEqual(
            AIProvider.openAICompatible.resolvedBaseURL("   "),
            ""
        )
        XCTAssertEqual(
            AIProvider.openAI.resolvedBaseURL(" https://gateway.example.com/v1 "),
            "https://gateway.example.com/v1"
        )
    }

    func testHostedProviderConfigCanBeReadyWithoutCustomBaseURL() {
        let configSet = ConfigSet(
            id: UUID(),
            name: "Claude",
            provider: .claude,
            baseURL: "   ",
            model: "claude-sonnet-4-20250514"
        )
        defer { configSet.saveAPIKey("") }
        configSet.saveAPIKey("secret")

        XCTAssertTrue(configSet.isConfigured)
        XCTAssertNil(configSet.readinessIssue)
    }

    func testAIServiceFactoryUsesProviderResolvedBaseURL() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Services/AIService.swift"))

        XCTAssertTrue(
            source.contains("let resolvedBaseURL = provider.resolvedBaseURL(baseURL)"),
            "AIServiceFactory should resolve blank hosted-provider endpoints before constructing concrete services."
        )
        XCTAssertTrue(
            source.contains("ClaudeService(apiKey: apiKey, baseURL: resolvedBaseURL)")
                && source.contains("OpenAIService(apiKey: apiKey, baseURL: resolvedBaseURL)"),
            "All concrete AI services should receive the normalized endpoint from the factory."
        )
    }

    func testDeleteConfigSetRemovesStoredAPIKey() throws {
        let configSet = ConfigSet(
            id: UUID(),
            name: "Temp",
            provider: .openAI,
            baseURL: "https://api.openai.com",
            model: "gpt-4o"
        )
        let manager = ConfigSetManager.shared
        manager.configSets = [configSet]
        configSet.saveAPIKey("secret")

        XCTAssertEqual(configSet.loadAPIKey(), "secret")

        manager.deleteConfigSet(id: configSet.id)

        XCTAssertNil(KeychainManager.load(forKey: "config_set_\(configSet.id.uuidString)_api_key"))
        XCTAssertTrue(manager.configSets.isEmpty)
    }

    func testRevisionChangesWhenExistingConfigSetIsUpdated() {
        let manager = ConfigSetManager.shared
        let configSet = ConfigSet(
            id: UUID(),
            name: "Gateway",
            provider: .openAICompatible,
            baseURL: "https://one.example.com/v1",
            model: "old-model"
        )
        manager.configSets = [configSet]
        let revisionAfterAdd = manager.revision

        var updated = configSet
        updated.model = "new-model"
        manager.updateConfigSet(updated)

        XCTAssertGreaterThan(manager.revision, revisionAfterAdd)
        XCTAssertEqual(manager.configSet(for: configSet.id)?.model, "new-model")
    }
}
