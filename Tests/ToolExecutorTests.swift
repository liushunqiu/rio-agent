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
