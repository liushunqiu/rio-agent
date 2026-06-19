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

    func testSettingsConfigurationDraftAppliesAllEditableFields() {
        let planningId = UUID()
        let executionId = UUID()
        let draft = SettingsConfigurationDraft(
            planningConfigSetId: planningId,
            executionConfigSetId: executionId,
            enableStreaming: false,
            maxContextMessages: 20,
            singleAgentSystemPrompt: "custom prompt"
        )

        let applied = draft.applied(to: AIConfiguration())

        XCTAssertEqual(applied.planningConfigSetId, planningId)
        XCTAssertEqual(applied.executionConfigSetId, executionId)
        XCTAssertFalse(applied.enableStreaming)
        XCTAssertEqual(applied.maxContextMessages, 20)
        XCTAssertEqual(applied.singleAgentSystemPrompt, "custom prompt")
    }

    func testMultiAgentSettingsDraftAppliesRouterAndOrchestratorFields() {
        let orchestratorSet = ConfigSet(
            id: UUID(),
            name: "Planner",
            provider: .openAICompatible,
            baseURL: "https://planner.example.com/v1",
            model: "claude-sonnet-4"
        )
        let workerSet = ConfigSet(
            id: UUID(),
            name: "Worker",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "deepseek-chat"
        )
        let routerSet = ConfigSet(
            id: UUID(),
            name: "Router",
            provider: .openAICompatible,
            baseURL: "https://router.example.com/v1",
            model: "qwen-router"
        )

        let worker = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: workerSet.id,
            provider: workerSet.provider,
            model: workerSet.model,
            systemPrompt: "worker prompt"
        )

        let draft = MultiAgentSettingsDraft(
            orchestratorConfigSetId: orchestratorSet.id,
            orchestratorPrompt: "custom orchestrator prompt",
            workers: [worker],
            maxParallel: 2,
            taskStrategy: .manual,
            maxRetries: 4,
            enableCritic: false,
            routerEnabled: true,
            routerConfigSetId: routerSet.id,
            routerModel: "manual-router-model",
            routerPrompt: "custom router prompt",
            enableQwenRouter: true,
            qwenBaseUrl: "http://localhost:9000",
            qwenModel: "Qwen/Qwen3.5-4B-Instruct",
            disableThinking: true,
            qwenTemperature: 0.2,
            qwenTopP: 0.65,
            qwenTopK: 32,
            qwenPresencePenalty: 0.4
        )

        let applied = draft.applied(
            to: MultiAgentConfig(),
            availableConfigSets: [orchestratorSet, workerSet, routerSet]
        )

        XCTAssertEqual(applied.orchestrator.configSetId, orchestratorSet.id)
        XCTAssertEqual(applied.orchestrator.model, orchestratorSet.model)
        XCTAssertEqual(applied.orchestrator.systemPrompt, "custom orchestrator prompt")
        XCTAssertEqual(applied.workers.first?.configSetId, workerSet.id)
        XCTAssertEqual(applied.maxParallelWorkers, 2)
        XCTAssertEqual(applied.taskSplitStrategy, .manual)
        XCTAssertEqual(applied.maxRetries, 4)
        XCTAssertFalse(applied.enableCritic)
        XCTAssertTrue(applied.router.enabled)
        XCTAssertEqual(applied.router.configSetId, routerSet.id)
        XCTAssertEqual(applied.router.model, "manual-router-model")
        XCTAssertEqual(applied.router.prompt, "custom router prompt")
        XCTAssertTrue(applied.router.enableQwenRouter)
        XCTAssertEqual(applied.router.qwenBaseUrl, "http://localhost:9000")
        XCTAssertEqual(applied.router.qwenModel, "Qwen/Qwen3.5-4B-Instruct")
        XCTAssertTrue(applied.router.disableThinking)
        XCTAssertEqual(applied.router.temperature, 0.2, accuracy: 0.0001)
        XCTAssertEqual(applied.router.topP, 0.65, accuracy: 0.0001)
        XCTAssertEqual(applied.router.topK, 32)
        XCTAssertEqual(applied.router.presencePenalty, 0.4, accuracy: 0.0001)
    }

    func testQwenRouterReadinessValidatesBaseUrlAndModelBeforeRuntime() {
        XCTAssertEqual(
            RouterConfig.qwenReadinessIssue(baseUrl: "   ", model: "Qwen/Qwen3.5-4B"),
            "缺少 vLLM 服务地址"
        )
        XCTAssertEqual(
            RouterConfig.qwenReadinessIssue(baseUrl: "localhost:8000", model: "Qwen/Qwen3.5-4B"),
            "vLLM 服务地址必须是 http/https URL"
        )
        XCTAssertEqual(
            RouterConfig.qwenReadinessIssue(baseUrl: "http://localhost:8000", model: "   "),
            "缺少 Qwen 模型名称"
        )

        var router = RouterConfig()
        router.qwenBaseUrl = " http://localhost:8000/ "
        router.qwenModel = " Qwen/Qwen3.5-4B "

        XCTAssertNil(router.qwenReadinessIssue)
        XCTAssertEqual(router.qwenChatCompletionsURL?.absoluteString, "http://localhost:8000/v1/chat/completions")
    }

    func testMultiAgentDraftRefreshesBoundWorkersWhenConfigSetContentChanges() {
        let workerSet = ConfigSet(
            id: UUID(),
            name: "Worker",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "old-model"
        )
        let editedWorkerSet = ConfigSet(
            id: workerSet.id,
            name: "Worker",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "new-model"
        )
        let worker = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: workerSet.id,
            provider: workerSet.provider,
            model: workerSet.model,
            systemPrompt: "worker prompt"
        )
        let draft = MultiAgentSettingsDraft(
            orchestratorConfigSetId: editedWorkerSet.id,
            orchestratorPrompt: "orchestrator prompt",
            workers: [worker],
            maxParallel: 1,
            taskStrategy: .automatic,
            maxRetries: 2,
            enableCritic: true,
            routerEnabled: false,
            routerConfigSetId: nil,
            routerModel: "",
            routerPrompt: RouterConfig.defaultPrompt,
            enableQwenRouter: false,
            qwenBaseUrl: "http://localhost:8000",
            qwenModel: "Qwen/Qwen3.5-4B",
            disableThinking: true,
            qwenTemperature: 0.7,
            qwenTopP: 0.8,
            qwenTopK: 20,
            qwenPresencePenalty: 1.5
        )

        let applied = draft.applied(
            to: MultiAgentConfig(workers: [worker]),
            availableConfigSets: [editedWorkerSet]
        )

        XCTAssertEqual(applied.workers.first?.configSetId, editedWorkerSet.id)
        XCTAssertEqual(applied.workers.first?.model, "new-model")
    }

    func testMultiAgentDraftIgnoresIncompleteConfigSetsWhenApplyingBindings() {
        let brokenSet = ConfigSet(
            id: UUID(),
            name: "Broken",
            provider: .openAICompatible,
            baseURL: "",
            model: "broken-model"
        )
        let readySet = ConfigSet(
            id: UUID(),
            name: "Ready",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "ready-model"
        )
        let worker = AgentConfig(
            name: "代码 Agent",
            role: .worker,
            capability: .code,
            configSetId: brokenSet.id,
            provider: brokenSet.provider,
            model: brokenSet.model,
            systemPrompt: "worker prompt"
        )
        let draft = MultiAgentSettingsDraft(
            orchestratorConfigSetId: brokenSet.id,
            orchestratorPrompt: "orchestrator prompt",
            workers: [worker],
            maxParallel: 1,
            taskStrategy: .automatic,
            maxRetries: 2,
            enableCritic: true,
            routerEnabled: true,
            routerConfigSetId: brokenSet.id,
            routerModel: "broken-model",
            routerPrompt: RouterConfig.defaultPrompt,
            enableQwenRouter: false,
            qwenBaseUrl: "http://localhost:8000",
            qwenModel: "Qwen/Qwen3.5-4B",
            disableThinking: true,
            qwenTemperature: 0.7,
            qwenTopP: 0.8,
            qwenTopK: 20,
            qwenPresencePenalty: 1.5
        )

        let applied = draft.applied(
            to: MultiAgentConfig(workers: [worker]),
            availableConfigSets: [brokenSet, readySet]
        )

        XCTAssertEqual(applied.orchestrator.configSetId, readySet.id)
        XCTAssertEqual(applied.orchestrator.model, "ready-model")
        XCTAssertEqual(applied.workers.first?.configSetId, readySet.id)
        XCTAssertEqual(applied.workers.first?.model, "ready-model")
        XCTAssertEqual(applied.router.configSetId, readySet.id)
    }

    func testAIConfigInfoAvailableProvidersRequireReadyConfigSets() {
        let incompleteCompatible = ConfigSet(
            id: UUID(),
            name: "Incomplete Compatible",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "   "
        )
        let info = AIConfigInfo(
            hasClaudeKey: false,
            hasOpenAIKey: false,
            hasCompatibleEndpoint: true,
            claudeApiKey: "",
            openAIApiKey: "",
            compatibleApiKey: "",
            currentClaudeModel: "",
            currentOpenAIModel: "",
            currentCompatibleModel: incompleteCompatible.model,
            allConfigSets: [incompleteCompatible],
            configSetRevision: 1
        )

        XCTAssertEqual(info.availableProviders, [])
        XCTAssertFalse(info.hasAnyProvider)
    }

    func testAIConfigInfoAvailableProvidersIncludeConfiguredSets() {
        let readyCompatible = ConfigSet(
            id: UUID(),
            name: "Ready Compatible",
            provider: .openAICompatible,
            baseURL: "https://example.com/v1",
            model: "ready-model"
        )
        let info = AIConfigInfo(
            hasClaudeKey: false,
            hasOpenAIKey: false,
            hasCompatibleEndpoint: false,
            claudeApiKey: "",
            openAIApiKey: "",
            compatibleApiKey: "",
            currentClaudeModel: "",
            currentOpenAIModel: "",
            currentCompatibleModel: readyCompatible.model,
            allConfigSets: [readyCompatible],
            configSetRevision: 1
        )

        XCTAssertEqual(info.availableProviders, [.openAICompatible])
        XCTAssertTrue(info.hasAnyProvider)
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
