import XCTest
@testable import RioAgent

final class ErrorRecoveryContextTests: XCTestCase {
    func testRecoveryActionsDescribeConcreteSettingsDestinations() {
        XCTAssertEqual(
            ErrorRecoveryContext.executionModel.recoveryActionTitle,
            "前往 AI 配置修复执行模型"
        )
        XCTAssertEqual(
            ErrorRecoveryContext.routerModel.recoveryActionTitle,
            "前往 Multi-Agent 修复 Router"
        )
        XCTAssertTrue(
            ErrorRecoveryContext.multiAgentWorkerAssignment.recoveryActionDetail.contains("设置 → Multi-Agent → 子 Agent 池")
        )
        XCTAssertTrue(
            ErrorRecoveryContext.multiAgentOrchestratorModel.recoveryActionDetail.contains("设置 → Multi-Agent → 主 Agent")
        )
    }
}
