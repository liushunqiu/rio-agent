import SwiftUI

/// Context Panel - Right sidebar showing session context and intelligent assistant status
struct ContextPanel: View {
    let messageCount: Int
    let modelName: String
    let providerName: String
    var estimatedTokens: Int = 0
    var contextWindow: Int = 200000
    var intelligentConfig: IntelligentAssistantConfig = IntelligentAssistantConfig()
    var memoryStats: MemoryStats = MemoryStats()
    var toolRecommendations: [String] = []
    var recentFiles: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                    Text("上下文")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 20) {
                    // Intelligent Assistant Status
                    ContextSection(title: "智能助手") {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 14))
                                .foregroundColor(intelligentConfig.enableLearning ? Theme.accentPrimary : Theme.textTertiary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intelligentConfig.enableLearning ? "学习中" : "已禁用")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(intelligentConfig.enableLearning ? Theme.statusSuccess : Theme.textTertiary)
                                
                                Text("已学习 \(memoryStats.totalLearningEvents) 个模式")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textTertiary)
                            }
                            
                            Spacer()
                            
                            // Learning progress indicator
                            if intelligentConfig.enableLearning {
                                LearningProgressRing(
                                    progress: min(Double(memoryStats.totalLearningEvents) / 100.0, 1.0),
                                    size: 24
                                )
                            }
                        }
                        
                        // Tool Recommendations
                        if intelligentConfig.enableToolRecommendations && !toolRecommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("推荐工具")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.textTertiary)
                                    .textCase(.uppercase)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 4) {
                                    ForEach(toolRecommendations.prefix(4), id: \.self) { tool in
                                        ToolRecommendationBadge(toolName: tool)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        // Recent Files
                        if intelligentConfig.enableContextAwareness && !recentFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("最近文件")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.textTertiary)
                                    .textCase(.uppercase)
                                
                                ForEach(recentFiles.prefix(3), id: \.self) { file in
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
                            .padding(.top, 8)
                        }
                    }

                    // Session Info
                    ContextSection(title: "Session") {
                        ContextRow(label: "模型", value: modelName)
                        ContextRow(label: "提供商", value: providerName)
                        ContextRow(label: "消息数", value: "\(messageCount)")
                        ContextRow(label: "时间", value: formatDate(Date()))
                    }

                    // Context Usage
                    ContextSection(title: "Context") {
                        let usedPercent = min(estimatedTokens * 100 / contextWindow, 100)
                        ContextRow(label: "Tokens", value: "\(estimatedTokens)")
                        ContextBar(usedPercent: usedPercent)
                        ContextRow(label: "窗口", value: formatTokenCount(contextWindow))
                        ContextRow(label: "已用", value: "\(usedPercent)%")
                    }


                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Theme.bgSecondary)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accentPrimary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
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
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
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
