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

    func testPathSecurityExpandsTildePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertEqual(PathSecurity.normalizedPath("~/Documents"), "\(home)/Documents")
        XCTAssertTrue(
            PathSecurity.isWithinDirectory(
                "~/Documents/example.txt",
                workingDirectory: "\(home)/Documents"
            )
        )
    }

    func testPathSecurityRelativePathUsesDirectoryBoundary() {
        XCTAssertEqual(
            PathSecurity.relativePath(
                "/Users/test/project/Sources/App.swift",
                from: "/Users/test/project"
            ),
            "Sources/App.swift"
        )
        XCTAssertEqual(
            PathSecurity.relativePath(
                "/Users/test/project-backup/Sources/App.swift",
                from: "/Users/test/project"
            ),
            "/Users/test/project-backup/Sources/App.swift"
        )
    }

    func testPathSecurityRelativePathForWorkspaceRootUsesFolderName() {
        XCTAssertEqual(
            PathSecurity.relativePath(
                "/Users/test/project",
                from: "/Users/test/project"
            ),
            "project"
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

    func testCommandClassifierTreatsRedirectionAsNonSafe() {
        XCTAssertNotEqual(CommandClassifier.classify("echo hello > output.txt"), .safe)
        XCTAssertNotEqual(CommandClassifier.classify("git status --short 2> errors.log"), .safe)
    }

    func testCommandClassifierAllowsSafeRedirectionInsideWorkingDirectory() {
        XCTAssertEqual(
            CommandClassifier.classify(
                "echo hello > output.txt",
                workingDirectory: "/Users/test/project"
            ),
            .safe
        )
        XCTAssertEqual(
            CommandClassifier.classify(
                "git status --short 2> logs/errors.log",
                workingDirectory: "/Users/test/project"
            ),
            .safe
        )
    }

    func testCommandClassifierRejectsUnsafeRedirectionTargets() {
        XCTAssertNotEqual(
            CommandClassifier.classify(
                "echo hello > /Users/test/other/output.txt",
                workingDirectory: "/Users/test/project"
            ),
            .safe
        )
        XCTAssertNotEqual(
            CommandClassifier.classify(
                "echo hello > $OUTPUT_FILE",
                workingDirectory: "/Users/test/project"
            ),
            .safe
        )
    }

    func testCommandClassifierSplitsShellControlOperatorsBeforeSafeMatch() {
        XCTAssertNotEqual(CommandClassifier.classify("echo hello; touch created.txt"), .safe)
        XCTAssertEqual(CommandClassifier.classify("pwd && git status --short"), .safe)
    }

    func testCommandClassifierIgnoresShellOperatorsInsideQuotes() {
        XCTAssertEqual(CommandClassifier.classify("echo 'a; b && c | d'"), .safe)
        XCTAssertEqual(
            CommandClassifier.classify(
                "echo 'hello > output.txt'",
                workingDirectory: "/Users/test/project"
            ),
            .safe
        )
    }

    func testCommandClassifierRequiresConfirmationForDynamicShellSyntax() {
        XCTAssertEqual(CommandClassifier.classify("echo $(pwd)"), .normal)
        XCTAssertEqual(CommandClassifier.classify("echo `pwd`"), .normal)
        XCTAssertEqual(CommandClassifier.classify("echo $HOME"), .normal)
        XCTAssertEqual(CommandClassifier.classify("echo ${HOME}"), .normal)
    }

    func testCommandClassifierRequiresConfirmationForDynamicShellSyntaxInsideDoubleQuotes() {
        XCTAssertEqual(CommandClassifier.classify("echo \"$(pwd)\""), .normal)
        XCTAssertEqual(CommandClassifier.classify("echo \"$HOME\""), .normal)
        XCTAssertEqual(CommandClassifier.classify("echo '$(pwd)'"), .safe)
    }

    func testCommandClassifierIgnoresDangerousWordsInsideQuotes() {
        XCTAssertEqual(CommandClassifier.classify("echo 'curl https://example.com'"), .safe)
        XCTAssertEqual(CommandClassifier.classify("printf 'rm -rf /'"), .safe)
        XCTAssertEqual(CommandClassifier.classify("echo \"sudo reboot\""), .safe)
    }

    func testCommandClassifierTreatsQuotedPipesAsSingleSafeCommand() {
        XCTAssertEqual(CommandClassifier.classify("printf 'a|b'"), .safe)
        XCTAssertNotEqual(CommandClassifier.classify("printf ok | touch created.txt"), .safe)
    }

    func testCommandClassifierTreatsPipeToInterpreterAsDangerous() {
        XCTAssertEqual(CommandClassifier.classify("cat script.sh|sh"), .dangerous)
    }

    func testShellToolSessionTrustIsExactCommandOnly() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tool = ShellTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        _ = try await tool.execute(arguments: [
            "command": "touch first.txt",
            "working_directory": tempDir.path
        ])
        _ = try await tool.execute(arguments: [
            "command": "touch second.txt",
            "working_directory": tempDir.path
        ])
        _ = try await tool.execute(arguments: [
            "command": "touch first.txt",
            "working_directory": tempDir.path
        ])

        XCTAssertEqual(confirmationCount, 2)
    }

    func testShellToolSessionTrustIsScopedToWorkingDirectory() async throws {
        let firstDir = try makeTemporaryWorkingDirectory()
        let secondDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }

        let tool = ShellTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        _ = try await tool.execute(arguments: [
            "command": "touch marker.txt",
            "working_directory": firstDir.path
        ])
        _ = try await tool.execute(arguments: [
            "command": "touch marker.txt",
            "working_directory": secondDir.path
        ])
        _ = try await tool.execute(arguments: [
            "command": "touch marker.txt",
            "working_directory": firstDir.path
        ])

        XCTAssertEqual(confirmationCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstDir.appendingPathComponent("marker.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondDir.appendingPathComponent("marker.txt").path))
    }

    func testShellToolConfirmationExplainsSessionTrustScope() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tool = ShellTool()
        var capturedMessage = ""
        tool.setConfirmationCallback { _, message, _ in
            capturedMessage = message
            return .denied
        }

        _ = try await tool.execute(arguments: [
            "command": "touch scoped.txt",
            "working_directory": tempDir.path
        ])

        XCTAssertTrue(capturedMessage.contains("工作目录:\n\(tempDir.path)"))
        XCTAssertTrue(capturedMessage.contains("只会信任该命令在当前工作目录下再次执行"))
    }

    func testDangerousShellCommandRejectsSessionTrust() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tool = ShellTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        let result = try await tool.execute(arguments: [
            "command": "curl https://example.com",
            "working_directory": tempDir.path
        ])

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertTrue(result.error?.contains("危险命令不能信任本会话") == true)
        XCTAssertEqual(confirmationCount, 1)
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

    func testFileToolsRejectRelativePathsBeforeFilesystemAccess() async throws {
        let readTool = FileReadTool()
        let writeTool = FileWriteTool()
        let editTool = EditFileTool()

        let readResult = try await readTool.execute(arguments: [
            "path": "Sources/App.swift"
        ])
        let writeResult = try await writeTool.execute(arguments: [
            "path": "Sources/App.swift",
            "content": "new content"
        ])
        let editResult = try await editTool.execute(arguments: [
            "path": "Sources/App.swift",
            "old_text": "old",
            "new_text": "new"
        ])

        XCTAssertEqual(readResult.status, .error)
        XCTAssertTrue(readResult.error?.contains("absolute path") == true)
        XCTAssertEqual(writeResult.status, .error)
        XCTAssertTrue(writeResult.error?.contains("absolute path") == true)
        XCTAssertEqual(editResult.status, .error)
        XCTAssertTrue(editResult.error?.contains("absolute path") == true)
    }

    func testEditFileRequiresCrossDirectoryConfirmationBeforeReadingContent() async throws {
        let workDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: workDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Outside.swift")
        try "let visible = true\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        let tool = EditFileTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .denied
        }

        let result = try await withTemporaryWorkingDirectory(workDir.path) {
            try await tool.execute(arguments: [
                "path": outsideFile.path,
                "old_text": "missing text that should not be checked before confirmation",
                "new_text": "replacement"
            ])
        }

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.error, "用户取消编辑")
        XCTAssertEqual(confirmationCount, 1)
    }

    func testEditFileWithoutConfirmationDoesNotRevealOutsideFileExistenceFirst() async throws {
        let workDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: workDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let missingOutsideFile = outsideDir.appendingPathComponent("Missing.swift")

        let result = try await withTemporaryWorkingDirectory(workDir.path) {
            try await EditFileTool().execute(arguments: [
                "path": missingOutsideFile.path,
                "old_text": "old",
                "new_text": "new"
            ])
        }

        XCTAssertEqual(result.status, .error)
        XCTAssertEqual(result.error, "编辑工作目录外文件需要用户确认")
    }

    func testDirectoryToolsRejectRelativeExplicitPaths() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let results = try await withTemporaryWorkingDirectory(tempDir.path) {
            [
                try await FindFilesTool().execute(arguments: [
                    "path": "Sources",
                    "pattern": "*.swift"
                ]),
                try await SearchFilesTool().execute(arguments: [
                    "path": "Sources",
                    "pattern": "target"
                ]),
                try await ListDirectoryTool().execute(arguments: [
                    "path": "Sources"
                ])
            ]
        }

        XCTAssertTrue(results.allSatisfy { $0.status == .error })
        XCTAssertTrue(results.allSatisfy { $0.error?.contains("absolute path") == true })
    }

    func testDirectoryToolsAllowAbsoluteReadOnlyPathsOutsideWorkingDirectory() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }
        let outsideFile = outsideDir.appendingPathComponent("Outside.swift")
        try "let targetValue = 1".write(to: outsideFile, atomically: true, encoding: .utf8)

        let results = try await withTemporaryWorkingDirectory(tempDir.path) {
            [
                try await FindFilesTool().execute(arguments: [
                    "path": outsideDir.path,
                    "pattern": "*.swift"
                ]),
                try await SearchFilesTool().execute(arguments: [
                    "path": outsideDir.path,
                    "pattern": "target"
                ]),
                try await ListDirectoryTool().execute(arguments: [
                    "path": outsideDir.path
                ])
            ]
        }

        XCTAssertTrue(results.allSatisfy { $0.status == .success })
        XCTAssertTrue(results[0].output.contains("Outside.swift"))
        XCTAssertTrue(results[1].output.contains("targetValue"))
        XCTAssertTrue(results[2].output.contains("Outside.swift"))
    }

    func testDirectoryToolsDefaultToWorkingDirectory() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let file = tempDir.appendingPathComponent("Keep.swift")
        try "let targetValue = 1".write(to: file, atomically: true, encoding: .utf8)

        let results = try await withTemporaryWorkingDirectory(tempDir.path) {
            [
                try await FindFilesTool().execute(arguments: ["pattern": "*.swift"]),
                try await SearchFilesTool().execute(arguments: ["pattern": "targetValue"]),
                try await ListDirectoryTool().execute(arguments: [:])
            ]
        }

        XCTAssertTrue(results.allSatisfy { $0.status == .success })
        XCTAssertTrue(results[0].output.contains("Keep.swift"))
        XCTAssertTrue(results[1].output.contains("targetValue"))
        XCTAssertTrue(results[2].output.contains("Directory: \(tempDir.path)"))
    }

    func testShellToolRejectsInvalidWorkingDirectoryBeforeExecution() async throws {
        let relativeResult = try await ShellTool().execute(arguments: [
            "command": "pwd",
            "working_directory": "Sources"
        ])
        XCTAssertEqual(relativeResult.status, .error)
        XCTAssertTrue(relativeResult.error?.contains("absolute path") == true)

        let missingResult = try await ShellTool().execute(arguments: [
            "command": "pwd",
            "working_directory": "/tmp/rio-agent-missing-\(UUID().uuidString)"
        ])
        XCTAssertEqual(missingResult.status, .error)
        XCTAssertTrue(missingResult.error?.contains("does not exist") == true)
    }

    func testFileReadHonorsEncodingArgument() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tempFile = tempDir.appendingPathComponent("latin1.txt")
        try withTemporaryWorkingDirectory(tempDir.path) {
            try "café".write(to: tempFile, atomically: true, encoding: .isoLatin1)
        }

        let tool = FileReadTool()
        let result = try await withTemporaryWorkingDirectory(tempDir.path) {
            try await tool.execute(arguments: [
                "path": tempFile.path,
                "encoding": "latin1"
            ])
        }

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("café"))
    }

    func testFileReadReportsEmptyFilesAsZeroLines() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tempFile = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: tempFile)

        let tool = FileReadTool()
        let result = try await withTemporaryWorkingDirectory(tempDir.path) {
            try await tool.execute(arguments: ["path": tempFile.path])
        }

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("总行数: 0"))
    }

    func testFileReadSessionTrustIsScopedToWorkingDirectory() async throws {
        let firstDir = try makeTemporaryWorkingDirectory()
        let secondDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Outside.txt")
        try "shared secret".write(to: outsideFile, atomically: true, encoding: .utf8)

        let tool = FileReadTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        let firstResult = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path])
        }
        let secondResult = try await withTemporaryWorkingDirectory(secondDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path])
        }
        let repeatedFirstResult = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path])
        }

        XCTAssertEqual(firstResult.status, .success)
        XCTAssertEqual(secondResult.status, .success)
        XCTAssertEqual(repeatedFirstResult.status, .success)
        XCTAssertEqual(confirmationCount, 2)
    }

    func testFileWriteSessionTrustIsScopedToWorkingDirectory() async throws {
        let firstDir = try makeTemporaryWorkingDirectory()
        let secondDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Outside.txt")
        let tool = FileWriteTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        _ = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path, "content": "first"])
        }
        _ = try await withTemporaryWorkingDirectory(secondDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path, "content": "second"])
        }
        let repeatedFirstResult = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: ["path": outsideFile.path, "content": "third"])
        }

        XCTAssertEqual(repeatedFirstResult.status, .success)
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "third")
        XCTAssertEqual(confirmationCount, 2)
    }

    func testEditFileSessionTrustIsScopedToWorkingDirectory() async throws {
        let firstDir = try makeTemporaryWorkingDirectory()
        let secondDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Outside.txt")
        try "one\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        let tool = EditFileTool()
        var confirmationCount = 0
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        _ = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: [
                "path": outsideFile.path,
                "old_text": "one",
                "new_text": "two"
            ])
        }
        _ = try await withTemporaryWorkingDirectory(secondDir.path) {
            try await tool.execute(arguments: [
                "path": outsideFile.path,
                "old_text": "two",
                "new_text": "three"
            ])
        }
        let repeatedFirstResult = try await withTemporaryWorkingDirectory(firstDir.path) {
            try await tool.execute(arguments: [
                "path": outsideFile.path,
                "old_text": "three",
                "new_text": "four"
            ])
        }

        XCTAssertEqual(repeatedFirstResult.status, .success)
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "four\n")
        XCTAssertEqual(confirmationCount, 2)
    }

    private func makeTemporaryWorkingDirectory() throws -> URL {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFile, withIntermediateDirectories: true)
        return tempFile
    }

    private func withTemporaryWorkingDirectory<T>(_ path: String, operation: () throws -> T) rethrows -> T {
        let previousWorkingDirectory = ToolRegistry.shared.workingDirectory
        ToolRegistry.shared.workingDirectory = path
        defer {
            ToolRegistry.shared.workingDirectory = previousWorkingDirectory
        }
        return try operation()
    }

    private func withTemporaryWorkingDirectory<T>(_ path: String, operation: () async throws -> T) async rethrows -> T {
        let previousWorkingDirectory = ToolRegistry.shared.workingDirectory
        ToolRegistry.shared.workingDirectory = path
        defer {
            ToolRegistry.shared.workingDirectory = previousWorkingDirectory
        }
        return try await operation()
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

    func testApplyPatchRejectsUnexpectedSessionTrustResult() async throws {
        let workDir = try makeTemporaryWorkingDirectory()
        let outsideDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: workDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let outsideFile = outsideDir.appendingPathComponent("Outside.txt")
        var confirmationCount = 0
        let tool = ApplyPatchTool()
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .trustedForSession
        }

        let result = try await withTemporaryWorkingDirectory(workDir.path) {
            try await tool.execute(arguments: [
                "patch": """
                *** Add File: \(outsideFile.path)
                outside write
                """
            ])
        }

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.error, "批量补丁不支持信任本会话")
        XCTAssertEqual(confirmationCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    func testApplyPatchRejectsRelativePathsBeforeConfirmation() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        var confirmationCount = 0
        let tool = ApplyPatchTool()
        tool.setConfirmationCallback { _, _, _ in
            confirmationCount += 1
            return .approved
        }

        let result = try await withTemporaryWorkingDirectory(tempDir.path) {
            try await tool.execute(arguments: [
                "patch": """
                *** Add File: Sources/New.swift
                let value = 1
                """
            ])
        }

        XCTAssertEqual(result.status, .error)
        XCTAssertTrue(result.error?.contains("absolute path") == true)
        XCTAssertEqual(confirmationCount, 0)
    }
}
