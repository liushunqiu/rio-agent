import Foundation

struct RuntimeModelRoleBuilder {
    static func singleAgentRoles(
        configuration: AIConfiguration,
        multiAgentConfig: MultiAgentConfig,
        routerConfigSet: ConfigSet?,
        isProcessing: Bool,
        usesMultiAgent: Bool,
        lastMessageRole: MessageRole?
    ) -> [AgentEngine.RuntimeModelRole] {
        var roles: [AgentEngine.RuntimeModelRole] = []

        if multiAgentConfig.router.enabled {
            let routerModel = multiAgentConfig.router.model.isEmpty
                ? configuration.executionModel
                : multiAgentConfig.router.model
            let routerProvider = routerConfigSet?.provider.displayName
                ?? configuration.executionProvider.displayName
            roles.append(AgentEngine.RuntimeModelRole(
                id: "router",
                title: "Router",
                providerName: routerProvider,
                modelName: routerModel,
                isActive: isProcessing && lastMessageRole != .assistant
            ))
        }

        roles.append(AgentEngine.RuntimeModelRole(
            id: "planning",
            title: "Planning",
            providerName: configuration.planningProvider.displayName,
            modelName: configuration.planningModel,
            isActive: isProcessing && !usesMultiAgent
        ))

        roles.append(AgentEngine.RuntimeModelRole(
            id: "execution",
            title: "Execution",
            providerName: configuration.executionProvider.displayName,
            modelName: configuration.executionModel,
            isActive: isProcessing && !usesMultiAgent
        ))

        return rolesWithModelNames(roles)
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
}
