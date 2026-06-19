import XCTest
@testable import RioAgent

final class ToolExecutorTests: XCTestCase {
    @MainActor
    func testReadOnlyToolCallsRunConcurrentlyAndPreserveResultOrder() async throws {
        let registry = ToolRegistry(tools: [
            DelayedReadOnlyTool(name: "read_file", delayNanoseconds: 250_000_000),
            DelayedReadOnlyTool(name: "search_files", delayNanoseconds: 250_000_000)
        ])
        let executor = ToolExecutor(toolRegistry: registry, memory: AgentMemory())

        let start = Date()
        let results = await executor.executeToolCalls([
            ToolCall(id: "first", name: "read_file"),
            ToolCall(id: "second", name: "search_files")
        ])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.map(\.toolCallId), ["first", "second"])
        XCTAssertLessThan(elapsed, 0.45)
    }

    @MainActor
    func testReadOnlyToolCompletionStateIsPublishedAsEachToolFinishes() async throws {
        let registry = ToolRegistry(tools: [
            DelayedReadOnlyTool(name: "read_file", delayNanoseconds: 250_000_000),
            DelayedReadOnlyTool(name: "search_files", delayNanoseconds: 40_000_000)
        ])
        let executor = ToolExecutor(toolRegistry: registry, memory: AgentMemory())
        var completedToolIds: [String] = []

        executor.onExecutionStateChanged = { state in
            if case .completed(let toolCall, _) = state {
                completedToolIds.append(toolCall.id)
            }
        }

        let results = await executor.executeToolCalls([
            ToolCall(id: "slow", name: "read_file"),
            ToolCall(id: "fast", name: "search_files")
        ])

        XCTAssertEqual(results.map(\.toolCallId), ["slow", "fast"])
        XCTAssertEqual(completedToolIds, ["fast", "slow"])
    }

    @MainActor
    func testCancellationErrorReturnsCancelledToolResult() async throws {
        let registry = ToolRegistry(tools: [
            CancellingTool(name: "execute_command")
        ])
        let executor = ToolExecutor(toolRegistry: registry, memory: AgentMemory())

        let results = await executor.executeToolCalls([
            ToolCall(id: "cancelled-command", name: "execute_command")
        ])

        XCTAssertEqual(results.first?.toolCallId, "cancelled-command")
        XCTAssertEqual(results.first?.status, .cancelled)
        XCTAssertEqual(results.first?.error, "任务已取消")
    }

    @MainActor
    func testToolExecutionContextExposesCurrentToolCallDuringExecution() async throws {
        let contextTool = ContextCapturingTool(name: "execute_command")
        let registry = ToolRegistry(tools: [contextTool])
        let executor = ToolExecutor(toolRegistry: registry, memory: AgentMemory())

        let results = await executor.executeToolCalls([
            ToolCall(id: "context-command", name: "execute_command")
        ])

        XCTAssertEqual(results.first?.status, .success)
        XCTAssertEqual(contextTool.capturedToolCallId, "context-command")
    }

    @MainActor
    func testSequentialToolExecutionSkipsRemainingToolsAfterCancellation() async throws {
        let followUpTool = CountingTool(name: "write_file")
        let registry = ToolRegistry(tools: [
            CancellingTool(name: "execute_command"),
            followUpTool
        ])
        let executor = ToolExecutor(toolRegistry: registry, memory: AgentMemory())
        var completedToolIds: [String] = []

        executor.onExecutionStateChanged = { state in
            if case .completed(let toolCall, _) = state {
                completedToolIds.append(toolCall.id)
            }
        }

        let results = await executor.executeToolCalls([
            ToolCall(id: "cancelled-command", name: "execute_command"),
            ToolCall(id: "skipped-write", name: "write_file")
        ])

        XCTAssertEqual(results.map(\.toolCallId), ["cancelled-command", "skipped-write"])
        XCTAssertEqual(results.map(\.status), [.cancelled, .cancelled])
        XCTAssertEqual(results[1].error, "任务已取消，后续工具未执行")
        XCTAssertEqual(followUpTool.executionCount, 0)
        XCTAssertEqual(completedToolIds, ["cancelled-command", "skipped-write"])
    }
}

private struct DelayedReadOnlyTool: Tool {
    let name: String
    let delayNanoseconds: UInt64
    let description = "Delayed test tool"
    let parameters: [String: ToolParameter] = [:]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return ToolResult.success(toolCallId: name, output: name)
    }
}

private struct CancellingTool: Tool {
    let name: String
    let description = "Cancelling test tool"
    let parameters: [String: ToolParameter] = [:]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        throw CancellationError()
    }
}

private final class CountingTool: Tool {
    let name: String
    let description = "Counting test tool"
    let parameters: [String: ToolParameter] = [:]
    private(set) var executionCount = 0

    init(name: String) {
        self.name = name
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        executionCount += 1
        return ToolResult.success(toolCallId: name, output: name)
    }
}

private final class ContextCapturingTool: Tool {
    let name: String
    let description = "Context capturing test tool"
    let parameters: [String: ToolParameter] = [:]
    private(set) var capturedToolCallId: String?

    init(name: String) {
        self.name = name
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        capturedToolCallId = ToolExecutionContext.currentToolCall?.id
        return ToolResult.success(toolCallId: name, output: name)
    }
}
