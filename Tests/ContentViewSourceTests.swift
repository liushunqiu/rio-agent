import XCTest

final class ContentViewSourceTests: XCTestCase {
    func testMainChatReceivesCurrentTaskPlanForMultiAgentVisibility() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("currentTaskPlan: agentEngine.currentTaskPlan"),
            "EnhancedChatView must receive the active task plan so Multi-Agent progress is visible in the main transcript."
        )
        XCTAssertTrue(
            source.contains("currentPipeline: agentEngine.currentPipeline"),
            "EnhancedChatView should receive the active pipeline so the main transcript can render runtime guidance."
        )
        XCTAssertTrue(
            source.contains("pendingUserDecision: agentEngine.pendingUserDecision"),
            "EnhancedChatView should receive pending confirmation state so transcript runtime guidance does not keep advertising an in-flight pipeline after execution pauses for user input."
        )
        XCTAssertFalse(
            source.contains("currentTaskPlan: nil"),
            "Passing nil hides TaskPlanView even while a Multi-Agent task is running."
        )
    }

    func testWorkingDirectoryBadgesExposeFullPath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains(".help(currentWorkingDirectory)"),
            "Top-bar workspace badges should expose the full path when the visible folder name is compact."
        )
        XCTAssertTrue(
            source.contains(".help(workingDirectory)"),
            "Empty-state workspace badges should expose the full path."
        )
        XCTAssertTrue(
            source.contains("private var folderHelpText: String"),
            "The input folder selector should have provider-specific help text for selected and unselected states."
        )
        XCTAssertTrue(
            source.contains("return \"当前工作目录：\\(dir)\""),
            "The folder selector should show the full selected path in its tooltip."
        )
        XCTAssertTrue(
            source.contains(".truncationMode(.middle)"),
            "Long workspace folder names should truncate safely instead of pushing nearby controls."
        )
        XCTAssertTrue(
            source.contains("if let focusSummary"),
            "The top bar should surface a separate focus summary instead of collapsing all runtime state into one generic badge."
        )
        XCTAssertTrue(
            source.contains("singleAgentVerification: agentEngine.singleAgentVerificationSummary"),
            "The top bar should receive the single-agent verification state so finalized answers can still surface missing evidence."
        )
        XCTAssertTrue(
            source.contains("var singleAgentVerification: VerifierService.VerificationOutcome?"),
            "TopBar should explicitly model single-agent verification as first-class runtime state."
        )
        XCTAssertTrue(
            source.contains("return \"未验证\""),
            "Top-bar pipeline status should call out unverified single-agent results instead of silently looking completed."
        )
        XCTAssertTrue(
            source.contains("return \"答案需要修订\""),
            "Top-bar focus summary should surface revision-required verification outcomes."
        )
        XCTAssertTrue(
            source.contains("currentTaskPlan.subTasks.filter(\\.needsAttention).count"),
            "Top-bar focus summary should use the shared SubTask attention state so blocked and cancelled subtasks are counted consistently."
        )
    }
}
