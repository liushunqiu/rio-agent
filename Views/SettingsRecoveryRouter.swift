import Foundation

enum SettingsRecoveryRouter {
    static func resolve(
        error: String,
        recoveryContext: ErrorRecoveryContext?
    ) -> SettingsLaunchContext? {
        if let recoveryContext {
            return settingsLaunchContext(from: recoveryContext)
        }
        return legacySettingsLaunchContext(for: error)
    }

    static func settingsLaunchContext(from recoveryContext: ErrorRecoveryContext) -> SettingsLaunchContext {
        switch recoveryContext {
        case .planningModel:
            return .planningModel
        case .executionModel:
            return .executionModel
        case .routerModel:
            return .routerModel
        case .multiAgentOrchestratorModel:
            return .multiAgentOrchestratorModel
        case .multiAgentWorkerAssignment:
            return .multiAgentWorkerAssignment
        case .multiAgentWorkerModel:
            return .multiAgentWorkerModel
        }
    }

    static func legacySettingsLaunchContext(for error: String) -> SettingsLaunchContext? {
        if shouldOpenMultiAgentSettings(for: error) {
            let multiAgentRules: [(markers: [String], context: SettingsLaunchContext)] = [
                (["router"], .routerModel),
                (["主 agent", "编排器", "orchestrator"], .multiAgentOrchestratorModel),
                (["未分配执行 agent"], .multiAgentWorkerAssignment),
                (["未选择可用模型配置", "不可用"], .multiAgentWorkerModel)
            ]

            for rule in multiAgentRules where containsAnyMarker(rule.markers, in: error) {
                return rule.context
            }

            return .multiAgentWorkerAssignment
        }

        if shouldOpenAISettings(for: error) {
            return containsAnyMarker(["规划"], in: error) ? .planningModel : .executionModel
        }

        return nil
    }

    static func shouldOpenAISettings(for error: String) -> Bool {
        containsAnyMarker(
            ["规划模型", "执行模型", "模型配置", "api key", "api 密钥", "端点", "未选择模型"],
            in: error
        )
    }

    static func shouldOpenMultiAgentSettings(for error: String) -> Bool {
        containsAnyMarker(
            ["未分配执行 agent", "设置 → multi-agent", "子 agent", "worker", "router", "主 agent", "编排器", "orchestrator"],
            in: error
        )
    }

    private static func containsAnyMarker(_ markers: [String], in error: String) -> Bool {
        let normalizedError = error.lowercased()
        return markers.contains { normalizedError.contains($0.lowercased()) }
    }
}
