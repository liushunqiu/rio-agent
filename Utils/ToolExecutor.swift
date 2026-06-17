import Foundation

// MARK: - Tool Executor
// 工具执行模块，负责工具调用的执行和状态管理

/// 工具执行器 - 管理工具调用的执行流程和错误处理
class ToolExecutor {

    // MARK: - Types

    /// 最近错误记录
    struct RecentError {
        let toolName: String
        let error: String
        let timestamp: Date
    }

    // MARK: - Properties

    private let toolRegistry: ToolRegistry
    private let memory: AgentMemory

    /// 最近的错误列表（用于模式检测）
    private(set) var recentErrors: [RecentError] = []

    /// 最大保留的错误数
    private let maxRecentErrors = 10

    // MARK: - State Management

    /// 当前执行状态的回调
    var onExecutionStateChanged: ((ToolExecutionState?) -> Void)?

    // MARK: - Initialization

    init(toolRegistry: ToolRegistry, memory: AgentMemory) {
        self.toolRegistry = toolRegistry
        self.memory = memory
    }

    // MARK: - Public Methods

    /// 执行工具调用列表
    func executeToolCalls(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        var results: [ToolResult] = []

        for toolCall in toolCalls {
            // 通知开始执行
            notifyStateChange(.pending(toolCall: toolCall))
            await Task.yield()

            notifyStateChange(.executing(toolCall: toolCall))

            // 执行工具
            let result = await executeSingleTool(toolCall)

            // 记录结果
            await recordToolExecution(toolCall: toolCall, result: result)

            notifyStateChange(.completed(toolCall: toolCall, result: result))

            results.append(result)
        }

        notifyStateChange(nil)
        return results
    }

    /// 检查是否存在连续错误模式
    func hasConsecutiveErrors(threshold: Int = 2) -> Bool {
        guard recentErrors.count >= threshold else { return false }

        let recentErrorNames = recentErrors.suffix(threshold).map { $0.toolName }
        return Set(recentErrorNames).count == 1 // 同一个工具连续失败
    }

    /// 获取最近的错误分析
    func getRecentErrorAnalysis() -> String? {
        guard let lastError = recentErrors.last else { return nil }

        let analysis = "Recent error in \(lastError.toolName): \(lastError.error)\n"

        // 注意：由于 actor 隔离，我们无法同步访问 memory.findSimilarErrors
        // 这部分功能需要在 MainActor 上下文中异步调用

        return analysis
    }

    /// 清除错误历史
    func clearErrorHistory() {
        recentErrors.removeAll()
    }

    // MARK: - Private Methods

    /// 执行单个工具调用
    private func executeSingleTool(_ toolCall: ToolCall) async -> ToolResult {
        do {
            let raw = try await toolRegistry.executeTool(
                name: toolCall.name,
                arguments: toolCall.arguments.mapValues { $0.value }
            )
            return ToolResult(
                toolCallId: toolCall.id,
                status: raw.status,
                output: raw.output,
                error: raw.error
            )
        } catch {
            return ToolResult.error(toolCallId: toolCall.id, error: error.localizedDescription)
        }
    }

    /// 记录工具执行结果
    private func recordToolExecution(toolCall: ToolCall, result: ToolResult) async {
        let taskType = await MainActor.run {
            ToolRecommender.classifyTask(memory.session.currentTask ?? "")
        }

        // 记录错误
        if result.status == .error {
            let error = RecentError(
                toolName: toolCall.name,
                error: result.error ?? "Unknown error",
                timestamp: Date()
            )
            recentErrors.append(error)

            // 保持最近 N 个错误
            if recentErrors.count > maxRecentErrors {
                recentErrors.removeFirst()
            }

            await MainActor.run {
                memory.recordErrorPattern(
                    error: error.error,
                    context: "Tool: \(toolCall.name), Args: \(toolCall.arguments)",
                    solution: ""
                )
            }
        }

        await MainActor.run {
            memory.recordToolUsage(toolCall.name)

            // 记录文件访问
            if let path = toolCall.arguments["path"]?.value as? String {
                memory.recordFileAccess(path)
            }

            // 记录成功模式
            if result.status == .success {
                memory.recordSuccessfulPattern(taskType: "\(taskType)", tool: toolCall.name)
            }

            // 记录到 ToolRecommender
            ToolRecommender.recordToolUsage(
                tool: toolCall.name,
                taskType: taskType,
                success: result.status == .success,
                executionTime: 0
            )
        }
    }

    /// 通知状态变化
    private func notifyStateChange(_ state: ToolExecutionState?) {
        onExecutionStateChanged?(state)
    }

    /// 生成错误反思提示
    func generateErrorReflection(toolCall: ToolCall, result: ToolResult) -> String {
        guard result.status == .error else { return "" }

        let errorMsg = result.error ?? "Unknown error"
        var reflection = "\n\n[Error Analysis for \(toolCall.name)]\n"
        reflection += "Error: \(errorMsg)\n"

        // 注意：由于 actor 隔离，我们无法同步访问 memory.findSimilarErrors
        // 这个方法需要在 MainActor 上下文中调用，或者异步执行
        // 为了保持简单，我们先跳过历史错误检查

        // 生成工具特定建议
        let suggestion = generateToolSpecificSuggestion(
            toolName: toolCall.name,
            error: errorMsg,
            arguments: toolCall.arguments
        )
        if !suggestion.isEmpty {
            reflection += "\n💡 Suggestion: \(suggestion)\n"
        }

        return reflection
    }

    /// 生成工具特定的错误建议
    private func generateToolSpecificSuggestion(
        toolName: String,
        error: String,
        arguments: [String: AnyCodable]
    ) -> String {
        let errorLower = error.lowercased()

        switch toolName {
        case "read_file", "write_file", "edit_file":
            if errorLower.contains("no such file") || errorLower.contains("not found") {
                if let path = arguments["path"]?.value as? String {
                    return "File '\(path)' not found. Use find_files to locate it or check if the path is correct."
                }
                return "File not found. Use find_files to locate the correct file path."
            }
            if errorLower.contains("permission denied") {
                return "Permission denied. The file may be outside the working directory or require special permissions."
            }

        case "execute_command":
            if errorLower.contains("command not found") {
                if let command = arguments["command"]?.value as? String {
                    return "Command '\(command)' not found. Check if the tool is installed or use a different command."
                }
            }
            if errorLower.contains("permission denied") {
                return "Permission denied. This command may be classified as dangerous and requires user confirmation."
            }

        case "search_files":
            if errorLower.contains("invalid") && errorLower.contains("regex") {
                return "Invalid regex pattern. Try a simpler pattern or escape special characters."
            }

        default:
            break
        }

        return ""
    }
}
