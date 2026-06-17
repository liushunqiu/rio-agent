import XCTest
@testable import RioAgent

final class MultiAgentConfigPromptMigrationTests: XCTestCase {
    func testMigrateBuiltInPromptsReplacesLegacyDefaultsOnly() {
        var config = MultiAgentConfig(
            orchestrator: AgentConfig(
                name: "主 Agent",
                role: .orchestrator,
                capability: .general,
                provider: .claude,
                model: "test-model",
                systemPrompt: MultiAgentConfig.legacyDefaultOrchestratorPrompt
            ),
            workers: [
                AgentConfig(
                    name: "搜索 Agent",
                    role: .worker,
                    capability: .search,
                    provider: .claude,
                    model: "test-model",
                    systemPrompt: MultiAgentConfig.legacyDefaultSearchPrompt
                ),
                AgentConfig(
                    name: "代码 Agent",
                    role: .worker,
                    capability: .code,
                    provider: .claude,
                    model: "test-model",
                    systemPrompt: "custom code prompt"
                )
            ]
        )

        config.migrateBuiltInPromptsIfNeeded()

        XCTAssertEqual(config.orchestrator.systemPrompt, MultiAgentConfig.defaultOrchestratorPrompt)
        XCTAssertEqual(config.workers[0].systemPrompt, MultiAgentConfig.defaultSearchPrompt)
        XCTAssertEqual(config.workers[1].systemPrompt, "custom code prompt")
    }
}
