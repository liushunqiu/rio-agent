import SwiftUI

/// Context Panel - Right sidebar showing session context
struct ContextPanel: View {
    let singleAgentPlan: AgentEngine.SingleAgentPlan?
    let taskPlan: TaskPlan?
    let runtimeRoles: [AgentEngine.RuntimeModelRole]
    let messageCount: Int
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
                    if let singleAgentPlan {
                        SingleAgentPlanPanel(plan: singleAgentPlan)
                    } else if let taskPlan {
                        TaskPlanView(plan: taskPlan)
                    } else {
                        EmptyPlanPanel()
                    }

                    ContextSection(title: "Session") {
                        ContextRow(label: "模型数", value: "\(runtimeRoles.count)")
                        ContextRow(label: "消息数", value: "\(messageCount)")
                        ContextRow(label: "时间", value: formatDate(Date()))
                    }

                    if !runtimeRoles.isEmpty {
                        ContextSection(title: "Models") {
                            ForEach(runtimeRoles) { role in
                                RuntimeModelRow(role: role)
                            }
                        }
                    }

                    // Context Usage
                    ContextSection(title: "Context") {
                        let usedPercent = min(estimatedTokens * 100 / contextWindow, 100)
                        ContextRow(label: "Tokens", value: "\(estimatedTokens)")
                        ContextBar(usedPercent: usedPercent)
                        ContextRow(label: "窗口", value: formatTokenCount(contextWindow))
                        ContextRow(label: "已用", value: "\(usedPercent)%")
                    }

                    if !recentFiles.isEmpty {
                        ContextSection(title: "最近文件") {
                            ForEach(recentFiles.prefix(5), id: \.self) { file in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textTertiary)

                                    Text(URL(fileURLWithPath: file).lastPathComponent)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)

                                    Spacer()
                                }
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
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
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgInput)
                    .cornerRadius(Theme.radiusSM)
            }

            HStack(spacing: 8) {
                PlanMetric(label: "复杂度", value: complexityText)
                PlanMetric(label: "步骤", value: "\(plan.steps.count)")
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

    private func status(for index: Int) -> PipelineStageStatus {
        switch plan.status {
        case .completed:
            return .completed
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

                    if role.isActive {
                        Text("ACTIVE")
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

                Text(role.providerName)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
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
                    .frame(width: geometry.size.width * CGFloat(usedPercent) / 100, height: 4)
            }
        }
        .frame(height: 4)
    }

    private var barColor: Color {
        if usedPercent < 50 {
            return Theme.statusSuccess
        } else if usedPercent < 80 {
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
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}
