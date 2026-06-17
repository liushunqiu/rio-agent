import SwiftUI

// MARK: - Enhanced Tool Call Card

struct EnhancedToolCallCard: View {
    let toolCall: ToolCall
    let isExecuting: Bool
    let isCompleted: Bool
    let executionResult: ToolResult?
    
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Tool icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(toolIconBackgroundColor)
                            .frame(width: 32, height: 32)

                        Image(systemName: toolIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(toolIconColor)
                    }
                    
                    // Tool info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toolCall.name)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                        
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.statusInfo)
                    } else if isCompleted {
                        Image(systemName: completedIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(completedColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                Divider()
                    .overlay(Theme.borderSubtle)
                
                VStack(alignment: .leading, spacing: 10) {
                    // Arguments
                    if !toolCall.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("参数")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                            
                            ForEach(Array(toolCall.arguments.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(key)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.accentPrimary)
                                        .frame(minWidth: 80, alignment: .leading)
                                    
                                    Text(String(describing: value.value))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    
                    // Execution result
                    if let result = executionResult, isCompleted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("结果")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                            
                            Text(result.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.codeBackground)
                                .cornerRadius(Theme.radiusSM)
                        }
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }
    
    // MARK: - Computed Properties
    
    private var toolIcon: String {
        if isCompleted {
            return completedIcon
        } else if isExecuting {
            return "gear.circle.fill"
        } else {
            return "terminal"
        }
    }
    
    private var toolIconColor: Color {
        if isCompleted {
            return completedColor
        } else if isExecuting {
            return Theme.statusInfo
        } else {
            return Theme.statusWarning
        }
    }
    
    private var toolIconBackgroundColor: Color {
        return toolIconColor.opacity(0.15)
    }
    
    private var statusText: String {
        if isCompleted {
            switch executionResult?.status {
            case .success: return "执行成功"
            case .error: return "执行失败"
            case .cancelled: return "已取消"
            case .none: return "已完成"
            }
        } else if isExecuting {
            return "执行中..."
        } else {
            return "等待执行"
        }
    }
    
    private var statusColor: Color {
        if isCompleted {
            return completedColor
        } else if isExecuting {
            return Theme.statusInfo
        } else {
            return Theme.textTertiary
        }
    }
    
    private var cardBackgroundColor: Color {
        if isCompleted {
            switch executionResult?.status {
            case .success: return Theme.statusSuccess.opacity(0.06)
            case .error: return Theme.statusError.opacity(0.06)
            case .cancelled: return Theme.textTertiary.opacity(0.06)
            case .none: return Theme.toolCallBg
            }
        } else if isExecuting {
            return Theme.statusInfo.opacity(0.06)
        } else {
            return Theme.toolCallBg
        }
    }
    
    private var cardBorderColor: Color {
        if isCompleted {
            switch executionResult?.status {
            case .success: return Theme.statusSuccess.opacity(0.3)
            case .error: return Theme.statusError.opacity(0.3)
            case .cancelled: return Theme.textTertiary.opacity(0.3)
            case .none: return Theme.toolCallBorder
            }
        } else if isExecuting {
            return Theme.statusInfo.opacity(0.3)
        } else {
            return Theme.toolCallBorder
        }
    }

    private var completedIcon: String {
        switch executionResult?.status {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .none: return "checkmark.circle.fill"
        }
    }

    private var completedColor: Color {
        switch executionResult?.status {
        case .success: return Theme.statusSuccess
        case .error: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        case .none: return Theme.statusSuccess
        }
    }
    
}

// MARK: - Enhanced Tool Result Card

struct EnhancedToolResultCard: View {
    let result: ToolResult
    let toolCallName: String
    
    @State private var isExpanded = false

    private let collapsedOutputLineLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Status icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: statusIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                    
                    // Result info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toolCallName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                        
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor)
                    }
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                Divider()
                    .overlay(Theme.borderSubtle)
                
                VStack(alignment: .leading, spacing: 10) {
                    // Output
                    if !result.output.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("输出")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.textSecondary)

                                Spacer()

                                if shouldCollapseOutput {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            isExpanded.toggle()
                                        }
                                    }) {
                                        Text(isExpanded ? "收起" : "展开全部")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Text(result.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .textSelection(.enabled)
                                .lineLimit(isExpanded || result.status == .error ? nil : collapsedOutputLineLimit)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.codeBackground)
                                .cornerRadius(Theme.radiusSM)
                        }
                    }
                    
                    // Error
                    if let error = result.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("错误")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.statusError)
                            
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.statusError)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.statusError.opacity(0.1))
                                .cornerRadius(Theme.radiusSM)
                        }
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        switch result.status {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch result.status {
        case .success: return Theme.statusSuccess
        case .error: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        }
    }
    
    private var statusText: String {
        switch result.status {
        case .success: return "执行成功"
        case .error: return "执行失败"
        case .cancelled: return "已取消"
        }
    }
    
    private var cardBackgroundColor: Color {
        switch result.status {
        case .success: return Theme.statusSuccess.opacity(0.06)
        case .error: return Theme.statusError.opacity(0.06)
        case .cancelled: return Theme.textTertiary.opacity(0.06)
        }
    }
    
    private var cardBorderColor: Color {
        switch result.status {
        case .success: return Theme.statusSuccess.opacity(0.3)
        case .error: return Theme.statusError.opacity(0.3)
        case .cancelled: return Theme.textTertiary.opacity(0.3)
        }
    }

    private var shouldCollapseOutput: Bool {
        result.output.components(separatedBy: .newlines).count > collapsedOutputLineLimit
            || result.output.count > 1000
    }
}

// MARK: - File Operation Tool Card

struct FileOperationToolCard: View {
    let toolCall: ToolCall
    let isExecuting: Bool
    let isCompleted: Bool
    let executionResult: ToolResult?
    
    @State private var showFileAnimation = false
    @State private var showDiffAnimation = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Enhanced tool call card
            EnhancedToolCallCard(
                toolCall: toolCall,
                isExecuting: isExecuting,
                isCompleted: isCompleted,
                executionResult: executionResult
            )
            
            // File operation animation
            if isExecuting || isCompleted {
                if shouldShowFileAnimation {
                    FileOperationAnimationView(
                        operationType: fileOperationType,
                        fileName: extractFileName(),
                        isCompleted: isCompleted
                    )
                    .transition(.opacity.combined(with: .scale))
                }
                
                // Diff animation for edit operations
                if shouldShowDiffAnimation, let oldText = toolCall.arguments["old_text"]?.value as? String,
                   let newText = toolCall.arguments["new_text"]?.value as? String {
                    FileDiffAnimationView(
                        oldContent: oldText,
                        newContent: newText,
                        isAnimating: isExecuting
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExecuting)
        .animation(.easeInOut(duration: 0.3), value: isCompleted)
    }
    
    // MARK: - Helper Properties
    
    private var shouldShowFileAnimation: Bool {
        let name = toolCall.name.lowercased()
        return name.contains("write") || name.contains("create") || name.contains("edit")
    }
    
    private var shouldShowDiffAnimation: Bool {
        let name = toolCall.name.lowercased()
        return name.contains("edit") && toolCall.arguments["old_text"] != nil && toolCall.arguments["new_text"] != nil
    }
    
    private var fileOperationType: FileOperationType {
        let name = toolCall.name.lowercased()
        if name.contains("write") || name.contains("create") {
            return .create
        } else if name.contains("edit") {
            return .edit
        } else if name.contains("delete") {
            return .delete
        } else {
            return .write
        }
    }
    
    private func extractFileName() -> String {
        if let path = toolCall.arguments["path"]?.value as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        } else if let filePath = toolCall.arguments["file_path"]?.value as? String {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        return "file"
    }
}

// MARK: - Preview

struct EnhancedToolCallCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            EnhancedToolCallCard(
                toolCall: ToolCall(id: "1", name: "write_file", arguments: [
                    "path": AnyCodable("/path/to/file.swift"),
                    "content": AnyCodable("print(\"Hello, World!\")")
                ]),
                isExecuting: false,
                isCompleted: false,
                executionResult: nil
            )
            
            EnhancedToolCallCard(
                toolCall: ToolCall(id: "2", name: "edit_file", arguments: [
                    "path": AnyCodable("/path/to/file.swift"),
                    "old_text": AnyCodable("old text"),
                    "new_text": AnyCodable("new text")
                ]),
                isExecuting: true,
                isCompleted: false,
                executionResult: nil
            )
            
            EnhancedToolResultCard(
                result: .success(toolCallId: "1", output: "文件写入成功"),
                toolCallName: "write_file"
            )
        }
        .padding()
        .background(Theme.bgPrimary)
        .previewLayout(.sizeThatFits)
    }
}
