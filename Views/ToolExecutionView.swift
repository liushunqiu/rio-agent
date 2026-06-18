import SwiftUI

struct ToolExecutionView: View {
    let state: ToolExecutionState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(statusMessageLineLimit)
                    .textSelection(.enabled)
                    .help(statusMessage)
            }

            Spacer()

            if case .executing = state {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
            }
        }
        .padding(14)
        .background(Theme.bgSecondary)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch state {
        case .pending: return "clock.fill"
        case .confirming: return "questionmark.circle.fill"
        case .executing: return "gear.circle.fill"
        case .completed(_, let result):
            switch result.status {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .cancelled: return "slash.circle.fill"
            }
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        switch state {
        case .pending(let tc): return "等待执行: \(tc.name)"
        case .confirming(let tc): return "确认执行: \(tc.name)"
        case .executing(let tc): return "正在执行: \(tc.name)"
        case .completed(let tc, let result):
            switch result.status {
            case .success: return "执行成功: \(tc.name)"
            case .error: return "执行失败: \(tc.name)"
            case .cancelled: return "已取消: \(tc.name)"
            }
        case .failed(let tc, _): return "执行错误: \(tc.name)"
        }
    }

    private var statusMessage: String {
        switch state {
        case .pending: return "等待用户确认"
        case .confirming: return "请在弹窗中确认是否执行"
        case .executing: return "正在执行命令..."
        case .completed(let toolCall, let result):
            return statusDetail(for: toolCall, result: result)
        case .failed(let toolCall, let error):
            return failureDetail(for: toolCall, error: error)
        }
    }

    private var statusMessageLineLimit: Int {
        switch state {
        case .completed(_, let result):
            switch result.status {
            case .success: return 2
            case .error, .cancelled: return 4
            }
        case .failed:
            return 4
        default:
            return 2
        }
    }

    private func compactStatusMessage(for result: ToolResult) -> String {
        let text = ToolResultDisplay.text(for: result)
        guard result.status == .success, text.count > 160 else {
            return text
        }
        return String(text.prefix(160)) + "..."
    }

    private func statusDetail(for toolCall: ToolCall, result: ToolResult) -> String {
        let detail = ToolResultDisplay.text(for: result)

        switch result.status {
        case .success:
            return compactStatusMessage(for: result)
        case .error:
            return "\(detail) 建议先检查 \(toolCall.name) 的输入和当前工作目录。"
        case .cancelled:
            return "\(detail) 如需继续，确认参数后重新发起 \(toolCall.name)。"
        }
    }

    private func failureDetail(for toolCall: ToolCall, error: String) -> String {
        "\(error) 建议先检查 \(toolCall.name) 的前置条件或权限配置。"
    }

    private var statusColor: Color {
        switch state {
        case .pending: return Theme.textTertiary
        case .confirming: return Theme.statusWarning
        case .executing: return Theme.statusInfo
        case .completed(_, let result):
            switch result.status {
            case .success: return Theme.statusSuccess
            case .error: return Theme.statusError
            case .cancelled: return Theme.textTertiary
            }
        case .failed: return Theme.statusError
        }
    }
}
