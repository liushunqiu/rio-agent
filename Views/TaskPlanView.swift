import SwiftUI

struct TaskPlanView: View {
    let plan: TaskPlan

    private var completedCount: Int {
        plan.subTasks.filter { $0.status == .completed }.count
    }

    private var runningCount: Int {
        plan.subTasks.filter { $0.status == .running }.count
    }

    private var failedCount: Int {
        plan.subTasks.filter { $0.status == .failed }.count
    }

    private var cancelledCount: Int {
        plan.subTasks.filter { $0.status == .cancelled }.count
    }

    private var verifiedCount: Int {
        plan.subTasks.filter { $0.verificationStatus == .verified }.count
    }

    private var unverifiedCount: Int {
        plan.subTasks.filter { $0.verificationStatus == .unverified }.count
    }

    private var needsAttentionCount: Int {
        plan.subTasks.filter(\.needsAttention).count
    }

    private var nextAttentionSummary: String? {
        if let failedSubTask = plan.subTasks.first(where: { $0.status == .failed }) {
            return "先处理失败子任务“\(failedSubTask.description)”，优先查看失败原因和恢复提示。"
        }

        if let blockedSubTask = plan.subTasks.first(where: { $0.recoveryContext == .multiAgentWorkerAssignment }) {
            return "子任务“\(blockedSubTask.description)”还没有可执行 Worker，先补齐分配再继续。"
        }

        if let retrySubTask = plan.subTasks.first(where: { $0.verificationStatus == .needsRetry }) {
            return "子任务“\(retrySubTask.description)”需要重新验证，先根据验证摘要修订结果。"
        }

        if let unverifiedSubTask = plan.subTasks.first(where: { $0.verificationStatus == .unverified }) {
            return "子任务“\(unverifiedSubTask.description)”还缺少完成证据，建议优先补充读回、测试或命令验证。"
        }

        if let cancelledSubTask = plan.subTasks.first(where: { $0.status == .cancelled }) {
            return "子任务“\(cancelledSubTask.description)”已停止，确认是否需要恢复执行。"
        }

        return nil
    }

    private var nextAttentionTone: Color {
        if plan.subTasks.contains(where: { $0.status == .failed }) {
            return Theme.statusError
        }
        if plan.subTasks.contains(where: { $0.recoveryContext == .multiAgentWorkerAssignment }) {
            return Theme.statusWarning
        }
        if plan.subTasks.contains(where: { $0.verificationStatus == .needsRetry }) {
            return Theme.statusWarning
        }
        if plan.subTasks.contains(where: { $0.verificationStatus == .unverified }) {
            return Theme.statusWarning
        }
        if plan.subTasks.contains(where: { $0.status == .cancelled }) {
            return Theme.textTertiary
        }
        return Theme.accentSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accentPrimary)

                Text("Multi-Agent 任务计划")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                DarkStatusBadge(status: plan.status)
            }

            Divider().overlay(Theme.borderSubtle)

            if !plan.subTasks.isEmpty {
                HStack(spacing: 8) {
                    TaskPlanMetricChip(
                        title: "已完成",
                        value: "\(completedCount)/\(plan.subTasks.count)",
                        tone: Theme.statusSuccess
                    )
                    TaskPlanMetricChip(
                        title: "执行中",
                        value: "\(runningCount)",
                        tone: Theme.statusInfo
                    )

                    if failedCount > 0 {
                        TaskPlanMetricChip(
                            title: "失败",
                            value: "\(failedCount)",
                            tone: Theme.statusError
                        )
                    }

                    if needsAttentionCount > 0 {
                        TaskPlanMetricChip(
                            title: "待处理",
                            value: "\(needsAttentionCount)",
                            tone: Theme.statusWarning
                        )
                    }

                    if unverifiedCount > 0 {
                        TaskPlanMetricChip(
                            title: "待验证",
                            value: "\(unverifiedCount)",
                            tone: Theme.statusWarning
                        )
                    }

                    if cancelledCount > 0 {
                        TaskPlanMetricChip(
                            title: "已停止",
                            value: "\(cancelledCount)",
                            tone: Theme.textTertiary
                        )
                    }

                    TaskPlanMetricChip(
                        title: "已验证",
                        value: "\(verifiedCount)",
                        tone: Theme.accentSecondary
                    )
                }

                if let nextAttentionSummary {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(nextAttentionTone)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("优先处理")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(nextAttentionSummary)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(nextAttentionTone.opacity(0.08))
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(nextAttentionTone.opacity(0.18), lineWidth: 1)
                    )
                }
            }

            // Original task
            VStack(alignment: .leading, spacing: 4) {
                Text("原始任务")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)

                Text(plan.originalTask)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgInput)
                    .cornerRadius(Theme.radiusSM)
            }

            // Sub-tasks
            if !plan.subTasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("子任务 (\(plan.subTasks.count))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(plan.subTasks) { subTask in
                        DarkSubTaskRow(subTask: subTask)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.accentPrimary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Status Badge

struct DarkStatusBadge: View {
    let status: TaskPlanStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 9))
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .foregroundColor(statusColor)
        .cornerRadius(Theme.radiusSM)
    }

    private var statusIcon: String {
        switch status {
        case .planning: return "doc.text"
        case .executing: return "gear"
        case .synthesizing: return "arrow.triangle.merge"
        case .verifying: return "checkmark.shield"
        case .completed: return "checkmark"
        case .cancelled: return "slash.circle"
        case .failed: return "xmark"
        }
    }

    private var statusText: String {
        switch status {
        case .planning: return "规划中"
        case .executing: return "执行中"
        case .synthesizing: return "汇总中"
        case .verifying: return "验证中"
        case .completed: return "已完成"
        case .cancelled: return "已停止"
        case .failed: return "失败"
        }
    }

    private var statusColor: Color {
        switch status {
        case .planning: return Theme.statusInfo
        case .executing: return Theme.statusWarning
        case .synthesizing: return Theme.accentPrimary
        case .verifying: return Theme.accentSecondary
        case .completed: return Theme.statusSuccess
        case .cancelled: return Theme.textTertiary
        case .failed: return Theme.statusError
        }
    }
}

// Legacy alias
struct StatusBadge: View {
    let status: TaskPlanStatus
    var body: some View { DarkStatusBadge(status: status) }
}

struct TaskPlanMetricChip: View {
    let title: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tone.opacity(0.08))
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - SubTask Row

struct DarkSubTaskRow: View {
    let subTask: SubTask

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundColor(statusColor)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(subTask.description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(3)

                if let worker = subTask.assignedWorker {
                    HStack(spacing: 6) {
                        Label(worker.name, systemImage: workerIcon(worker))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textSecondary)

                        Text(worker.capability.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Theme.accentPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accentPrimary.opacity(0.12))
                            .cornerRadius(Theme.radiusSM)

                        Text(worker.model)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("未分配执行 Agent")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.statusWarning)
                }

                if let reason = subTask.assignmentReason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(2)
                }

                if subTask.retryCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                        Text("重试 \(subTask.retryCount) 次")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Theme.statusWarning)
                }

                HStack(spacing: 6) {
                    Image(systemName: verificationIcon)
                        .font(.system(size: 9, weight: .semibold))
                    Text(subTask.verificationStatus.displayText)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(verificationColor)

                if let attentionSummary {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(attentionColor)
                            .padding(.top, 1)

                        Text(attentionSummary)
                            .font(.system(size: 10))
                            .foregroundColor(attentionColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(attentionColor.opacity(0.08))
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(attentionColor.opacity(0.18), lineWidth: 1)
                    )
                }

                if let summary = subTask.verificationSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(verificationSummaryColor)
                        .lineLimit(2)
                }

                if let resultText {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(resultLabel, systemImage: resultIcon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(resultColor)

                        Text(resultText)
                            .font(.system(size: 10))
                            .foregroundColor(resultColor)
                            .lineLimit(resultLineLimit)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(resultColor.opacity(0.08))
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(resultColor.opacity(0.16), lineWidth: 1)
                    )
                }
            }

            Spacer()

            if resultText != nil {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .help(resultText ?? "")
            }
        }
        .padding(8)
        .background(Theme.bgTertiary)
        .cornerRadius(Theme.radiusSM)
    }

    private func workerIcon(_ worker: AgentConfig) -> String {
        switch worker.capability {
        case .search: return "magnifyingglass"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .file: return "doc.text"
        case .general: return "person.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    private var statusIcon: String {
        switch subTask.status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch subTask.status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .cancelled: return Theme.textTertiary
        case .failed: return Theme.statusError
        }
    }

    private var verificationIcon: String {
        switch subTask.verificationStatus {
        case .unverified: return "questionmark.circle"
        case .verified: return "checkmark.shield"
        case .needsRetry: return "exclamationmark.triangle"
        }
    }

    private var verificationColor: Color {
        switch subTask.verificationStatus {
        case .unverified: return Theme.statusWarning
        case .verified: return Theme.statusSuccess
        case .needsRetry: return Theme.statusWarning
        }
    }

    private var verificationSummaryColor: Color {
        switch subTask.verificationStatus {
        case .verified:
            return Theme.textTertiary
        case .unverified:
            return Theme.statusWarning
        case .needsRetry:
            return Theme.statusError
        }
    }

    private var resultText: String? {
        guard let result = subTask.result?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }
        return result
    }

    private var resultLabel: String {
        switch subTask.status {
        case .failed: return "失败原因"
        case .cancelled: return "停止原因"
        case .completed: return "结果摘要"
        case .running: return "执行输出"
        case .pending: return "待处理"
        }
    }

    private var resultIcon: String {
        switch subTask.status {
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle.fill"
        case .completed: return "doc.text.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .pending: return "clock"
        }
    }

    private var resultColor: Color {
        switch subTask.status {
        case .failed: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        case .completed: return Theme.textSecondary
        case .running: return Theme.statusInfo
        case .pending: return Theme.textTertiary
        }
    }

    private var resultLineLimit: Int? {
        subTask.status == .failed ? nil : 3
    }

    private var attentionSummary: String? {
        switch subTask.recoveryContext {
        case .planningModel?:
            return ErrorRecoveryContext.planningModel.recoveryActionDetail
        case .executionModel?:
            return ErrorRecoveryContext.executionModel.recoveryActionDetail
        case .routerModel?:
            return ErrorRecoveryContext.routerModel.recoveryActionDetail
        case .multiAgentOrchestratorModel?:
            return ErrorRecoveryContext.multiAgentOrchestratorModel.recoveryActionDetail
        case .multiAgentWorkerAssignment?:
            return ErrorRecoveryContext.multiAgentWorkerAssignment.recoveryActionDetail
        case .multiAgentWorkerModel?:
            return ErrorRecoveryContext.multiAgentWorkerModel.recoveryActionDetail
        case .none:
            if subTask.status == .failed || subTask.verificationStatus == .needsRetry {
                return "该子任务需要人工关注，建议先查看失败原因和验证摘要。"
            }
            if subTask.verificationStatus == .unverified {
                return "该子任务还缺少足够的完成证据，建议补充读回、测试或命令验证。"
            }
            return nil
        }
    }

    private var attentionColor: Color {
        switch subTask.recoveryContext {
        case .multiAgentWorkerAssignment, .multiAgentWorkerModel, .multiAgentOrchestratorModel, .executionModel, .planningModel:
            return Theme.statusWarning
        case .routerModel:
            return Theme.accentSecondary
        case .none:
            return Theme.statusWarning
        }
    }
}

struct SubTaskRow: View {
    let subTask: SubTask
    var body: some View { DarkSubTaskRow(subTask: subTask) }
}
