import XCTest
@testable import RioAgent

final class ProcessRunnerTests: XCTestCase {
    func testTimeoutTerminatesChildProcesses() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-process-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let marker = tempDir.appendingPathComponent("child-survived.txt")
        let command = "(sleep 0.8; touch '\(marker.path)') & wait"

        do {
            _ = try await ProcessRunner.shared.run(
                command: command,
                workingDirectory: tempDir.path,
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch ProcessError.timeout {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
    }
}
