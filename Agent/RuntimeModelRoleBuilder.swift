import Foundation

struct RuntimeModelRoleBuilder {
    static func singleAgentRoles(
        configuration: AIConfiguration,
        multiAgentConfig: MultiAgentConfig,
        routerConfigSet: ConfigSet?,
        isProcessing: Bool,
        usesMultiAgent: Bool,
        currentPipeline: ExecutionPipeline?,
        lastMessageRole: MessageRole?
    ) -> [AgentEngine.RuntimeModelRole] {
        var roles: [AgentEngine.RuntimeModelRole] = []
        let activeRole = singleAgentActiveRole(
            isProcessing: isProcessing,
            usesMultiAgent: usesMultiAgent,
            currentPipeline: currentPipeline,
            lastMessageRole: lastMessageRole
        )

        if multiAgentConfig.router.enabled {
            let routerRole = routerRuntimeRole(
                configuration: configuration,
                multiAgentConfig: multiAgentConfig,
                routerConfigSet: routerConfigSet,
                isActive: activeRole == .router
            )
            roles.append(routerRole)
        }

        roles.append(AgentEngine.RuntimeModelRole(
            id: "planning",
            title: "Planning",
            providerName: configuration.planningProvider.displayName,
            modelName: configuration.planningModel,
            isActive: activeRole == .planning
        ))

        roles.append(AgentEngine.RuntimeModelRole(
            id: "execution",
            title: "Execution",
            providerName: configuration.executionProvider.displayName,
            modelName: configuration.executionModel,
            isActive: activeRole == .execution
        ))

        return rolesWithModelNames(roles)
    }

    private static func routerRuntimeRole(
        configuration: AIConfiguration,
        multiAgentConfig: MultiAgentConfig,
        routerConfigSet: ConfigSet?,
        isActive: Bool
    ) -> AgentEngine.RuntimeModelRole {
        if multiAgentConfig.router.enableQwenRouter {
            return AgentEngine.RuntimeModelRole(
                id: "router",
                title: "Qwen Router",
                providerName: "Qwen / vLLM",
                modelName: multiAgentConfig.router.qwenModel,
                isActive: isActive
            )
        }

        guard let routerConfigSet else {
            return AgentEngine.RuntimeModelRole(
                id: "router",
                title: "Router",
                providerName: "未配置",
                modelName: "未选择模型配置",
                isActive: isActive
            )
        }

        let configuredModel = multiAgentConfig.router.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let routerModel = configuredModel.isEmpty ? routerConfigSet.model : configuredModel
        return AgentEngine.RuntimeModelRole(
            id: "router",
            title: "Router",
            providerName: routerConfigSet.provider.displayName,
            modelName: routerModel,
            isActive: isActive
        )
    }

    static func multiAgentRoles(
        config: MultiAgentConfig,
        plan: TaskPlan?
    ) -> [AgentEngine.RuntimeModelRole] {
        var activeIds = Set<String>()
        if let plan {
            switch plan.status {
            case .planning, .synthesizing, .verifying:
                activeIds.insert("orchestrator")
            case .executing:
                let runningWorkers = plan.subTasks.compactMap { subTask -> String? in
                    guard subTask.status == .running, let worker = subTask.assignedWorker else { return nil }
                    return "worker-\(worker.id.uuidString)"
                }
                if runningWorkers.isEmpty {
                    activeIds.insert("orchestrator")
                } else {
                    runningWorkers.forEach { activeIds.insert($0) }
                }
            case .completed, .cancelled, .failed:
                break
            }
        }

        var roles: [AgentEngine.RuntimeModelRole] = [
            AgentEngine.RuntimeModelRole(
                id: "orchestrator",
                title: "Orchestrator",
                providerName: config.orchestrator.provider.displayName,
                modelName: config.orchestrator.model,
                isActive: activeIds.contains("orchestrator")
            )
        ]

        for worker in config.workers where worker.isEnabled {
            roles.append(AgentEngine.RuntimeModelRole(
                id: "worker-\(worker.id.uuidString)",
                title: worker.name,
                providerName: worker.provider.displayName,
                modelName: worker.model,
                isActive: activeIds.contains("worker-\(worker.id.uuidString)")
            ))
        }

        return rolesWithModelNames(roles)
    }

    private static func rolesWithModelNames(_ roles: [AgentEngine.RuntimeModelRole]) -> [AgentEngine.RuntimeModelRole] {
        roles.filter { !$0.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private enum SingleAgentActiveRole {
        case router
        case planning
        case execution
    }

    private static func singleAgentActiveRole(
        isProcessing: Bool,
        usesMultiAgent: Bool,
        currentPipeline: ExecutionPipeline?,
        lastMessageRole: MessageRole?
    ) -> SingleAgentActiveRole? {
        guard isProcessing, !usesMultiAgent else { return nil }

        if let stage = currentPipeline?.currentStage {
            switch stage.type {
            case .router:
                return .router
            case .taskAnalysis, .dagPlanning:
                return .planning
            case .execution, .errorRecovery, .verification, .synthesis:
                return .execution
            }
        }

        return lastMessageRole == .assistant ? .execution : .planning
    }
}
