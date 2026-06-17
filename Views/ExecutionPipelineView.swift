import SwiftUI

/// 执行流水线可视化面板（统一展示 Single Agent 和 Multi-Agent 的执行流程）
struct ExecutionPipelineView: View {
    let pipeline: ExecutionPipeline
    @State private var expandedStages: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: pipelineIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(pipelineColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pipelineTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    if let duration = formattedDuration {
                        Text(duration)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Spacer()

                StatusIndicator(status: pipeline.overallStatus)
            }

            Divider().overlay(Theme.borderSubtle)

            // Stages
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pipeline.stages.enumerated()), id: \.element.id) { index, stage in
                    VStack(spacing: 0) {
                        StageRow(
                            stage: stage,
                            isExpanded: expandedStages.contains(stage.id),
                            onToggle: {
                                if expandedStages.contains(stage.id) {
                                    expandedStages.remove(stage.id)
                                } else {
                                    expandedStages.insert(stage.id)
                                }
                            }
                        )

                        // Connector line to next stage
                        if index < pipeline.stages.count - 1 {
                            ConnectorLine(fromStatus: stage.status)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(pipelineColor.opacity(0.3), lineWidth: 1.5)
        )
        .onAppear {
            // 默认展开正在运行的阶段
            if let currentStage = pipeline.currentStage {
                expandedStages.insert(currentStage.id)
            }
        }
    }

    private var pipelineIcon: String {
        switch pipeline.mode {
        case .singleAgent: return "flowchart.fill"
        case .multiAgent: return "network"
        }
    }

    private var pipelineTitle: String {
        switch pipeline.mode {
        case .singleAgent: return "Single Agent 执行流程"
        case .multiAgent: return "Multi-Agent 执行流程"
        }
    }

    private var pipelineColor: Color {
        switch pipeline.overallStatus {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary
        }
    }

    private var formattedDuration: String? {
        let duration = pipeline.duration
        guard duration > 0.1 else { return nil }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Stage Row

struct StageRow: View {
    let stage: PipelineStage
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stage header (always visible)
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(stageColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: stageIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(stageColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(stage.type.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)

                            if let duration = formattedDuration {
                                Text(duration)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.bgTertiary)
                                    .cornerRadius(Theme.radiusSM)
                            }
                        }

                        Text(stageSummary)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if stage.status == .running {
                        ProgressView()
                            .controlSize(.small)
                            .tint(stageColor)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(stageColor)
                    }

                    if !stage.substeps.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(isExpanded ? Theme.bgTertiary.opacity(0.5) : Color.clear)
                .cornerRadius(Theme.radiusMD)
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Stage-specific details
                    StageDetailsView(details: stage.details)

                    // Substeps
                    if !stage.substeps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(stage.substeps) { substep in
                                SubstepRow(substep: substep)
                            }
                        }
                    }
                }
                .padding(.leading, 42)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private var stageIcon: String {
        stage.type.icon
    }

    private var stageColor: Color {
        switch stage.status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary.opacity(0.5)
        }
    }

    private var statusIcon: String {
        switch stage.status {
        case .pending: return "clock"
        case .running: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private var stageSummary: String {
        switch stage.details {
        case .empty: return "等待执行..."
        case .router(let decision, _, let confidence):
            if let conf = confidence {
                return "\(decision) (置信度: \(String(format: "%.0f%%", conf * 100)))"
            }
            return decision
        case .taskAnalysis(let complexity, let stepCount, _):
            return "复杂度: \(complexity) · \(stepCount) 个步骤"
        case .dagPlanning(let subTaskCount, let workerCount, _):
            return "\(subTaskCount) 个子任务 · \(workerCount) 个 Worker"
        case .execution(_, let completed, let total):
            return "已执行 \(completed)/\(total) 个工具调用"
        case .errorRecovery(let retryCount, _):
            return "第 \(retryCount) 次重试"
        case .verification(let passed, let total):
            return "通过 \(passed)/\(total) 项检查"
        case .synthesis(let workerResults):
            return "汇总 \(workerResults) 个结果"
        case .error(let message):
            return "❌ \(message)"
        case .skipped(let reason):
            return "已跳过: \(reason)"
        }
    }

    private var formattedDuration: String? {
        guard let duration = stage.duration else { return nil }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m\(seconds)s"
        }
    }
}

// MARK: - Stage Details View

struct StageDetailsView: View {
    let details: StageDetails

    var body: some View {
        Group {
            switch details {
            case .empty:
                EmptyView()

            case .router(_, let target, _):
                if let target {
                    DetailRow(icon: "arrow.right.circle", label: "路由目标", value: target)
                }

            case .taskAnalysis(_, _, let estimatedTime):
                if let time = estimatedTime {
                    DetailRow(icon: "clock", label: "预计耗时", value: time)
                }

            case .dagPlanning(_, _, let maxDepth):
                DetailRow(icon: "arrow.down.to.line", label: "最大依赖深度", value: "\(maxDepth)")

            case .execution(let toolCalls, _, _):
                if !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailRow(icon: "wrench.and.screwdriver", label: "工具列表", value: "")
                        ForEach(toolCalls, id: \.self) { tool in
                            Text("• \(tool)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                                .padding(.leading, 20)
                        }
                    }
                }

            case .errorRecovery(_, let analysis):
                if let analysis {
                    DetailRow(icon: "text.bubble", label: "Critic 分析", value: analysis)
                }

            case .verification(_, _):
                EmptyView()

            case .synthesis(_):
                EmptyView()

            case .error(let message):
                DetailRow(icon: "exclamationmark.triangle", label: "错误", value: message, color: Theme.statusError)

            case .skipped(let reason):
                DetailRow(icon: "info.circle", label: "跳过原因", value: reason, color: Theme.textTertiary)
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = Theme.textSecondary

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color.opacity(0.7))
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textTertiary)

                Text(value)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Substep Row

struct SubstepRow: View {
    let substep: PipelineSubstep

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(substep.title)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            if let duration = substep.duration {
                Text(formattedDuration(duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            Image(systemName: statusIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
    }

    private var statusColor: Color {
        switch substep.status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary.opacity(0.5)
        }
    }

    private var statusIcon: String {
        switch substep.status {
        case .pending: return "clock"
        case .running: return "arrow.clockwise"
        case .completed: return "checkmark"
        case .failed: return "xmark"
        case .skipped: return "minus"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.1fs", duration)
        }
    }
}

// MARK: - Connector Line

struct ConnectorLine: View {
    let fromStatus: PipelineStageStatus

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 16)
            Rectangle()
                .fill(lineColor)
                .frame(width: 2, height: 16)
            Spacer()
        }
    }

    private var lineColor: Color {
        switch fromStatus {
        case .completed: return Theme.statusSuccess.opacity(0.3)
        case .running: return Theme.statusInfo.opacity(0.3)
        case .failed: return Theme.statusError.opacity(0.3)
        case .skipped: return Theme.textTertiary.opacity(0.2)
        case .pending: return Theme.borderSubtle
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: PipelineStageStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                ProgressView()
                    .controlSize(.mini)
                    .tint(statusColor)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .foregroundColor(statusColor)
        .cornerRadius(Theme.radiusSM)
    }

    private var statusIcon: String {
        switch status {
        case .pending: return "clock"
        case .running: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private var statusText: String {
        switch status {
        case .pending: return "等待中"
        case .running: return "执行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .skipped: return "已跳过"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary
        }
    }
}

// MARK: - Preview

struct ExecutionPipelineView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ExecutionPipelineView(pipeline: mockPipeline)
        }
        .padding()
        .background(Theme.bgPrimary)
    }

    static var mockPipeline: ExecutionPipeline {
        var pipeline = ExecutionPipeline(mode: .singleAgent)

        var stage1 = PipelineStage(type: .router, details: .router(decision: "SKIP", target: nil, confidence: 0.95))
        stage1.status = .completed
        stage1.startTime = Date().addingTimeInterval(-5)
        stage1.endTime = Date().addingTimeInterval(-4.8)

        var stage2 = PipelineStage(type: .taskAnalysis, details: .taskAnalysis(complexity: "Moderate", stepCount: 3, estimatedTime: "~2 min"))
        stage2.status = .completed
        stage2.startTime = Date().addingTimeInterval(-4.8)
        stage2.endTime = Date().addingTimeInterval(-4.2)

        var stage3 = PipelineStage(type: .execution, details: .execution(toolCalls: ["read_file", "write_file", "execute_command"], completedCount: 2, totalCount: 3))
        stage3.status = .running
        stage3.startTime = Date().addingTimeInterval(-4.2)
        stage3.substeps = [
            PipelineSubstep(title: "read_file: README.md", status: .completed, duration: 0.15),
            PipelineSubstep(title: "write_file: config.json", status: .completed, duration: 0.28),
            PipelineSubstep(title: "execute_command: npm install", status: .running)
        ]

        pipeline.stages = [stage1, stage2, stage3]

        return pipeline
    }
}
