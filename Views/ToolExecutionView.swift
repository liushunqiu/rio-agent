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
                    .lineLimit(2)
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
            return result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        switch state {
        case .pending(let tc): return "等待执行: \(tc.name)"
        case .confirming(let tc): return "确认执行: \(tc.name)"
        case .executing(let tc): return "正在执行: \(tc.name)"
        case .completed(let tc, let result):
            return result.status == .success ? "执行成功: \(tc.name)" : "执行失败: \(tc.name)"
        case .failed(let tc, _): return "执行错误: \(tc.name)"
        }
    }

    private var statusMessage: String {
        switch state {
        case .pending: return "等待用户确认"
        case .confirming: return "请在弹窗中确认是否执行"
        case .executing: return "正在执行命令..."
        case .completed(_, let result):
            return result.status == .success ? String(result.output.prefix(80)) : result.error ?? "未知错误"
        case .failed(_, let error): return error
        }
    }

    private var statusColor: Color {
        switch state {
        case .pending: return Theme.textTertiary
        case .confirming: return Theme.statusWarning
        case .executing: return Theme.statusInfo
        case .completed(_, let result):
            return result.status == .success ? Theme.statusSuccess : Theme.statusError
        case .failed: return Theme.statusError
        }
    }
}
