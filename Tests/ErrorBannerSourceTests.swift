import XCTest

final class ErrorBannerSourceTests: XCTestCase {
    func testErrorBannerSupportsReadableAndCopyableDiagnostics() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("@State private var isExpanded = false"),
            "ErrorBanner should support expanding long diagnostics without making every error banner tall."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(isExpanded ? 8 : 2)"),
            "Expanded errors should reveal more diagnostic context than the compact two-line banner."
        )
        XCTAssertTrue(
            source.contains(".textSelection(.enabled)"),
            "Error text should be selectable for manual copy."
        )
        XCTAssertTrue(
            source.contains("NSPasteboard.general.setString(message, forType: .string)"),
            "ErrorBanner should provide a direct copy action for complete diagnostics."
        )
        XCTAssertTrue(
            source.contains("ErrorBannerUtilityButton("),
            "Secondary error-banner utilities should collapse into compact icon buttons so recovery actions remain primary."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: message)"),
            "Changing errors should reset expansion and copied state."
        )
    }

    func testErrorBannerDistinguishesNonBlockingDegradedFlow() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("isNonBlocking: error.contains(\"已继续执行标准流程\")"),
            "Non-blocking router fallback should be passed to the banner as a degraded-flow state."
        )
        XCTAssertTrue(
            source.contains("isNonBlocking ? \"部分流程已降级\" : \"本轮执行遇到问题\""),
            "Non-blocking fallback should not be presented as a stopped execution failure."
        )
        XCTAssertTrue(
            source.contains("return \"继续执行\""),
            "The banner badge should clarify that the main task continues after a degraded router flow."
        )
        XCTAssertTrue(
            source.contains("return onOpenSettings == nil ? \"可恢复\" : \"可恢复 / 待配置\""),
            "Recoverable errors that still require configuration work should expose both truths in the badge instead of collapsing them into a generic state."
        )
        XCTAssertTrue(
            source.contains("isNonBlocking ? Theme.statusWarning : Theme.statusError"),
            "Degraded-flow banners should use a warning tone instead of the blocking error tone."
        )
    }

    func testConfigErrorsOfferSettingsShortcutFromErrorBanner() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ContentView.swift"))

        XCTAssertTrue(
            source.contains("onOpenSettings: settingsShortcutAction(for: error, recoveryContext: agentEngine.errorRecoveryContext)"),
            "Configuration-related errors should provide a routed one-click path into settings."
        )
        XCTAssertTrue(
            source.contains("settingsButtonTitle: settingsShortcutTitle(for: error, recoveryContext: agentEngine.errorRecoveryContext)"),
            "Error banner should surface a context-aware settings action title instead of a generic button label."
        )
        XCTAssertTrue(
            source.contains("private func settingsShortcutAction("),
            "Settings shortcut routing should be explicit instead of showing for every error."
        )
        XCTAssertTrue(
            source.contains("private func settingsShortcutTitle("),
            "Settings shortcut titles should be derived explicitly from structured recovery context."
        )
        XCTAssertTrue(
            source.contains("settingsInitialTab = launchContext.tab"),
            "Error recovery should derive the initial settings tab from an explicit launch context."
        )
        XCTAssertTrue(
            source.contains("settingsLaunchContext = launchContext"),
            "Opening settings from an error should preserve the specific recovery context."
        )
        XCTAssertTrue(
            source.contains("recoveryContext: ErrorRecoveryContext?"),
            "Error banner routing should accept a structured recovery context from the runtime."
        )
        XCTAssertTrue(
            source.contains("SettingsRecoveryRouter.resolve("),
            "ContentView should delegate recovery routing to the shared router instead of embedding keyword rules."
        )
        XCTAssertTrue(
            source.contains("ErrorBannerUtilityButton(\n                            icon: \"gearshape\""),
            "Settings recovery should render as a secondary utility so task recovery stays primary."
        )
        XCTAssertTrue(
            source.contains(".help(settingsHelpText ?? \"打开设置修复当前配置问题\")"),
            "The settings shortcut help text should reflect the actual recovery target instead of a hard-coded AI message."
        )
    }

    func testSettingsRecoveryRouterCentralizesLegacyAndStructuredRecoveryRules() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/SettingsRecoveryRouter.swift"))

        XCTAssertTrue(
            source.contains("if let recoveryContext"),
            "Structured runtime recovery context should take priority over legacy string matching."
        )
        XCTAssertTrue(
            source.contains("static func settingsLaunchContext(from recoveryContext: ErrorRecoveryContext) -> SettingsLaunchContext"),
            "Runtime recovery contexts should be mapped into settings launch contexts explicitly."
        )
        XCTAssertTrue(
            source.contains("static func shouldOpenAISettings(for error: String) -> Bool"),
            "AI configuration failures should still be classified separately from Multi-Agent setup failures."
        )
        XCTAssertTrue(
            source.contains("static func shouldOpenMultiAgentSettings(for error: String) -> Bool"),
            "Multi-Agent setup failures should route into the Multi-Agent tab directly."
        )
        XCTAssertTrue(
            source.contains(".routerModel"),
            "Router failures should land in a dedicated router recovery context instead of generic AI settings."
        )
        XCTAssertTrue(
            source.contains(".multiAgentOrchestratorModel"),
            "Multi-Agent orchestrator failures should land in a dedicated orchestrator recovery context."
        )
        XCTAssertTrue(
            source.contains(".multiAgentWorkerAssignment"),
            "Missing worker assignment should lead directly to the worker assignment recovery path."
        )
        XCTAssertTrue(
            source.contains(".multiAgentWorkerModel"),
            "Broken worker model bindings should lead to the worker model recovery path."
        )
        XCTAssertTrue(
            source.contains("? .planningModel : .executionModel"),
            "Planning-model failures should still be distinguished from execution-model failures."
        )
    }
}
