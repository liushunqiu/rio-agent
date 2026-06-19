import XCTest

final class MultiAgentSettingsSourceTests: XCTestCase {
    func testMultiAgentConfigSelectorsExposeAndDisableIncompleteConfigSets() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("configSets.filter(\\.isConfigured)") || source.contains("aiConfig.allConfigSets.filter(\\.isConfigured)"),
            "Multi-Agent settings should prefer ready model configs when reconciling selections."
        )
        XCTAssertTrue(
            source.contains(".disabled(!configSet.isConfigured)"),
            "Agent config set selector should not allow binding incomplete model configs."
        )
        XCTAssertTrue(
            source.contains(".disabled(enableQwenRouter || !cs.isConfigured)"),
            "Router config set selector should not allow binding incomplete model configs."
        )
        XCTAssertTrue(
            source.contains("selectedReadyConfigSet == nil"),
            "Worker add/edit sheets should block saving when no ready model config exists."
        )
        XCTAssertTrue(
            source.contains("暂不可选"),
            "Disabled Multi-Agent config rows should explain why they cannot be selected."
        )
    }

    func testMultiAgentSelectorsDoNotShowUnavailableStoredBindingsAsActive() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("let isSelectedReadyRouterConfig = routerConfigSetId == cs.id && cs.isConfigured"),
            "Router rows should only render the selected state for ready configs."
        )
        XCTAssertTrue(
            source.contains("private var selectedReadyConfigSet: ConfigSet?"),
            "Agent selectors should distinguish a stored config id from a ready binding."
        )
        XCTAssertTrue(
            source.contains("if let selectedReadyConfigSet"),
            "The current binding summary should only show ready configs as active."
        )
        XCTAssertTrue(
            source.contains("原绑定已失效"),
            "Stale bindings to incomplete configs should be called out instead of shown as healthy."
        )
        XCTAssertTrue(
            source.contains("configSetId == configSet.id && configSet.isConfigured"),
            "Selector icons should not mark incomplete stored configs as selected."
        )
        XCTAssertTrue(
            source.contains("let isSelectedReadyConfigSet = configSetId == configSet.id && configSet.isConfigured"),
            "Agent selector rows should use the same ready-only selected state for row styling."
        )
        XCTAssertTrue(
            source.contains(".background(isSelectedReadyConfigSet ? Theme.bgTertiary : Theme.bgInput)"),
            "Incomplete stored config bindings should not keep the active row background."
        )
        XCTAssertTrue(
            source.contains(".stroke(isSelectedReadyConfigSet ? Theme.accentPrimary.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)"),
            "Incomplete stored config bindings should not keep the active row border."
        )
    }

    func testMultiAgentSettingsExposeTruncatedValuesAndDisabledSaveReasons() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains(".help(detail)"),
            "Metric details should expose the full text when truncated."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.name)"),
            "Config set names in agent selectors should remain inspectable when truncated."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.model)"),
            "Model identifiers in agent selectors should remain inspectable when truncated."
        )
        XCTAssertTrue(
            source.contains(".help(readinessIssue)"),
            "Readiness issues should remain inspectable when compact selector rows truncate them."
        )
        XCTAssertTrue(
            source.contains(".help(\"当前绑定: \\(selectedReadyConfigSet.provider.displayName) · \\(selectedReadyConfigSet.model)\")"),
            "The current model binding summary should expose the full provider/model value."
        )
        XCTAssertTrue(
            source.contains("private var saveDisabledReason: String?"),
            "Worker add/edit sheets should derive a concrete disabled-save reason."
        )
        XCTAssertTrue(
            source.contains("return \"请先填写子 Agent 名称\""),
            "Disabled worker save buttons should explain missing names."
        )
        XCTAssertTrue(
            source.contains("return \"请先选择一个可用的模型端点\""),
            "Disabled worker save buttons should explain missing model endpoints."
        )
        XCTAssertTrue(
            source.contains(".help(saveDisabledReason ?? \"添加子 Agent\")"),
            "The add worker button should expose why it is disabled."
        )
        XCTAssertTrue(
            source.contains(".help(saveDisabledReason ?? \"保存子 Agent\")"),
            "The edit worker button should expose why it is disabled."
        )
    }

    func testMultiAgentHeaderReflectsSelectedTaskSplitStrategy() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("value: taskStrategyMetricValue"),
            "The Multi-Agent settings header should derive its mode value from the selected task split strategy."
        )
        XCTAssertTrue(
            source.contains("detail: taskStrategyMetricDetail"),
            "The Multi-Agent settings header should explain the real task split behavior instead of using static copy."
        )
        XCTAssertTrue(
            source.contains("tone: taskStrategyMetricTone"),
            "Manual-confirmation mode should be visually distinct from automatic mode in the header."
        )
        XCTAssertTrue(
            source.contains("case .manual:\n            return \"复杂任务拆分前先暂停，等待你确认执行模式\""),
            "Manual mode should tell the user that execution will pause for confirmation."
        )
        XCTAssertFalse(
            source.contains("value: \"自动流水线\""),
            "The header should not always claim automatic mode after the user selects manual confirmation."
        )
    }

    func testPipelineSummaryReflectsRouterAndCriticSwitches() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("Text(pipelineSummaryText)"),
            "The pipeline summary should be derived from the current Router and Critic switch state."
        )
        XCTAssertTrue(
            source.contains("private var pipelineSummaryText: String"),
            "Multi-Agent settings should centralize the dynamic pipeline summary text."
        )
        XCTAssertTrue(
            source.contains("switch (routerEnabled, enableCritic)"),
            "Pipeline summary copy should follow both Router and Critic settings."
        )
        XCTAssertTrue(
            source.contains("Router 前置路由当前关闭"),
            "The summary should explicitly call out when Router is disabled."
        )
        XCTAssertTrue(
            source.contains("Critic 审查当前关闭"),
            "The summary should explicitly call out when Critic is disabled."
        )
        XCTAssertFalse(
            source.contains("四层流水线始终启用"),
            "The settings UI should not claim every pipeline layer is always enabled when Router and Critic can be switched off."
        )
    }

    func testQwenRouterSettingsExposeReadinessProblemsBeforeRuntime() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("private var qwenRouterReadinessIssue: String?"),
            "Qwen router settings should derive a local readiness issue from the editable fields."
        )
        XCTAssertTrue(
            source.contains("RouterConfig.qwenReadinessIssue(baseUrl: qwenBaseUrl, model: qwenModel)"),
            "The settings UI should reuse the same readiness rule as the runtime router config."
        )
        XCTAssertTrue(
            source.contains("InlineWarning(text: \"Qwen 专用路由暂不可用：\\(qwenRouterReadinessIssue)。\")"),
            "Invalid Qwen router settings should be visible before the user runs a task."
        )
    }

    func testMultiAgentSettingsSupportTargetedRecoveryHighlighting() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("let launchContext: SettingsLaunchContext?"),
            "Multi-Agent settings should accept the shared settings launch context."
        )
        XCTAssertTrue(
            source.contains("private var orchestratorRecoveryMessage: String?"),
            "Multi-Agent settings should derive a recovery callout for the orchestrator section."
        )
        XCTAssertTrue(
            source.contains("case .planningModel, .multiAgentOrchestratorModel:"),
            "Orchestrator recovery should support both planning-layer and dedicated Multi-Agent orchestrator failures."
        )
        XCTAssertTrue(
            source.contains("private var workersRecoveryMessage: String?"),
            "Multi-Agent settings should derive a recovery callout for worker assignment and worker model failures."
        )
        XCTAssertTrue(
            source.contains("private var routerRecoveryMessage: String?"),
            "Multi-Agent settings should derive a recovery callout for router failures."
        )
        XCTAssertTrue(
            source.contains("recoveryMessage: orchestratorRecoveryMessage"),
            "Planning-related recovery should visually highlight the orchestrator section."
        )
        XCTAssertTrue(
            source.contains("recoveryMessage: workersRecoveryMessage"),
            "Worker-related recovery should visually highlight the worker section."
        )
        XCTAssertTrue(
            source.contains("recoveryMessage: routerRecoveryMessage"),
            "Router-related recovery should visually highlight the router section."
        )
        XCTAssertTrue(
            source.contains("SettingsSection(title: \"子 Agent 池\", icon: \"person.2.fill\", recoveryMessage: recoveryMessage)"),
            "Worker section should render with the targeted recovery accent."
        )
    }

    func testWorkerDeletionRequiresExplicitConfirmation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/MultiAgentSettingsView.swift"))

        XCTAssertTrue(
            source.contains("@State private var pendingDeleteWorker: AgentConfig?"),
            "Multi-Agent settings should stage a worker before deleting it."
        )
        XCTAssertTrue(
            source.contains(".alert(\"删除子 Agent？\""),
            "Deleting a worker should show a confirmation alert."
        )
        XCTAssertTrue(
            source.contains("deleteWorkerConfirmationMessage"),
            "The delete confirmation should describe the worker deletion impact."
        )
        XCTAssertTrue(
            source.contains("pendingDeleteWorker.name"),
            "The confirmation should identify the worker being deleted."
        )
        XCTAssertTrue(
            source.contains("workers.removeAll { $0.id == pendingDeleteWorker.id }"),
            "The staged worker should be deleted only after the user confirms."
        )
        XCTAssertTrue(
            source.contains("这个操作无法撤销"),
            "The confirmation should warn that deleting the worker cannot be undone."
        )
        XCTAssertFalse(
            source.contains("onDelete: { worker in\n                        workers.removeAll"),
            "The worker section should not delete rows immediately from its onDelete callback."
        )
    }
}
