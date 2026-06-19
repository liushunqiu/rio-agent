import SwiftUI

// MARK: - File Operation Animation View

struct FileOperationAnimationView: View {
    let operationType: FileOperationType
    let fileName: String
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(operationType.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: isCompleted ? "checkmark.circle.fill" : operationType.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCompleted ? Theme.statusSuccess : operationType.color)
            }

            // Operation details
            VStack(alignment: .leading, spacing: 4) {
                Text(operationType.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(fileName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fileName)
            }

            Spacer()

            if !isCompleted {
                ProgressView()
                    .controlSize(.small)
                    .tint(operationType.color)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(operationType.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - File Operation Type

enum FileOperationType {
    case write
    case edit
    case create
    case delete
    
    var title: String {
        switch self {
        case .write: return "写入文件"
        case .edit: return "编辑文件"
        case .create: return "创建文件"
        case .delete: return "删除文件"
        }
    }
    
    var icon: String {
        switch self {
        case .write: return "doc.text.fill"
        case .edit: return "pencil.circle.fill"
        case .create: return "doc.badge.plus"
        case .delete: return "trash.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .write: return Theme.statusInfo
        case .edit: return Theme.statusWarning
        case .create: return Theme.statusSuccess
        case .delete: return Theme.statusError
        }
    }
}

// MARK: - File Diff Animation View

struct FileDiffAnimationView: View {
    let oldContent: String
    let newContent: String
    let isAnimating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.statusInfo)

                Text("代码变更")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Text("\(calculateDiffStats()) 处变更")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            // Diff preview
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { index, diffLine in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .frame(width: 30, alignment: .trailing)

                        Text(diffLine.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(diffLine.type.textColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(diffLine.text)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(diffLine.type.backgroundColor)
                    )
                }
            }
            .padding(8)
            .background(Theme.codeBackground)
            .cornerRadius(Theme.radiusMD)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .fill(Theme.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.statusInfo.opacity(0.2), lineWidth: 1)
        )
    }

    private var diffLines: [DiffLine] {
        let oldLines = oldContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)

        var result: [DiffLine] = []
        let maxLines = max(oldLines.count, newLines.count)

        for i in 0..<maxLines {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil

            switch (oldLine, newLine) {
            case let (old?, new?) where old == new:
                result.append(DiffLine(text: new, type: .unchanged))
            case let (nil, new?):
                result.append(DiffLine(text: "+ \(new)", type: .added))
            case let (old?, nil):
                result.append(DiffLine(text: "- \(old)", type: .removed))
            case let (old?, new?):
                result.append(DiffLine(text: "- \(old)", type: .removed))
                result.append(DiffLine(text: "+ \(new)", type: .added))
            case (nil, nil):
                break
            }
        }

        return result
    }

    private func calculateDiffStats() -> Int {
        return diffLines.filter { $0.type != .unchanged }.count
    }
}

// MARK: - Diff Line Model

struct DiffLine {
    let text: String
    let type: DiffLineType
}

enum DiffLineType {
    case added
    case removed
    case unchanged
    
    var textColor: Color {
        switch self {
        case .added: return Theme.statusSuccess
        case .removed: return Theme.statusError
        case .unchanged: return Theme.textSecondary
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .added: return Theme.statusSuccess.opacity(0.1)
        case .removed: return Theme.statusError.opacity(0.1)
        case .unchanged: return Color.clear
        }
    }
}

// MARK: - File Write Progress Animation

struct FileWriteProgressView: View {
    let fileName: String
    let fileSize: Int64
    let writtenBytes: Int64
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.statusInfo.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: isCompleted ? "checkmark.circle.fill" : "doc.text.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCompleted ? Theme.statusSuccess : Theme.statusInfo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fileName)

                Text(formatFileSize(writtenBytes) + " / " + formatFileSize(fileSize))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            if !isCompleted {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.statusInfo)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.statusInfo.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Enhanced Tool Execution Animation

struct EnhancedToolExecutionView: View {
    let toolName: String
    let status: ToolExecutionStatus
    let progress: Double?
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: status.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(status.color)
            }

            // Tool info
            VStack(alignment: .leading, spacing: 4) {
                Text(toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(toolName)

                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(detail)
                }

                if let progress = progress, status == .executing {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Theme.bgTertiary)
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(status.color)
                                .frame(width: geometry.size.width * clampedProgress(progress), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            if status == .executing {
                ProgressView()
                    .controlSize(.small)
                    .tint(status.color)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(status.color.opacity(0.2), lineWidth: 1)
        )
    }

    private func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}

// MARK: - Tool Execution Status

enum ToolExecutionStatus {
    case pending
    case executing
    case completed
    case failed
    
    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .executing: return "gear.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return Theme.textTertiary
        case .executing: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .failed: return Theme.statusError
        }
    }
}

// MARK: - Preview

struct FileOperationAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FileOperationAnimationView(
                operationType: .write,
                fileName: "example.swift",
                isCompleted: false
            )

            FileOperationAnimationView(
                operationType: .edit,
                fileName: "README.md",
                isCompleted: true
            )
            
            FileDiffAnimationView(
                oldContent: "func old() {\n    // old code\n}",
                newContent: "func new() {\n    // new code\n    print(\"hello\")\n}",
                isAnimating: true
            )
            
            FileWriteProgressView(
                fileName: "large_file.txt",
                fileSize: 1024 * 1024,
                writtenBytes: 512 * 1024,
                isCompleted: false
            )
        }
        .padding()
        .background(Theme.bgPrimary)
        .previewLayout(.sizeThatFits)
    }
}
