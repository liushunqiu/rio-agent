import SwiftUI

struct TaskPlanView: View {
    let plan: TaskPlan
    let prefersCondensedCompletedState: Bool
    @State private var showAllSubTasks = false
    @State private var showCompletedPlanDetails = false

    init(
        plan: TaskPlan,
        prefersCondensedCompletedState: Bool = false
    ) {
        self.plan = plan
        self.prefersCondensedCompletedState = prefersCondensedCompletedState
    }

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

    private var prioritizedBlockedSubTask: SubTask? {
        plan.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })
    }

    private var nextAttentionSummary: String? {
        if let failedSubTask = plan.subTasks.first(where: { $0.status == .failed }) {
            return "先处理失败子任务“\(failedSubTask.description)”，优先查看失败原因和恢复提示。"
        }

        if let blockedSubTask = prioritizedBlockedSubTask,
           let recoveryContext = blockedSubTask.recoveryContext {
            return "子任务“\(blockedSubTask.description)”当前受阻，先\(recoveryContext.recoveryActionDetail)"
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
        if prioritizedBlockedSubTask != nil {
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

    private var highlightedSubTasks: [SubTask] {
        plan.subTasks.filter { subTask in
            subTask.status == .running || subTask.needsAttention || subTask.verificationStatus == .unverified
        }
    }

    private var stableSubTasks: [SubTask] {
        plan.subTasks.filter { subTask in
            subTask.status != .running && !subTask.needsAttention && subTask.verificationStatus != .unverified
        }
    }

    private var shouldCollapseStableSubTasks: Bool {
        plan.subTasks.count > 6 && stableSubTasks.count > 2
    }

    private var visibleSubTasks: [SubTask] {
        guard shouldCollapseStableSubTasks && !showAllSubTasks else {
            return plan.subTasks
        }
        return highlightedSubTasks + stableSubTasks.prefix(2)
    }

    private var hiddenSubTaskCount: Int {
        max(0, plan.subTasks.count - visibleSubTasks.count)
    }

    private var collapsedSubTaskSummary: String {
        if highlightedSubTasks.isEmpty {
            return "其余 \(hiddenSubTaskCount) 项已折叠，展开后可查看全部执行明细。"
        }
        return "其余 \(hiddenSubTaskCount) 项已折叠，当前优先展示执行中、需关注和待验证子任务。"
    }

    private var collapseToggleTitle: String {
        showAllSubTasks ? "收起稳定项" : "展开全部子任务"
    }

    private var shouldOfferCompletedSummary: Bool {
        prefersCondensedCompletedState && plan.status == .completed
    }

    private var isShowingCompletedSummary: Bool {
        shouldOfferCompletedSummary && !showCompletedPlanDetails
    }

    private var completedSummaryText: String {
        if needsAttentionCount > 0 {
            return "任务已完成汇总，但仍有 \(needsAttentionCount) 个子任务需要继续复核。主阅读流已折叠计划明细，按需展开即可继续处理。"
        }
        if unverifiedCount > 0 {
            return "任务已完成汇总，但仍有 \(unverifiedCount) 个子任务缺少验证证据。主阅读流已折叠计划明细，按需展开即可继续补证。"
        }
        return "任务已完成，主阅读流优先展示最终答复。完整计划已折叠，需要复盘时再展开。"
    }

    private var shouldShowRunningMetric: Bool {
        runningCount > 0 && plan.status != .completed
    }

    private var shouldShowVerifiedMetric: Bool {
        verifiedCount > 0 && plan.status != .completed && unverifiedCount == 0
    }

    private var summaryBannerTitle: String {
        if failedCount > 0 {
            return "优先处理"
        }
        if prioritizedBlockedSubTask != nil {
            return "优先恢复"
        }
        if needsAttentionCount > 0 || unverifiedCount > 0 {
            return "优先补证"
        }
        return "当前重点"
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

            if !plan.subTasks.isEmpty && !isShowingCompletedSummary {
                HStack(spacing: 8) {
                    TaskPlanMetricChip(
                        title: "已完成",
                        value: "\(completedCount)/\(plan.subTasks.count)",
                        tone: Theme.statusSuccess
                    )

                    if shouldShowRunningMetric {
                        TaskPlanMetricChip(
                            title: "执行中",
                            value: "\(runningCount)",
                            tone: Theme.statusInfo
                        )
                    }

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

                    if shouldShowVerifiedMetric {
                        TaskPlanMetricChip(
                            title: "已验证",
                            value: "\(verifiedCount)",
                            tone: Theme.accentSecondary
                        )
                    }
                }

                if let nextAttentionSummary {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(nextAttentionTone)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(summaryBannerTitle)
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

            if isShowingCompletedSummary {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("计划已收束")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)

                        Text(completedSummaryText)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button("展开计划") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showCompletedPlanDetails = true
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accentPrimary)
                }
                .padding(10)
                .background(Theme.bgInput)
                .cornerRadius(Theme.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            } else {
                // Original task
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("原始任务")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                            .textCase(.uppercase)

                        Spacer(minLength: 0)

                        if shouldOfferCompletedSummary {
                            Button("收起计划") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showCompletedPlanDetails = false
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.accentPrimary)
                        }
                    }

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

                        ForEach(visibleSubTasks) { subTask in
                            DarkSubTaskRow(subTask: subTask)
                        }

                        if hiddenSubTaskCount > 0 {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(showAllSubTasks ? "已展开全部子任务" : "已折叠稳定项")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)

                                    Text(collapsedSubTaskSummary)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)

                                Button(collapseToggleTitle) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showAllSubTasks.toggle()
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accentPrimary)
                            }
                            .padding(10)
                            .background(Theme.bgInput)
                            .cornerRadius(Theme.radiusSM)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusSM)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            )
                        }
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
        .onChange(of: plan.id) { _, _ in
            showAllSubTasks = false
            showCompletedPlanDetails = false
        }
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
                HStack(alignment: .top, spacing: 8) {
                    Text(subTask.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(3)
                        .help(subTask.description)

                    Spacer(minLength: 0)

                    if subTask.needsAttention {
                        SubTaskMetaPill(
                            icon: "sparkle.magnifyingglass",
                            text: "需关注",
                            tone: attentionColor
                        )
                    }
                }

                HStack(spacing: 6) {
                    SubTaskMetaPill(
                        icon: statusIcon,
                        text: statusDisplayText,
                        tone: statusColor
                    )

                    SubTaskMetaPill(
                        icon: verificationIcon,
                        text: subTask.verificationStatus.displayText,
                        tone: verificationColor
                    )

                    if subTask.retryCount > 0 {
                        SubTaskMetaPill(
                            icon: "arrow.counterclockwise",
                            text: "重试 \(subTask.retryCount) 次",
                            tone: Theme.statusWarning
                        )
                    }
                }

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
                            .help(worker.model)
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
                        .help(reason)
                }

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
                            .help(attentionSummary)
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
                        .lineLimit(3)
                        .help(summary)
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
                            .help(resultText)
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
        .background(rowTone.opacity(0.08))
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(rowTone.opacity(0.18), lineWidth: 1)
        )
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

    private var statusDisplayText: String {
        switch subTask.status {
        case .pending: return "待处理"
        case .running: return "执行中"
        case .completed: return "已完成"
        case .cancelled: return "已停止"
        case .failed: return "失败"
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

    private var rowTone: Color {
        if subTask.status == .failed || subTask.verificationStatus == .needsRetry {
            return Theme.statusError
        }
        if subTask.needsAttention || subTask.verificationStatus == .unverified {
            return Theme.statusWarning
        }
        if subTask.status == .cancelled {
            return Theme.textTertiary
        }
        if subTask.status == .running {
            return Theme.statusInfo
        }
        return Theme.accentPrimary
    }
}

struct SubTaskRow: View {
    let subTask: SubTask
    var body: some View { DarkSubTaskRow(subTask: subTask) }
}

private struct SubTaskMetaPill: View {
    let icon: String
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tone.opacity(0.10))
        .cornerRadius(Theme.radiusSM)
    }
}
