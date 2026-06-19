import SwiftUI
import AppKit

enum ToolResultDisplay {
    static let emptyOutputPlaceholder = "工具执行完成，但没有返回输出。"
    private static let collapsedOutputLineLimit = 8

    static func label(for result: ToolResult) -> String {
        switch result.status {
        case .success:
            return "输出"
        case .error:
            return "错误"
        case .cancelled:
            return "取消原因"
        }
    }

    static func text(for result: ToolResult) -> String {
        switch result.status {
        case .success:
            return result.output.isEmpty ? emptyOutputPlaceholder : result.output
        case .error, .cancelled:
            if let error = result.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                return error
            }
            return result.output.isEmpty ? emptyOutputPlaceholder : result.output
        }
    }

    static func shouldCollapse(_ result: ToolResult) -> Bool {
        let displayText = text(for: result)
        return displayText.components(separatedBy: .newlines).count > collapsedOutputLineLimit
            || displayText.count > 1000
    }
}

struct ToolResultOutputBlock: View {
    let result: ToolResult
    var fontSize: CGFloat = 11
    var contentPadding: CGFloat = 8

    @State private var isOutputExpanded = false
    @State private var didCopy = false
    @State private var copyResetID: UUID?

    private let collapsedOutputLineLimit = 8
    private var displayText: String { ToolResultDisplay.text(for: result) }
    private var shouldCollapse: Bool { ToolResultDisplay.shouldCollapse(result) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ToolResultDisplay.label(for: result))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(labelColor)

                Spacer()

                if shouldCollapse {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isOutputExpanded.toggle()
                        }
                    }) {
                        Text(isOutputExpanded ? "收起" : "展开全部")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(isOutputExpanded ? "收起长输出" : "展开完整输出")
                }

                Button(action: copyDisplayText) {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .bold))
                        Text(didCopy ? "已复制" : "复制")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(didCopy ? Theme.statusSuccess : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("复制完整\(ToolResultDisplay.label(for: result))")
            }

            Text(displayText)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(textColor)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
                .padding(contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(result.status == .error ? Theme.statusError.opacity(0.10) : Theme.codeBackground)
                .cornerRadius(Theme.radiusSM)
        }
        .onChange(of: displayText) { _, _ in
            isOutputExpanded = false
            didCopy = false
            copyResetID = nil
        }
    }

    private var lineLimit: Int? {
        if result.status == .error || isOutputExpanded {
            return nil
        }
        return collapsedOutputLineLimit
    }

    private var labelColor: Color {
        result.status == .error ? Theme.statusError : Theme.textSecondary
    }

    private var textColor: Color {
        result.status == .error ? Theme.statusError : Theme.textSecondary
    }

    private func copyDisplayText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText, forType: .string)
        let resetID = UUID()
        copyResetID = resetID
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard copyResetID == resetID else { return }
            didCopy = false
            copyResetID = nil
        }
    }
}

struct ToolArgumentRow: View {
    let name: String
    let value: Any
    var keyWidth: CGFloat = 80
    var fontSize: CGFloat = 11
    var initiallyExpanded = false

    @State private var isExpanded: Bool
    @State private var didCopy = false
    @State private var copyResetID: UUID?

    init(name: String, value: Any, keyWidth: CGFloat = 80, fontSize: CGFloat = 11, initiallyExpanded: Bool = false) {
        self.name = name
        self.value = value
        self.keyWidth = keyWidth
        self.fontSize = fontSize
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var displayValue: String {
        String(describing: value)
    }

    private var shouldCollapse: Bool {
        displayValue.count > 140 || displayValue.components(separatedBy: .newlines).count > 3
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.accentPrimary)
                .frame(width: keyWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayValue)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(shouldCollapse && !isExpanded ? 3 : nil)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(displayValue)

                if shouldCollapse {
                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Label(isExpanded ? "收起" : "展开", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.textTertiary)
                        .help(isExpanded ? "收起参数" : "展开完整参数")

                        Button(action: copyValue) {
                            Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(didCopy ? Theme.statusSuccess : Theme.textTertiary)
                        .help("复制完整参数")
                    }
                }
            }
        }
        .onChange(of: displayValue) { _, _ in
            isExpanded = initiallyExpanded
            didCopy = false
            copyResetID = nil
        }
    }

    private func copyValue() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayValue, forType: .string)
        let resetID = UUID()
        copyResetID = resetID
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard copyResetID == resetID else { return }
            didCopy = false
            copyResetID = nil
        }
    }
}

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
                                ToolArgumentRow(name: key, value: value.value)
                            }
                        }
                    }
                    
                    // Execution result
                    if let result = executionResult, isCompleted {
                        ToolResultOutputBlock(result: result)
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
                    ToolResultOutputBlock(result: result)
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
