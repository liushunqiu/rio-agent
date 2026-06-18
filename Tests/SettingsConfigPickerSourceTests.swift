import XCTest

final class SettingsConfigPickerSourceTests: XCTestCase {
    func testConfigSetPickerRowsExposeAndDisableIncompleteConfigSets() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("if let readinessIssue = configSet.readinessIssue"),
            "Planning/execution config picker rows should show why an incomplete model config is not usable."
        )
        XCTAssertTrue(
            source.contains(".disabled(!configSet.isConfigured)"),
            "Planning/execution config picker rows should not allow selecting incomplete model configs."
        )
        XCTAssertTrue(
            source.contains("暂不可选"),
            "Disabled config picker rows should expose a short hover hint instead of silently ignoring clicks."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.name)"),
            "Config picker rows should expose the full config name when it is truncated."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.model.isEmpty ? \"未设置模型\" : configSet.model)"),
            "Config picker rows should expose the full model identifier when it is truncated."
        )
        XCTAssertTrue(
            source.contains(".help(readinessIssue)"),
            "Readiness warnings should expose the full reason after the visible text is line-limited."
        )
    }

    func testLegacyProviderRowsExposeTruncatedProviderAndModelText() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains(".help(provider.displayName)"),
            "Provider picker rows should expose the full provider label when the settings panel is narrow."
        )
        XCTAssertTrue(
            source.contains(".help(model.isEmpty ? \"未设置模型\" : model)"),
            "Provider picker rows should expose the full model text when it is truncated."
        )
        XCTAssertTrue(
            source.contains(".help(value.isEmpty ? \"未设置\" : value)"),
            "Settings metric cards should expose full values after middle truncation."
        )
    }

    func testSettingsReconciliationFallsBackOnlyToConfiguredConfigSets() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("let readySets = configSetManager.configSets.filter(\\.isConfigured)"),
            "Settings reconciliation should use the same readiness rule as picker row disabling."
        )
        XCTAssertTrue(
            source.contains("let fallbackId = readySets.first?.id"),
            "Fallback selection should not silently bind an incomplete model config."
        )
        XCTAssertFalse(
            source.contains("let fallbackId = sets.first?.id"),
            "Settings reconciliation should not fall back to the first raw config set."
        )
    }

    func testSettingsViewSupportsExplicitInitialTab() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("@State private var selectedTab: SettingsTab"),
            "SettingsView should allow the opener to choose which settings tab is initially focused."
        )
        XCTAssertTrue(
            source.contains("initialTab: SettingsTab = .ai"),
            "SettingsView should default to AI settings while still allowing explicit tab routing."
        )
        XCTAssertTrue(
            source.contains("self._selectedTab = State(initialValue: initialTab)"),
            "The requested initial tab should be applied immediately when the sheet opens."
        )
    }

    func testSettingsViewSupportsRecoveryLaunchContext() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsView.swift"))

        XCTAssertTrue(
            source.contains("enum SettingsLaunchContext: Equatable"),
            "Settings recovery should use an explicit launch context instead of inferring everything from the selected tab."
        )
        XCTAssertTrue(
            source.contains("launchContext: SettingsLaunchContext? = nil"),
            "SettingsView should accept an optional launch context from the caller."
        )
        XCTAssertTrue(
            source.contains("if let launchContext {\n                            SettingsRecoveryBanner(context: launchContext)"),
            "Settings opened from an error should render a recovery banner above the tab content."
        )
        XCTAssertTrue(
            source.contains("if let launchContext, launchContext.tab == selectedTab"),
            "The header subtitle should switch to recovery guidance when the current tab matches the launch context."
        )
        XCTAssertTrue(
            source.contains("SettingsSidebarItem(tab: .ai, selectedTab: $selectedTab, launchContext: launchContext)"),
            "Recovery-aware settings routing should also flow through the sidebar items."
        )
        XCTAssertTrue(
            source.contains("let launchContext: SettingsLaunchContext?"),
            "Settings sidebar items should know about the shared launch context."
        )
        XCTAssertTrue(
            source.contains("private var isRecoveryTarget: Bool { launchContext?.tab == tab }"),
            "Sidebar items should explicitly identify when they are the recovery destination."
        )
        XCTAssertTrue(
            source.contains("Image(systemName: \"wrench.and.screwdriver.fill\")"),
            "The recovery target tab should expose a dedicated visual marker in the settings sidebar."
        )
        XCTAssertTrue(
            source.contains(".help(sidebarHelpText)"),
            "Sidebar items should expose the full recovery guidance on hover when they are the recovery target."
        )
        XCTAssertTrue(
            source.contains("struct SettingsRecoveryBanner: View"),
            "Recovery guidance should live in a dedicated banner component."
        )
        XCTAssertTrue(
            source.contains("struct SectionRecoveryCallout: View"),
            "Section-level recovery focus should use a dedicated callout component."
        )
        XCTAssertTrue(
            source.contains("Text(\"正在修复\")"),
            "Recovery-targeted settings sections should expose a stronger section-level repair marker, not just a subtle border."
        )
        XCTAssertTrue(
            source.contains("foregroundColor(recoveryMessage == nil ? Theme.accentPrimary : Theme.statusWarning)"),
            "Recovery-targeted section headers should elevate their icon tone when they are the active fix destination."
        )
        XCTAssertTrue(
            source.contains("Text(context.title)"),
            "The recovery banner should state what needs to be fixed."
        )
        XCTAssertTrue(
            source.contains("Text(context.detail)"),
            "The recovery banner should explain the concrete repair action."
        )
        XCTAssertTrue(
            source.contains("var destinationLabel: String"),
            "Recovery contexts should provide a concrete in-settings destination label."
        )
        XCTAssertTrue(
            source.contains("Text(\"修复位置：\\(context.destinationLabel)\")"),
            "The recovery banner should name the exact settings section to fix."
        )
        XCTAssertTrue(
            source.contains("recoveryMessage: planningRecoveryMessage"),
            "Planning model recovery should highlight the planning config section directly."
        )
        XCTAssertTrue(
            source.contains("recoveryMessage: executionRecoveryMessage"),
            "Execution model recovery should highlight the execution config section directly."
        )
        XCTAssertTrue(
            source.contains("if let recoveryMessage"),
            "Settings sections should render recovery callouts when launched from a targeted error."
        )
    }
}
