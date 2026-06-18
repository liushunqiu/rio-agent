import XCTest
@testable import RioAgent

final class SettingsRecoveryRouterTests: XCTestCase {
    func testStructuredRecoveryContextTakesPriorityOverLegacyErrorText() {
        let resolved = SettingsRecoveryRouter.resolve(
            error: "Router 不可用",
            recoveryContext: .executionModel
        )

        XCTAssertEqual(resolved, .executionModel)
    }

    func testLegacyMultiAgentErrorsResolveToSpecificLaunchContexts() {
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "Router 模型不可用"),
            .routerModel
        )
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "主 Agent 编排器不可用"),
            .multiAgentOrchestratorModel
        )
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "未分配执行 Agent"),
            .multiAgentWorkerAssignment
        )
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "Worker 未选择可用模型配置"),
            .multiAgentWorkerModel
        )
    }

    func testLegacyAIErrorsResolveToPlanningAndExecutionContexts() {
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "规划模型未选择模型"),
            .planningModel
        )
        XCTAssertEqual(
            SettingsRecoveryRouter.legacySettingsLaunchContext(for: "执行模型 API Key 不可用"),
            .executionModel
        )
    }

    func testUnknownErrorDoesNotProduceSettingsShortcut() {
        XCTAssertNil(
            SettingsRecoveryRouter.resolve(
                error: "普通运行错误",
                recoveryContext: nil
            )
        )
    }
}
