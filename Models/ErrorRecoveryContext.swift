import Foundation

enum ErrorRecoveryContext: Equatable {
    case planningModel
    case executionModel
    case routerModel
    case multiAgentOrchestratorModel
    case multiAgentWorkerAssignment
    case multiAgentWorkerModel

    var recoveryActionTitle: String {
        switch self {
        case .planningModel:
            return "前往 AI 配置修复规划模型"
        case .executionModel:
            return "前往 AI 配置修复执行模型"
        case .routerModel:
            return "前往 Multi-Agent 修复 Router"
        case .multiAgentOrchestratorModel:
            return "前往 Multi-Agent 修复编排器"
        case .multiAgentWorkerAssignment:
            return "前往 Multi-Agent 分配 Worker"
        case .multiAgentWorkerModel:
            return "前往 Multi-Agent 修复 Worker 模型"
        }
    }

    var recoveryActionDetail: String {
        switch self {
        case .planningModel:
            return "打开 设置 → AI 配置，补全规划模型的端点、模型标识或 API Key。"
        case .executionModel:
            return "打开 设置 → AI 配置，补全执行模型的端点、模型标识或 API Key。"
        case .routerModel:
            return "打开 设置 → Multi-Agent → 路由配置，检查 Router 绑定的模型、端点和提示词。"
        case .multiAgentOrchestratorModel:
            return "打开 设置 → Multi-Agent → 主 Agent，为编排器选择一个可用模型配置。"
        case .multiAgentWorkerAssignment:
            return "打开 设置 → Multi-Agent → 子 Agent 池，启用至少一个 Worker 并完成分配。"
        case .multiAgentWorkerModel:
            return "打开 设置 → Multi-Agent → 子 Agent 池，为失败的 Worker 绑定一个可用模型配置。"
        }
    }
}
