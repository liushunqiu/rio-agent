import XCTest
@testable import RioAgent

final class ExecutionPipelineModelTests: XCTestCase {
    func testEmptyPipelineIsPendingInsteadOfCompleted() {
        let pipeline = ExecutionPipeline(mode: .singleAgent)

        XCTAssertEqual(pipeline.overallStatus, .pending)
    }

    func testCompletedAndSkippedStagesProduceCompletedPipeline() {
        var completedStage = PipelineStage(type: .execution)
        completedStage.complete()
        var skippedStage = PipelineStage(type: .verification)
        skippedStage.skip(reason: "无需验证")
        var pipeline = ExecutionPipeline(mode: .singleAgent)
        pipeline.stages = [completedStage, skippedStage]

        XCTAssertEqual(pipeline.overallStatus, .completed)
    }

    func testFailedStageTakesPriorityOverCompletedStages() {
        var completedStage = PipelineStage(type: .execution)
        completedStage.complete()
        var failedStage = PipelineStage(type: .verification)
        failedStage.fail(error: "验证未通过")
        var pipeline = ExecutionPipeline(mode: .multiAgent)
        pipeline.stages = [completedStage, failedStage]

        XCTAssertEqual(pipeline.overallStatus, .failed)
    }
}
