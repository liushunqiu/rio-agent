import XCTest
@testable import RioAgent

final class SubTaskAttentionTests: XCTestCase {
    func testNeedsAttentionForFailedCancelledVerificationRetryAndRecoveryContext() {
        XCTAssertTrue(SubTask(description: "failed", status: .failed).needsAttention)
        XCTAssertTrue(SubTask(description: "cancelled", status: .cancelled).needsAttention)
        XCTAssertTrue(
            SubTask(
                description: "retry",
                status: .completed,
                verificationStatus: .needsRetry
            ).needsAttention
        )
        XCTAssertTrue(
            SubTask(
                description: "blocked",
                status: .pending,
                recoveryContext: .multiAgentWorkerAssignment
            ).needsAttention
        )
    }

    func testNeedsAttentionIsFalseForHealthyCompletedSubTask() {
        XCTAssertFalse(
            SubTask(
                description: "ok",
                status: .completed,
                verificationStatus: .verified,
                recoveryContext: nil
            ).needsAttention
        )
    }
}
