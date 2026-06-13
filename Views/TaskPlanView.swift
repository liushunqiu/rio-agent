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
        case .completed: return "checkmark"
        case .failed: return "xmark"
        }
    }

    private var statusText: String {
        switch status {
        case .planning: return "规划中"
        case .executing: return "执行中"
        case .synthesizing: return "汇总中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    private var statusColor: Color {
        switch status {
        case .planning: return Theme.statusInfo
        case .executing: return Theme.statusWarning
        case .synthesizing: return Theme.accentPrimary
        case .completed: return Theme.statusSuccess
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
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundColor(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(subTask.description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)

                if let worker = subTask.assignedWorker {
                    Text(worker.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
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

    private var statusIcon: String {
        switch subTask.status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch subTask.status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        }
    }
}

struct SubTaskRow: View {
    let subTask: SubTask
    var body: some View { DarkSubTaskRow(subTask: subTask) }
}
