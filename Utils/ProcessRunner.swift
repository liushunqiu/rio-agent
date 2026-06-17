import Foundation
import Darwin

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
                    self.terminateProcessGroup(for: process)
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

    private func terminateProcessGroup(for process: Process) {
        let pid = process.processIdentifier
        if pid > 0 {
            terminateProcessTree(rootPID: pid, signal: SIGTERM)
        }
        process.terminate()

        timeoutQueue.asyncAfter(deadline: .now() + 1.0) {
            guard process.isRunning else { return }
            if pid > 0 {
                self.terminateProcessTree(rootPID: pid, signal: SIGKILL)
            }
            process.interrupt()
        }
    }

    private func terminateProcessTree(rootPID: pid_t, signal: Int32) {
        for childPID in childProcessIDs(of: rootPID) {
            terminateProcessTree(rootPID: childPID, signal: signal)
        }
        kill(rootPID, signal)
    }

    private func childProcessIDs(of parentPID: pid_t) -> [pid_t] {
        var processCount = proc_listallpids(nil, 0)
        guard processCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(processCount))
        processCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard processCount > 0 else { return [] }

        return pids.prefix(Int(processCount)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
            guard size == Int32(MemoryLayout<proc_bsdinfo>.stride),
                  info.pbi_ppid == parentPID else {
                return nil
            }
            return pid
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
