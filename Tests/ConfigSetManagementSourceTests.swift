import XCTest

final class ConfigSetManagementSourceTests: XCTestCase {
    func testConfigSetManagerCanUseInjectedStorage() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/ConfigSet.swift"))
        let testSource = try String(contentsOf: repoRoot.appendingPathComponent("Tests/ConfigSetTests.swift"))

        XCTAssertTrue(
            managerSource.contains("private let userDefaults: UserDefaults")
                && managerSource.contains("private let saveKey: String"),
            "ConfigSetManager should keep its persistence backend injectable."
        )
        XCTAssertTrue(
            managerSource.contains("init(\n        userDefaults: UserDefaults = .standard,\n        storageKey: String = ConfigSetManager.storageKey\n    )"),
            "The app should keep the existing shared defaults while tests can provide isolated storage."
        )
        XCTAssertTrue(
            managerSource.contains("userDefaults.set(data, forKey: saveKey)")
                && managerSource.contains("if let data = userDefaults.data(forKey: saveKey),"),
            "ConfigSetManager should consistently read and write through the injected UserDefaults store."
        )
        XCTAssertTrue(
            testSource.contains("private func makeIsolatedManager() -> ConfigSetManager")
                && testSource.contains("ConfigSetManager(\n            userDefaults: defaults,"),
            "ConfigSet tests should not mutate the real shared model configuration storage."
        )
    }

    func testConfigEditorSaveGuidanceIsSpecificAndDiscoverable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains(".help(canSave ? \"保存模型配置\" : readinessMessage)"),
            "A disabled save button should expose the same readiness reason as the visible status row."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"模型名称\")"),
            "The editor should report a missing model config name explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"API Key\")"),
            "Hosted provider configs should report a missing API Key explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"API 端点\")"),
            "OpenAI-compatible configs should report a missing API endpoint explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"模型标识\")"),
            "All config types should report a missing model identifier explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.joined(separator: \"、\")"),
            "Readiness guidance should list only the fields that are currently missing."
        )
    }

    func testConfigRowsTruncateLongNamesBeforeActionControls() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("Text(configSet.name)\n                    .font(.system(size: 13, weight: .semibold))\n                    .foregroundColor(Theme.textPrimary)\n                    .lineLimit(1)\n                    .truncationMode(.middle)"),
            "Long config names should not push status text or edit/delete controls out of the row."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.name)"),
            "Truncated config names should still expose the full name on hover."
        )
        XCTAssertTrue(
            source.contains("Text(configSet.model)\n                            .font(.system(size: 10, design: .monospaced))\n                            .foregroundColor(Theme.textSecondary)\n                            .lineLimit(1)\n                            .truncationMode(.middle)"),
            "Long model identifiers should not stretch config rows."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.model)"),
            "Truncated model identifiers should remain inspectable."
        )
        XCTAssertTrue(
            source.contains(".help(readinessHint)"),
            "Readiness issues should remain discoverable when the row is compact."
        )
    }

    func testCompatibleConfigAPIKeyStatusIsOptionalNotError() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("private var apiKeyStatusText: String"),
            "The API Key status should be derived from provider-specific readiness rules."
        )
        XCTAssertTrue(
            source.contains("case .openAICompatible:\n            return \"可选\""),
            "OpenAI-compatible configs should not show an empty API Key as a red missing requirement."
        )
        XCTAssertTrue(
            source.contains("case .claude, .openAI:\n            return \"未配置\""),
            "Hosted providers should still clearly require an API Key."
        )
        XCTAssertTrue(
            source.contains("OpenAI Compatible 端点可按服务需要选择是否填写 API Key。"),
            "The optional API Key state should explain why it differs from hosted providers."
        )
    }

    func testConfigEditorExplainsDefaultAndCustomBaseURLs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("private var endpointHelpText: String"),
            "The endpoint field should explain provider-specific default and required endpoint behavior."
        )
        XCTAssertTrue(
            source.contains("留空使用官方默认端点：\\(provider.resolvedBaseURL(\"\"))"),
            "Hosted providers should explain that a blank endpoint uses the official default."
        )
        XCTAssertTrue(
            source.contains("自定义 OpenAI 兼容端点必填"),
            "OpenAI-compatible configs should keep endpoint requirements visible near the field."
        )
        XCTAssertTrue(
            source.contains("Text(endpointHelpText)"),
            "Endpoint guidance should be visible in the editor, not only encoded in validation rules."
        )
    }

    func testConfigEditorConfirmsDiscardingUnsavedChanges() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("@State private var showingDiscardConfirmation = false"),
            "The model config editor should stage discard confirmation instead of closing immediately with unsaved edits."
        )
        XCTAssertTrue(
            source.contains("private var hasUnsavedChanges: Bool"),
            "The editor should compare current fields against its initial snapshot before dismissing."
        )
        XCTAssertTrue(
            source.contains("trimmedName != originalName")
                && source.contains("provider != originalProvider")
                && source.contains("trimmedBaseURL != originalBaseURL")
                && source.contains("trimmedAPIKey != originalAPIKey")
                && source.contains("trimmedModel != originalModel"),
            "Unsaved-change detection should cover every editable model config field, including API Key."
        )
        XCTAssertTrue(
            source.contains("Button(\"取消\") {\n                    requestDismiss()\n                }"),
            "The cancel button should route through discard confirmation instead of calling dismiss directly."
        )
        XCTAssertTrue(
            source.contains(".interactiveDismissDisabled(hasUnsavedChanges)"),
            "Interactive sheet dismissal should not silently discard changed model configuration."
        )
        XCTAssertTrue(
            source.contains(".alert(\"放弃未保存的模型配置？\", isPresented: $showingDiscardConfirmation)"),
            "Discarding unsaved model config changes should require an explicit confirmation alert."
        )
        XCTAssertTrue(
            source.contains("Button(\"继续编辑\", role: .cancel)")
                && source.contains("Button(\"放弃更改\", role: .destructive)"),
            "The discard confirmation should make the safe path and destructive path explicit."
        )
    }

    func testConfigSetDeletionKeepsAtLeastOneUsableModelConfig() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("if canDeleteConfigSet(configSet)"),
            "Config rows should derive deletion availability from usable configuration state, not only raw row count."
        )
        XCTAssertTrue(
            source.contains("private func canDeleteConfigSet(_ configSet: ConfigSet) -> Bool"),
            "The delete affordance should centralize its last-usable-config rule."
        )
        XCTAssertTrue(
            source.contains("guard manager.configSets.count > 1 else { return false }"),
            "The settings UI should still keep at least one config row available for editing."
        )
        XCTAssertTrue(
            source.contains("return !configSet.isConfigured || configuredCount > 1"),
            "Deleting incomplete configs should remain possible, but deleting the last usable config should be blocked."
        )
        XCTAssertTrue(
            source.contains("至少保留一个可用模型配置；如需替换，请先添加并保存新的可用配置。"),
            "The disabled delete affordance should explain how to replace the last usable model config safely."
        )
        XCTAssertTrue(
            source.contains(".help(deleteDisabledReason(for: configSet))"),
            "Locked delete controls should expose the specific reason on hover."
        )
    }
}
