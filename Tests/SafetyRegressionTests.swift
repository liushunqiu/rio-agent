import XCTest
@testable import RioAgent

final class SafetyRegressionTests: XCTestCase {

    func testPathSecurityRejectsPrefixCollision() {
        XCTAssertFalse(
            PathSecurity.isWithinDirectory(
                "/Users/test/project-backup/secrets.txt",
                workingDirectory: "/Users/test/project"
            )
        )
    }

    func testPathSecurityAllowsNestedPath() {
        XCTAssertTrue(
            PathSecurity.isWithinDirectory(
                "/Users/test/project/Sources/App/main.swift",
                workingDirectory: "/Users/test/project"
            )
        )
    }

    func testCommandClassifierTreatsGitPushAsNonSafe() {
        XCTAssertNotEqual(CommandClassifier.classify("git push origin main"), .safe)
    }

    func testCommandClassifierTreatsNpmInstallAsNonSafe() {
        XCTAssertNotEqual(CommandClassifier.classify("npm install"), .safe)
    }

    func testCommandClassifierTreatsReadOnlyGitStatusAsSafe() {
        XCTAssertEqual(CommandClassifier.classify("git status --short"), .safe)
    }
}
