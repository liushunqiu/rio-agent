import Foundation

// MARK: - Unified Error System
// 统一的错误类型系统，替代分散的错误处理
// 注意：这是独立的示例代码，需要根据项目实际的 AIProvider 等类型调整

enum RioAgentError: LocalizedError {

    // MARK: - Configuration Errors

    case missingAPIKey(provider: String)
    case invalidConfiguration(reason: String)
    case configurationLoadFailed(reason: String)

    // MARK: - Tool Execution Errors

    case toolExecutionFailed(tool: String, reason: String)
    case toolTimeout(tool: String)
    case toolPermissionDenied(tool: String, reason: String)
    case missingToolParameter(tool: String, parameter: String)
    case invalidToolParameter(tool: String, parameter: String, reason: String)

    // MARK: - AI Service Errors

    case aiServiceUnavailable(provider: String)
    case aiRequestFailed(provider: String, statusCode: Int, message: String?)
    case aiResponseParsingFailed(provider: String, reason: String)
    case aiStreamingFailed(provider: String, reason: String)

    // MARK: - Multi-Agent Errors

    case taskSplitFailed(reason: String)
    case dagCyclicDependency(tasks: [UUID])
    case workerNotAvailable(workerType: String)
    case subTaskExecutionFailed(taskId: UUID, reason: String)

    // MARK: - Context Management Errors

    case contextWindowExceeded(current: Int, limit: Int)
    case messageCompactionFailed(reason: String)

    // MARK: - File System Errors

    case fileNotFound(path: String)
    case fileReadFailed(path: String, reason: String)
    case fileWriteFailed(path: String, reason: String)

    // MARK: - LocalizedError Implementation

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "缺少 API Key：\(provider)"
        case .invalidConfiguration(let reason):
            return "配置无效：\(reason)"
        case .configurationLoadFailed(let reason):
            return "加载配置失败：\(reason)"

        case .toolExecutionFailed(let tool, let reason):
            return "工具执行失败（\(tool)）：\(reason)"
        case .toolTimeout(let tool):
            return "工具执行超时：\(tool)"
        case .toolPermissionDenied(let tool, let reason):
            return "工具权限被拒绝（\(tool)）：\(reason)"
        case .missingToolParameter(let tool, let parameter):
            return "工具缺少必要参数（\(tool)）：\(parameter)"
        case .invalidToolParameter(let tool, let parameter, let reason):
            return "工具参数无效（\(tool).\(parameter)）：\(reason)"

        case .aiServiceUnavailable(let provider):
            return "AI 服务不可用：\(provider)"
        case .aiRequestFailed(let provider, let statusCode, let message):
            let msg = message ?? "未知错误"
            return "AI 请求失败（\(provider) - \(statusCode)）：\(msg)"
        case .aiResponseParsingFailed(let provider, let reason):
            return "AI 响应解析失败（\(provider)）：\(reason)"
        case .aiStreamingFailed(let provider, let reason):
            return "AI 流式响应失败（\(provider)）：\(reason)"

        case .taskSplitFailed(let reason):
            return "任务拆分失败：\(reason)"
        case .dagCyclicDependency(let tasks):
            return "检测到循环依赖：\(tasks.map { $0.uuidString.prefix(8) }.joined(separator: " -> "))"
        case .workerNotAvailable(let workerType):
            return "Worker 不可用：\(workerType)"
        case .subTaskExecutionFailed(let taskId, let reason):
            return "子任务执行失败（\(taskId.uuidString.prefix(8))）：\(reason)"

        case .contextWindowExceeded(let current, let limit):
            return "上下文窗口超限：当前 \(current) tokens，限制 \(limit) tokens"
        case .messageCompactionFailed(let reason):
            return "消息压缩失败：\(reason)"

        case .fileNotFound(let path):
            return "文件未找到：\(path)"
        case .fileReadFailed(let path, let reason):
            return "文件读取失败（\(path)）：\(reason)"
        case .fileWriteFailed(let path, let reason):
            return "文件写入失败（\(path)）：\(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "请前往 设置 → AI 配置 → \(provider) 填写 API Key"
        case .invalidConfiguration:
            return "请检查配置文件格式是否正确"
        case .configurationLoadFailed:
            return "尝试删除配置文件并重新配置"

        case .toolExecutionFailed(let tool, _):
            return "请检查 \(tool) 工具的参数是否正确"
        case .toolTimeout:
            return "尝试简化操作或增加超时时间"
        case .toolPermissionDenied:
            return "请确认操作权限，或使用不同的工具"
        case .missingToolParameter:
            return "请提供完整的工具参数"
        case .invalidToolParameter:
            return "请检查参数格式和取值范围"

        case .aiServiceUnavailable:
            return "请检查网络连接和 API Key 配置"
        case .aiRequestFailed(_, let statusCode, _):
            if statusCode == 401 {
                return "API Key 无效或已过期，请重新配置"
            } else if statusCode == 429 {
                return "请求频率超限，请稍后重试"
            }
            return "请稍后重试或联系服务提供商"
        case .aiResponseParsingFailed:
            return "可能是模型返回了非标准格式，请尝试其他模型"
        case .aiStreamingFailed:
            return "请检查网络连接，或切换到非流式模式"

        case .taskSplitFailed:
            return "尝试简化任务描述，或切换到单 Agent 模式"
        case .dagCyclicDependency:
            return "请检查任务依赖关系，确保没有循环"
        case .workerNotAvailable:
            return "请在 Multi-Agent 设置中启用相应的 Worker"
        case .subTaskExecutionFailed:
            return "检查子任务的具体错误信息并修复"

        case .contextWindowExceeded:
            return "使用 /compact 命令压缩对话历史，或开始新对话"
        case .messageCompactionFailed:
            return "尝试手动删除部分历史消息"

        case .fileNotFound:
            return "使用 find_files 工具搜索文件，或检查路径是否正确"
        case .fileReadFailed:
            return "检查文件权限和编码格式"
        case .fileWriteFailed:
            return "检查磁盘空间和写入权限"
        }
    }

    var failureReason: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 API 密钥"
        case .toolTimeout:
            return "操作执行时间超过限制"
        case .dagCyclicDependency:
            return "DAG 中存在循环依赖"
        case .contextWindowExceeded:
            return "消息总 token 数超过模型上下文窗口"
        default:
            return nil
        }
    }
}

// MARK: - Error Conversion Extensions
// 提供从旧版错误类型转换的便利方法（如果需要）

extension RioAgentError {
    /// 创建通用的工具执行错误
    static func toolError(_ tool: String, _ reason: String) -> RioAgentError {
        return .toolExecutionFailed(tool: tool, reason: reason)
    }

    /// 创建通用的 AI 服务错误
    static func aiError(_ provider: String, statusCode: Int, message: String? = nil) -> RioAgentError {
        return .aiRequestFailed(provider: provider, statusCode: statusCode, message: message)
    }
}


