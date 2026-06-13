import SwiftUI

struct ContextPanel: View {
    let messageCount: Int
    let modelName: String
    let providerName: String
    var estimatedTokens: Int = 0
    var contextWindow: Int = 200000

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
