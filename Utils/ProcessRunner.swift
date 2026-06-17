import Foundation

private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()
    private var didResume = false
    private var didTimeout = false

    func appendOutput(_ data: Data) {
        lock.lock()
        outputData.append(data)
        lock.unlock()
    }

    func appendError(_ data: Data) {
        lock.lock()
        errorData.append(data)
        lock.unlock()
    }

    func markTimedOut() {
        lock.lock()
        didTimeout = true
        lock.unlock()
    }

    func snapshotAndMarkResumed(additionalOutput: Data, additionalError: Data) -> (output: Data, error: Data, timedOut: Bool, shouldResume: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if !additionalOutput.isEmpty {
            outputData.append(additionalOutput)
        }
        if !additionalError.isEmpty {
            errorData.append(additionalError)
        }

        let shouldResume = !didResume
        didResume = true
        return (outputData, errorData, didTimeout, shouldResume)
    }

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

class ProcessRunner {
    static let shared = ProcessRunner()
    private let timeoutQueue = DispatchQueue(label: "rio-agent.process-runner.timeout", qos: .utility)

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
            let state = ProcessRunState()

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
                    state.markTimedOut()
                    process.terminate()
                }
            }

            timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                state.appendOutput(data)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                state.appendError(data)
            }

            process.terminationHandler = { process in
                timeoutWorkItem.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOutput = outputPipe.fileHandleForReading.availableData
                let remainingError = errorPipe.fileHandleForReading.availableData
                let snapshot = state.snapshotAndMarkResumed(
                    additionalOutput: remainingOutput,
                    additionalError: remainingError
                )

                guard snapshot.shouldResume else { return }

                if snapshot.timedOut {
                    continuation.resume(throwing: ProcessError.timeout)
                } else {
                    let output = String(data: snapshot.output, encoding: .utf8) ?? ""
                    let errorOutput = String(data: snapshot.error, encoding: .utf8) ?? ""

                    let result = ProcessResult(
                        exitCode: process.terminationStatus,
                        output: output,
                        error: errorOutput
                    )

                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutWorkItem.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                if state.markResumed() {
                    continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                }
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
