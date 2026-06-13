import Foundation

class ProcessRunner {
    static let shared = ProcessRunner()

    private init() {}

    func run(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> ProcessResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command] + arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            if let workDir = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            }

            // 设置超时
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            process.terminationHandler = { process in
                timeoutWorkItem.cancel()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    output: output,
                    error: errorOutput
                )

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                timeoutWorkItem.cancel()
                continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
            }
        }
    }
}

struct ProcessResult {
    let exitCode: Int32
    let output: String
    let error: String

    var isSuccess: Bool {
        return exitCode == 0
    }
}

enum ProcessError: LocalizedError {
    case launchFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason):
            return "进程启动失败: \(reason)"
        case .timeout:
            return "进程执行超时"
        }
    }
}
