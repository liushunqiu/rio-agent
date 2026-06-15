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

    func testFileReadRejectsNegativePaginationArguments() async throws {
        let tool = FileReadTool()

        let negativeOffset = try await tool.execute(arguments: [
            "path": "/tmp/example.txt",
            "offset": -1
        ])
        XCTAssertEqual(negativeOffset.status, .error)
        XCTAssertTrue(negativeOffset.error?.contains("offset") == true)

        let negativeMaxLines = try await tool.execute(arguments: [
            "path": "/tmp/example.txt",
            "max_lines": -1
        ])
        XCTAssertEqual(negativeMaxLines.status, .error)
        XCTAssertTrue(negativeMaxLines.error?.contains("max_lines") == true)
    }

    func testApplyPatchValidationFailureDoesNotPartiallyModifyFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let firstFile = tempDir.appendingPathComponent("first.txt")
        let secondFile = tempDir.appendingPathComponent("second.txt")
        try "alpha\n".write(to: firstFile, atomically: true, encoding: .utf8)
        try "bravo\n".write(to: secondFile, atomically: true, encoding: .utf8)

        let previousWorkingDirectory = ToolRegistry.shared.workingDirectory
        ToolRegistry.shared.workingDirectory = tempDir.path
        defer {
            ToolRegistry.shared.workingDirectory = previousWorkingDirectory
        }

        let patch = """
        *** Update File: \(firstFile.path)
        <<<<<<< SEARCH
        alpha
        =======
        changed
        >>>>>>> REPLACE
        *** Update File: \(secondFile.path)
        <<<<<<< SEARCH
        missing
        =======
        changed
        >>>>>>> REPLACE
        """

        let result = try await ApplyPatchTool().execute(arguments: ["patch": patch])

        XCTAssertEqual(result.status, .error)
        XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "alpha\n")
        XCTAssertEqual(try String(contentsOf: secondFile, encoding: .utf8), "bravo\n")
    }
}
