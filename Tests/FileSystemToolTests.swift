import XCTest
@testable import RioAgent

final class FileSystemToolTests: XCTestCase {
    func testFindFilesSkipsGeneratedAndDependencyDirectories() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write("keep", to: tempDir.appendingPathComponent("Sources/App/Keep.swift"))
        try write("skip", to: tempDir.appendingPathComponent(".git/Hidden.swift"))
        try write("skip", to: tempDir.appendingPathComponent(".build/Generated.swift"))
        try write("skip", to: tempDir.appendingPathComponent("DerivedData/App/Generated.swift"))
        try write("skip", to: tempDir.appendingPathComponent(".venv/lib/Generated.swift"))
        try write("skip", to: tempDir.appendingPathComponent("dist/Generated.swift"))
        try write("skip", to: tempDir.appendingPathComponent("node_modules/Package.swift"))

        let result = try await FindFilesTool().execute(arguments: [
            "path": tempDir.path,
            "pattern": "*.swift"
        ])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("Keep.swift"))
        XCTAssertFalse(result.output.contains("Hidden.swift"))
        XCTAssertFalse(result.output.contains("Generated.swift"))
        XCTAssertFalse(result.output.contains("Package.swift"))
    }

    func testFindFilesSupportsRecursivePathGlob() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write("match", to: tempDir.appendingPathComponent("Sources/App/Keep.swift"))
        try write("no", to: tempDir.appendingPathComponent("Tests/App/KeepTests.swift"))

        let result = try await FindFilesTool().execute(arguments: [
            "path": tempDir.path,
            "pattern": "Sources/**/*.swift"
        ])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("Sources/App/Keep.swift"))
        XCTAssertFalse(result.output.contains("Tests/App/KeepTests.swift"))
    }

    func testFindFilesKeepsUsableMatchesWhenOneDirectoryCannotBeRead() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        let blockedDir = tempDir.appendingPathComponent("Blocked", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        try write("match", to: tempDir.appendingPathComponent("Sources/App/Keep.swift"))
        try write("hidden", to: blockedDir.appendingPathComponent("Hidden.swift"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedDir.path)

        let result = try await FindFilesTool().execute(arguments: [
            "path": tempDir.path,
            "pattern": "*.swift"
        ])

        guard result.output.contains("部分目录无法读取") else {
            throw XCTSkip("Current filesystem did not report a traversal error for a chmod 000 directory.")
        }

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("Keep.swift"))
        XCTAssertFalse(result.output.contains("Hidden.swift"))
    }

    func testSearchFilesHonorsFilePatternAndLineNumbers() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let swiftFile = tempDir.appendingPathComponent("Sources/App/Main.swift")
        let textFile = tempDir.appendingPathComponent("notes.txt")
        try write("first\nlet targetValue = 1\nlast", to: swiftFile)
        try write("targetValue in notes", to: textFile)

        let result = try await SearchFilesTool().execute(arguments: [
            "path": tempDir.path,
            "pattern": "targetValue",
            "file_pattern": "*.swift"
        ])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("\(swiftFile.path):2:let targetValue = 1"))
        XCTAssertFalse(result.output.contains("notes.txt"))
    }

    func testSearchFilesCanSearchSingleFilePath() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("Main.swift")
        try write("let targetValue = 1", to: file)

        let result = try await SearchFilesTool().execute(arguments: [
            "path": file.path,
            "pattern": "targetValue"
        ])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("\(file.path):1:let targetValue = 1"))
    }

    func testSearchFilesSurfacesUnreadableFileDiagnostics() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let readableFile = tempDir.appendingPathComponent("Readable.swift")
        let invalidUTF8File = tempDir.appendingPathComponent("Binary.swift")
        try write("let targetValue = 1", to: readableFile)
        try FileManager.default.createDirectory(
            at: invalidUTF8File.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xff, 0xfe, 0xfd]).write(to: invalidUTF8File)

        let result = try await SearchFilesTool().execute(arguments: [
            "path": tempDir.path,
            "pattern": "targetValue",
            "file_pattern": "*.swift"
        ])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("\(readableFile.path):1:let targetValue = 1"))
        XCTAssertTrue(result.output.contains("部分文件无法读取"))
        XCTAssertTrue(result.output.contains(invalidUTF8File.path))
    }

    func testListDirectoryProducesStableNativeListing() async throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write("b", to: tempDir.appendingPathComponent("b.txt"))
        try write("a", to: tempDir.appendingPathComponent("a.txt"))

        let result = try await ListDirectoryTool().execute(arguments: ["path": tempDir.path])

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("Directory: \(tempDir.path)"))
        XCTAssertLessThan(
            result.output.range(of: "a.txt")?.lowerBound ?? result.output.endIndex,
            result.output.range(of: "b.txt")?.lowerBound ?? result.output.startIndex
        )
    }

    private func makeTemporaryWorkingDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
