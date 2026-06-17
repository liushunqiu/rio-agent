import XCTest
@testable import RioAgent

final class VerifierServiceTests: XCTestCase {
    func testVerifierMarksErroredExecutionAsNeedsRetry() async {
        let verifier = VerifierService(aiService: nil, model: "test-model")

        let outcome = await verifier.verify(
            task: "run tests",
            output: "tests passed",
            errors: ["command failed"],
            evidence: ["tool=execute_command\nstatus=ERROR\nevidence=exit code 1"],
            systemPrompt: nil
        )

        XCTAssertEqual(outcome.status, .needsRetry)
    }

    func testVerifierMarksMissingEvidenceAsUnverified() async {
        let verifier = VerifierService(aiService: nil, model: "test-model")

        let outcome = await verifier.verify(
            task: "edit file",
            output: "I updated the file",
            errors: [],
            evidence: [],
            systemPrompt: nil
        )

        XCTAssertEqual(outcome.status, .unverified)
    }

    func testVerifierHeuristicMarksConcreteEvidenceAsVerified() async {
        let verifier = VerifierService(aiService: nil, model: "test-model")

        let outcome = await verifier.verify(
            task: "read back the file after editing",
            output: "已修改并读回目标文件，内容符合预期。",
            errors: [],
            evidence: ["tool=read_file\nstatus=SUCCESS\nevidence=line 1: updated content"],
            systemPrompt: nil
        )

        XCTAssertEqual(outcome.status, .verified)
    }

    func testVerifierDoesNotTreatEmptySuccessOutputAsVerifiedEvidence() async {
        let verifier = VerifierService(aiService: nil, model: "test-model")

        let outcome = await verifier.verify(
            task: "modify file",
            output: "已完成修改。",
            errors: [],
            evidence: ["tool=execute_command\nstatus=SUCCESS\nevidence=（空输出）"],
            systemPrompt: nil
        )

        XCTAssertEqual(outcome.status, .unverified)
    }
}
