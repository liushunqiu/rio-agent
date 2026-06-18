import XCTest

final class ExecutionPipelineStatusSourceTests: XCTestCase {
    func testExecutionStageDetailsExposeFailureAndCancellationCounts() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelSource = try String(contentsOf: repoRoot.appendingPathComponent("Models/ExecutionPipeline.swift"))
        let engineSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let viewSource = try String(contentsOf: repoRoot.appendingPathComponent("Views/ExecutionPipelineView.swift"))

        XCTAssertTrue(
            modelSource.contains("failedCount: Int = 0"),
            "Execution stage details should carry failure counts without forcing the whole recoverable pipeline to fail."
        )
        XCTAssertTrue(
            modelSource.contains("cancelledCount: Int = 0"),
            "Execution stage details should carry cancellation counts for stopped tool/subtask work."
        )
        XCTAssertTrue(
            engineSource.contains("let failed = results.filter { $0.status == .error }.count"),
            "Single-agent tool execution should count failed tool results."
        )
        XCTAssertTrue(
            engineSource.contains("failed: failed"),
            "Tool failure counts should be published into pipeline details."
        )
        XCTAssertTrue(
            engineSource.contains(".filter { $0.status == .failed }"),
            "Live substep synchronization should preserve failure counts even before the final result array is available."
        )
        XCTAssertTrue(
            engineSource.contains("failedSubTaskCount(in: plan)"),
            "Multi-Agent execution stages should reflect failed subtasks in the shared pipeline UI."
        )
        XCTAssertTrue(
            viewSource.contains("if failed > 0 { parts.append(\"\\(failed) 个失败\") }"),
            "Execution stage summaries should call out failed work instead of only saying execution completed."
        )
        XCTAssertTrue(
            viewSource.contains("parts.append(\"无失败\")"),
            "Successful execution details should explicitly reassure users that no tool failed."
        )
    }
}
