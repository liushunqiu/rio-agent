import SwiftUI

/// Context Panel - Right sidebar showing session context
struct ContextPanel: View {
    let singleAgentPlan: AgentEngine.SingleAgentPlan?
    let taskPlan: TaskPlan?
    let pipeline: ExecutionPipeline?
    let singleAgentVerification: VerifierService.VerificationOutcome?
    let pendingUserDecision: AgentEngine.PendingUserDecision?
    let runtimeRoles: [AgentEngine.RuntimeModelRole]
    let messageCount: Int
    var workingDirectory: String?
    var estimatedTokens: Int = 0
    var contextWindow: Int = 200000
    var recentFiles: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accentPrimary)
                    Text("上下文")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 14) {
                    if let pendingUserDecision {
                        PendingDecisionPanel(pendingUserDecision: pendingUserDecision)
                    } else if let taskPlan {
                        TaskPlanView(plan: taskPlan)
                    } else if let singleAgentPlan {
                        SingleAgentPlanPanel(plan: singleAgentPlan)
                    } else {
                        EmptyPlanPanel()
                    }

                    if let pipeline {
                        ContextSection(title: "运行态") {
                            RuntimeFocusCard(
                                pipeline: pipeline,
                                taskPlan: taskPlan,
                                singleAgentVerification: singleAgentVerification,
                                pendingUserDecision: pendingUserDecision
                            )
                        }
                    }

                    ContextSection(title: "会话") {
                        SessionOverviewCard(
                            modelCount: runtimeRoles.count,
                            messageCount: messageCount,
                            recentFileCount: recentFiles.count,
                            workingDirectory: workingDirectory,
                            activitySummary: activitySummary
                        )
                    }

                    if !runtimeRoles.isEmpty {
                        ContextSection(title: "模型") {
                            ForEach(runtimeRoles) { role in
                                RuntimeModelRow(role: role)
                            }
                        }
                    }

                    // Context Usage
                    ContextSection(title: "上下文") {
                        let usedPercent = contextUsagePercent
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("累计消耗")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.textTertiary)
                                Text(formatTokenCount(estimatedTokens))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            Spacer()

                            ContextUsageBadge(
                                label: usedPercent < 70 ? "余量充足" : (usedPercent < 90 ? "接近上限" : "建议压缩"),
                                tone: usageTone(for: usedPercent)
                            )
                        }
                        ContextBar(usedPercent: usedPercent)
                        ContextRow(label: "模型窗口", value: formatTokenCount(contextWindow))
                        ContextRow(label: "占窗口比例", value: "\(usedPercent)%")
                    }

                    if !recentFiles.isEmpty {
                        ContextSection(title: "最近文件") {
                            ForEach(recentFiles.prefix(5), id: \.self) { file in
                                RecentFileRow(file: file, workingDirectory: workingDirectory)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(
            LinearGradient(
                colors: [Theme.bgSecondary.opacity(0.96), Theme.bgPrimary.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private var contextUsagePercent: Int {
        guard contextWindow > 0, estimatedTokens > 0 else { return 0 }
        let percentage = Double(estimatedTokens) / Double(contextWindow) * 100
        guard percentage.isFinite else { return 100 }
        return min(max(Int(percentage.rounded()), 0), 100)
    }

    private func usageTone(for usedPercent: Int) -> Color {
        if usedPercent < 70 {
            return Theme.statusSuccess
        } else if usedPercent < 90 {
            return Theme.statusWarning
        } else {
            return Theme.statusError
        }
    }

    private var activitySummary: String? {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "等待确认 · 覆盖 AGENT.md"
            case .chooseExecutionModeForTask:
                return "等待确认 · 选择执行模式"
            }
        }

        if let taskPlan {
            return "多 Agent · \(multiAgentSummary(for: taskPlan))"
        }

        if let singleAgentPlan {
            let completed = min(singleAgentPlan.currentStep, singleAgentPlan.steps.count)
            return "单 Agent · \(completed)/\(singleAgentPlan.steps.count) 步"
        }

        return nil
    }

    private func multiAgentSummary(for plan: TaskPlan) -> String {
        let completed = plan.subTasks.filter { $0.status == .completed }.count
        let failed = plan.subTasks.filter { $0.status == .failed }.count
        let cancelled = plan.subTasks.filter { $0.status == .cancelled }.count
        var parts = ["\(completed)/\(plan.subTasks.count) 子任务"]
        if failed > 0 {
            parts.append("失败 \(failed)")
        }
        if cancelled > 0 {
            parts.append("停止 \(cancelled)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Plan Panels

struct SingleAgentPlanPanel: View {
    let plan: AgentEngine.SingleAgentPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accentPrimary)

                Text("执行计划")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                DarkStatusBadge(status: plan.status)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("任务")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)

                Text(plan.originalTask)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(4)
                    .help(plan.originalTask)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgInput)
                    .cornerRadius(Theme.radiusSM)
            }

            HStack(spacing: 8) {
                PlanMetric(label: "复杂度", value: complexityText)
                PlanMetric(label: "进度", value: "\(min(plan.currentStep, plan.steps.count))/\(plan.steps.count)")
                PlanMetric(label: "预计", value: estimatedTimeText)
            }

            if !plan.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("步骤")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        SingleAgentPlanStepRow(
                            index: index,
                            step: step,
                            status: status(for: index)
                        )
                    }
                }
            }

            if !plan.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(plan.reasoning)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(5)
                    .help(plan.reasoning)
            }
        }
        .padding(12)
        .background(Theme.bgGlass)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.accentPrimary.opacity(0.22), lineWidth: 1)
        )
    }

    private var complexityText: String {
        switch plan.complexity {
        case .simple: return "简单"
        case .moderate: return "中等"
        case .complex: return "复杂"
        case .veryComplex: return "很复杂"
        }
    }

    private var estimatedTimeText: String {
        let estimated = plan.estimatedTime
        if estimated < 60 {
            return "\(Int(max(estimated.rounded(), 1)))s"
        }

        let minutes = Int(estimated / 60)
        let seconds = Int(estimated.truncatingRemainder(dividingBy: 60))
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }

    private func status(for index: Int) -> PipelineStageStatus {
        switch plan.status {
        case .completed:
            return .completed
        case .cancelled:
            return index < plan.currentStep ? .completed : .cancelled
        case .failed:
            return index < plan.currentStep ? .completed : .failed
        case .executing, .verifying, .synthesizing:
            if index < plan.currentStep { return .completed }
            if index == plan.currentStep { return .running }
            return .pending
        case .planning:
            return .pending
        }
    }
}

struct SingleAgentPlanStepRow: View {
    let index: Int
    let step: String
    let status: PipelineStageStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(status == .pending ? 0.14 : 0.22))
                    .frame(width: 20, height: 20)

                if status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(statusColor)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }
            .frame(width: 20, height: 20)

            Text(step)
                .font(.system(size: 11))
                .foregroundColor(status == .pending ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(4)
                .help(step)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.bgTertiary.opacity(status == .running ? 0.9 : 0.55))
        .cornerRadius(Theme.radiusSM)
    }

    private var statusColor: Color {
        switch status {
        case .completed: return Theme.statusSuccess
        case .running: return Theme.statusInfo
        case .cancelled: return Theme.textTertiary
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary
        case .pending: return Theme.textTertiary
        }
    }
}

struct PlanMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
    }
}

struct EmptyPlanPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
                Text("执行计划")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            Text("当前没有活动计划。复杂任务会在这里展示规划步骤和执行进度。")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct PendingDecisionPanel: View {
    let pendingUserDecision: AgentEngine.PendingUserDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.statusWarning)

                Text("等待确认")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Text("待处理")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.statusWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.statusWarning.opacity(0.12))
                    .cornerRadius(Theme.radiusSM)
            }

            Text(decisionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Text(decisionDescription)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                DecisionHintChip(icon: "checkmark.circle", text: confirmHint, tone: Theme.statusSuccess)
                DecisionHintChip(icon: "arrow.triangle.branch", text: redirectHint, tone: Theme.statusInfo)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.statusWarning.opacity(0.22), lineWidth: 1)
        )
    }

    private var decisionTitle: String {
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "准备继续初始化"
        case .chooseExecutionModeForTask:
            return "准备开始执行"
        }
    }

    private var decisionDescription: String {
        switch pendingUserDecision {
        case let .overwriteAgentFile(directory):
            let name = URL(fileURLWithPath: directory).lastPathComponent
            return "当前目录 \(name) 已存在 AGENT.md。系统正在等待你确认是否覆盖，或改为处理一条新的任务。"
        case let .chooseExecutionModeForTask(task):
            return "当前任务已分析完成，系统正在等待你确认执行模式。\n\(task)"
        }
    }

    private var confirmHint: String {
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "回复是进行覆盖"
        case .chooseExecutionModeForTask:
            return "回复是继续多 Agent"
        }
    }

    private var redirectHint: String {
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "回复否或直接改任务"
        case .chooseExecutionModeForTask:
            return "回复否改单 Agent"
        }
    }
}

struct DecisionHintChip: View {
    let icon: String
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tone.opacity(0.10))
        .cornerRadius(Theme.radiusSM)
    }
}

// MARK: - Learning Progress Ring

struct LearningProgressRing: View {
    let progress: Double
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Theme.bgTertiary, lineWidth: 3)
                .frame(width: size, height: size)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.accentPrimary, Theme.statusSuccess]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            // Percentage text
            Text("\(Int(progress * 100))%")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.textPrimary)
        }
    }
}

// MARK: - Tool Recommendation Badge

struct ToolRecommendationBadge: View {
    let toolName: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: toolIcon)
                .font(.system(size: 9))
                .foregroundColor(Theme.accentPrimary)
            
            Text(toolDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.accentPrimary.opacity(0.1))
        .cornerRadius(Theme.radiusSM)
    }
    
    private var toolIcon: String {
        switch toolName {
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "edit_file": return "pencil"
        case "search_files": return "magnifyingglass"
        case "find_files": return "folder"
        case "list_directory": return "list.bullet"
        case "execute_command": return "terminal"
        case "apply_patch": return "doc.plaintext"
        default: return "wrench"
        }
    }
    
    private var toolDisplayName: String {
        switch toolName {
        case "read_file": return "读取文件"
        case "write_file": return "写入文件"
        case "edit_file": return "编辑文件"
        case "search_files": return "搜索"
        case "find_files": return "查找文件"
        case "list_directory": return "目录列表"
        case "execute_command": return "执行命令"
        case "apply_patch": return "应用补丁"
        default: return toolName
        }
    }
}

// MARK: - Memory Stats

struct MemoryStats {
    var totalLearningEvents: Int = 0
    var toolPreferences: Int = 0
    var workflowPatterns: Int = 0
    var errorPatterns: Int = 0
}

// MARK: - Section

struct ContextSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accentPrimary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgGlass)
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
        }
    }
}

// MARK: - Row

struct ContextRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}

struct SessionOverviewCard: View {
    let modelCount: Int
    let messageCount: Int
    let recentFileCount: Int
    let workingDirectory: String?
    let activitySummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SessionMetric(icon: "cpu", label: "模型", value: "\(modelCount)")
                SessionMetric(icon: "text.bubble", label: "消息", value: "\(messageCount)")
                SessionMetric(icon: "doc.text", label: "文件", value: "\(recentFileCount)")
            }

            if let activitySummary {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accentPrimary)
                    Text(activitySummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(activitySummary)
                    Spacer()
                }
                .padding(8)
                .background(Theme.bgInput)
                .cornerRadius(Theme.radiusSM)
            }

            if let workingDirectory {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.statusInfo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: workingDirectory).lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(workingDirectory)
                        Text(workingDirectory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(workingDirectory)
                    }

                    Spacer()
                }
                .padding(8)
                .background(Theme.bgInput)
                .cornerRadius(Theme.radiusSM)
            }
        }
    }
}

struct RuntimeFocusCard: View {
    let pipeline: ExecutionPipeline
    let taskPlan: TaskPlan?
    let singleAgentVerification: VerifierService.VerificationOutcome?
    let pendingUserDecision: AgentEngine.PendingUserDecision?

    private var currentStage: PipelineStage? {
        pipeline.currentStage
    }

    private var exceptionalStage: PipelineStage? {
        pipeline.stages.last(where: { $0.status == .failed || $0.status == .cancelled })
    }

    private var completedStageCount: Int {
        pipeline.stages.filter { $0.status == .completed || $0.status == .skipped }.count
    }

    private var actionableSubTaskCount: Int {
        taskPlan?.subTasks.filter(\.needsAttention).count ?? 0
    }

    private var prioritizedBlockedSubTask: SubTask? {
        taskPlan?.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RuntimeMetricPill(
                    icon: overallStatusIcon,
                    label: "状态",
                    value: overallStatusText,
                    tone: overallStatusColor
                )
                RuntimeMetricPill(
                    icon: "list.number",
                    label: "阶段",
                    value: "\(completedStageCount)/\(pipeline.stages.count)",
                    tone: Theme.accentPrimary
                )
                if actionableSubTaskCount > 0 {
                    RuntimeMetricPill(
                        icon: "exclamationmark.bubble",
                        label: "待处理",
                        value: "\(actionableSubTaskCount)",
                        tone: Theme.statusWarning
                    )
                }
            }

            if let pendingUserDecision {
                RuntimeFocusRow(
                    icon: "questionmark.circle",
                    title: "等待输入",
                    value: pendingDecisionTitle(for: pendingUserDecision),
                    detail: pendingDecisionDetail(for: pendingUserDecision),
                    tone: Theme.statusWarning
                )
            } else if let currentStage {
                RuntimeFocusRow(
                    icon: currentStage.type.icon,
                    title: "当前阶段",
                    value: currentStage.type.title,
                    detail: stageSummary(for: currentStage),
                    tone: stageTone(for: currentStage.status)
                )
            } else if let singleAgentVerification {
                RuntimeFocusRow(
                    icon: verificationIcon(for: singleAgentVerification.status),
                    title: "验证状态",
                    value: verificationTitle(for: singleAgentVerification.status),
                    detail: singleAgentVerification.summary,
                    tone: verificationTone(for: singleAgentVerification.status)
                )
            }

            if let exceptionalStage {
                RuntimeFocusRow(
                    icon: exceptionalStage.status == .failed ? "exclamationmark.triangle.fill" : "slash.circle.fill",
                    title: exceptionalStage.status == .failed ? "异常阶段" : "已停止阶段",
                    value: exceptionalStage.type.title,
                    detail: stageSummary(for: exceptionalStage),
                    tone: stageTone(for: exceptionalStage.status)
                )
            }

            RuntimeFocusRow(
                icon: "sparkle.magnifyingglass",
                title: "下一步建议",
                value: nextActionTitle,
                detail: nextActionDetail,
                tone: nextActionTone
            )
        }
    }

    private var overallStatusText: String {
        if pendingUserDecision != nil {
            return "等待确认"
        }
        switch pipeline.overallStatus {
        case .pending: return "等待中"
        case .running: return "执行中"
        case .completed: return "已完成"
        case .cancelled: return "已停止"
        case .failed: return "失败"
        case .skipped: return "已跳过"
        }
    }

    private var overallStatusIcon: String {
        if pendingUserDecision != nil {
            return "questionmark.circle.fill"
        }
        switch pipeline.overallStatus {
        case .pending: return "clock"
        case .running: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private var overallStatusColor: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        return stageTone(for: pipeline.overallStatus)
    }

    private func stageTone(for status: PipelineStageStatus) -> Color {
        switch status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .cancelled: return Theme.textTertiary
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary
        }
    }

    private func stageSummary(for stage: PipelineStage) -> String {
        switch stage.details {
        case .empty:
            return "等待阶段更新。"
        case .router(let decision, let target, let confidence):
            var parts = [decision]
            if let target, !target.isEmpty {
                parts.append("目标 \(target)")
            }
            if let confidence {
                parts.append("置信度 \(Int((confidence * 100).rounded()))%")
            }
            return parts.joined(separator: " · ")
        case .taskAnalysis(let complexity, let stepCount, let estimatedTime):
            var parts = ["复杂度 \(complexity)", "\(stepCount) 个步骤"]
            if let estimatedTime, !estimatedTime.isEmpty {
                parts.append(estimatedTime)
            }
            return parts.joined(separator: " · ")
        case .dagPlanning(let subTaskCount, let workerCount, let maxDepth):
            return "\(subTaskCount) 个子任务 · \(workerCount) 个 Worker · 深度 \(maxDepth)"
        case .execution(_, let completed, let total, let failed, let cancelled):
            var parts = ["\(completed)/\(total) 已结束"]
            if failed > 0 {
                parts.append("失败 \(failed)")
            }
            if cancelled > 0 {
                parts.append("停止 \(cancelled)")
            }
            if failed == 0 && cancelled == 0 {
                parts.append("无阻塞")
            }
            return parts.joined(separator: " · ")
        case .errorRecovery(let retryCount, let analysis):
            if let analysis, !analysis.isEmpty {
                return "第 \(retryCount) 次重试 · \(analysis)"
            }
            return "第 \(retryCount) 次重试"
        case .verification(let passed, let total, _):
            return "通过 \(passed)/\(total) 项检查"
        case .synthesis(let workerResults):
            return "汇总 \(workerResults) 个结果"
        case .error(let message):
            return message
        case .skipped(let reason):
            return reason
        case .cancelled(let reason):
            return reason
        }
    }

    private var nextActionTitle: String {
        if let pendingUserDecision {
            return pendingDecisionTitle(for: pendingUserDecision)
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "先修订答案"
            case .unverified:
                return "补充验证证据"
            case .verified:
                break
            }
        }
        if let exceptionalStage {
            switch exceptionalStage.status {
            case .failed:
                return "先修复失败阶段"
            case .cancelled:
                return "确认是否重新启动"
            default:
                break
            }
        }
        if pipeline.overallStatus == .completed {
            return "检查最终结果"
        }
        if let currentStage {
            return "等待 \(currentStage.type.title) 完成"
        }
        return "等待下一次输入"
    }

    private var nextActionDetail: String {
        if let pendingUserDecision {
            return pendingDecisionDetail(for: pendingUserDecision)
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "当前答案与证据冲突，建议先根据验证摘要修订结论，再继续输出。"
            case .unverified:
                return "当前没有足够强的完成证据，建议补充读回、测试或命令验证。"
            case .verified:
                break
            }
        }
        if let exceptionalStage {
            switch exceptionalStage.status {
            case .failed:
                if let recoveryContext = prioritizedBlockedSubTask?.recoveryContext {
                    return recoveryContext.recoveryActionDetail
                }
                return "先阅读该阶段错误，再根据右下角错误横幅或设置入口修复模型、路由或 Worker 配置。"
            case .cancelled:
                return "如果停止是预期行为，可直接提交新任务；如果不是，恢复上一个任务文本后重新执行。"
            default:
                break
            }
        }
        if pipeline.overallStatus == .completed {
            return "结果已经生成，建议优先核对关键文件变更、工具输出和验证状态。"
        }
        if let currentStage {
            return "当前系统正在处理 \(currentStage.type.title)。如果长时间无进展，优先检查对应阶段的模型配置与执行输出。"
        }
        return "当前没有活动执行，提交一个任务即可开始新的流程。"
    }

    private var nextActionTone: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if let singleAgentVerification {
            return verificationTone(for: singleAgentVerification.status)
        }
        if let exceptionalStage {
            return stageTone(for: exceptionalStage.status)
        }
        if pipeline.overallStatus == .completed {
            return Theme.statusSuccess
        }
        return Theme.statusInfo
    }

    private func pendingDecisionTitle(for decision: AgentEngine.PendingUserDecision) -> String {
        switch decision {
        case .overwriteAgentFile:
            return "确认是否覆盖 AGENT.md"
        case .chooseExecutionModeForTask:
            return "确认执行模式"
        }
    }

    private func pendingDecisionDetail(for decision: AgentEngine.PendingUserDecision) -> String {
        switch decision {
        case .overwriteAgentFile:
            return "回复“是”会覆盖现有 AGENT.md；回复其他内容会取消覆盖，并允许直接切换到新任务。"
        case .chooseExecutionModeForTask:
            return "回复“是”继续多 Agent；回复其他内容会改走单 Agent，避免无谓等待。"
        }
    }

    private func verificationTitle(for status: VerificationStatus) -> String {
        switch status {
        case .verified:
            return "已验证"
        case .unverified:
            return "未验证"
        case .needsRetry:
            return "需修订"
        }
    }

    private func verificationIcon(for status: VerificationStatus) -> String {
        switch status {
        case .verified:
            return "checkmark.shield.fill"
        case .unverified:
            return "questionmark.circle"
        case .needsRetry:
            return "exclamationmark.triangle.fill"
        }
    }

    private func verificationTone(for status: VerificationStatus) -> Color {
        switch status {
        case .verified:
            return Theme.statusSuccess
        case .unverified:
            return Theme.statusWarning
        case .needsRetry:
            return Theme.statusError
        }
    }
}

struct RuntimeMetricPill: View {
    let icon: String
    let label: String
    let value: String
    let tone: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.08))
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
    }
}

struct RuntimeFocusRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(tone.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tone)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(detail)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
    }
}

struct SessionMetric: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Theme.accentPrimary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
    }
}

struct ContextUsageBadge: View {
    let label: String
    let tone: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tone.opacity(0.10))
        .cornerRadius(Theme.radiusSM)
    }
}

struct RecentFileRow: View {
    let file: String
    let workingDirectory: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: file).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file)

                Text(relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var relativePath: String {
        PathSecurity.relativePath(file, from: workingDirectory)
    }
}

struct RuntimeModelRow: View {
    let role: AgentEngine.RuntimeModelRole

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(role.isActive ? Theme.statusSuccess : Theme.textTertiary.opacity(0.5))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(role.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(role.title)

                    if role.isActive {
                        Text("运行中")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.statusSuccess)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.statusSuccess.opacity(0.12))
                            .cornerRadius(Theme.radiusSM)
                    }
                }

                Text(role.modelName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(role.modelName)

                Text(role.providerName)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(role.providerName)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Progress Bar

struct ContextBar: View {
    let usedPercent: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.bgTertiary)
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geometry.size.width * CGFloat(clampedPercent) / 100, height: 4)
            }
        }
        .frame(height: 4)
    }

    private var clampedPercent: Int {
        min(max(usedPercent, 0), 100)
    }

    private var barColor: Color {
        if clampedPercent < 50 {
            return Theme.statusSuccess
        } else if clampedPercent < 80 {
            return Theme.statusWarning
        } else {
            return Theme.statusError
        }
    }
}

// MARK: - MCP Server Row

enum MCPServerStatus {
    case connected
    case disconnected
    case error
}

struct MCPServerRow: View {
    let name: String
    let status: MCPServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Text(statusText)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return Theme.statusSuccess
        case .disconnected: return Theme.textTertiary
        case .error: return Theme.statusError
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "已连接"
        case .disconnected: return "未连接"
        case .error: return "异常"
        }
    }
}
