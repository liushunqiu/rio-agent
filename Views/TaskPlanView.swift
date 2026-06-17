import SwiftUI

struct TaskPlanView: View {
    let plan: TaskPlan

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

                if let summary = subTask.verificationSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let result = subTask.result, subTask.status == .completed {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .help(result)
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
        case .unverified: return Theme.textTertiary
        case .verified: return Theme.statusSuccess
        case .needsRetry: return Theme.statusWarning
        }
    }
}

struct SubTaskRow: View {
    let subTask: SubTask
    var body: some View { DarkSubTaskRow(subTask: subTask) }
}
