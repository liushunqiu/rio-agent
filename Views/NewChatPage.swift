import SwiftUI

private let brandGreen = Theme.accentPrimary
private let brandGradient = Theme.accentGradient

struct NewChatPage: View {
    @Binding var inputText: String
    @State private var composer: ComposerInputState
    let onSubmit: (String) -> Bool
    let workingDirectory: Binding<String?>
    let modelName: String
    let providerName: String
    let canAcceptInput: Bool
    let pendingUserDecision: AgentEngine.PendingUserDecision?

    @FocusState private var isInputFocused: Bool
    @State private var appears = false

    private let maxCardWidth: CGFloat = 700
    private let quickPrompts: [QuickPrompt] = [
        QuickPrompt(
            icon: "square.stack.3d.up.magnifyingglass",
            title: "扫描仓库结构",
            prompt: "深度扫描当前仓库，先总结目录结构、核心模块、关键数据流和潜在风险点。"
        ),
        QuickPrompt(
            icon: "exclamationmark.triangle",
            title: "排查逻辑漏洞",
            prompt: "通读当前代码路径，定位流程漏洞、状态同步问题和潜在回归点，并直接修复。"
        ),
        QuickPrompt(
            icon: "wand.and.stars",
            title: "优化界面交互",
            prompt: "从真实用户体验出发，优化当前界面的信息层级、状态反馈和交互节奏。"
        ),
        QuickPrompt(
            icon: "checkmark.seal",
            title: "实现并验证",
            prompt: "按现有代码风格完成实现，补足必要验证，并明确说明已验证范围。"
        )
    ]

    init(
        inputText: Binding<String>,
        onSubmit: @escaping (String) -> Bool,
        workingDirectory: Binding<String?>,
        modelName: String,
        providerName: String,
        canAcceptInput: Bool = true,
        pendingUserDecision: AgentEngine.PendingUserDecision? = nil
    ) {
        self._inputText = inputText
        self._composer = State(initialValue: ComposerInputState(text: inputText.wrappedValue))
        self.onSubmit = onSubmit
        self.workingDirectory = workingDirectory
        self.modelName = modelName
        self.providerName = providerName
        self.canAcceptInput = canAcceptInput
        self.pendingUserDecision = pendingUserDecision
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(20, geometry.size.height * 0.08))

                        headerArea

                        Spacer().frame(height: 18)

                        inputCard

                        if shouldShowWorkspaceSummary {
                            Spacer().frame(height: 16)

                            workspaceSummary

                            Spacer().frame(height: 18)
                        } else {
                            Spacer().frame(height: 10)
                        }

                        quickPromptSection
                    }
                    .frame(minHeight: geometry.size.height * 0.7)
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
        }
        .background(Color.clear)
        .opacity(appears ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appears = true
            }
            composer.updateText(inputText)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
        .onChange(of: inputText) { _, newValue in
            if composer.text != newValue {
                composer.updateText(newValue)
            }
        }
        .onChange(of: workingDirectory.wrappedValue) { _, newValue in
            composer.removeFileReferencesOutsideWorkingDirectory(newValue)
            inputText = composer.text
        }
    }

    private var headerArea: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.bgGlass)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .stroke(Theme.borderDefault, lineWidth: 1)
                    )
                    .shadow(color: Theme.accentPrimary.opacity(0.10), radius: 8, x: 0, y: 4)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(brandGradient)
            }

            VStack(spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            SelectedFileTags(
                selectedFiles: composer.selectedFiles,
                workingDirectory: workingDirectory.wrappedValue,
                horizontalPadding: 14,
                isRemovable: canEditContext,
                removalDisabledReason: fileContextLockHelpText
            ) { filePath in
                composer.removeFileReference(filePath)
                inputText = composer.text
            }
            
            ZStack(alignment: .topLeading) {
                if composer.text.isEmpty {
                    Text(inputPlaceholder)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    TextField("", text: composerTextBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(minHeight: 84, maxHeight: 140)

                    sendButton
                        .padding(.trailing, 10)
                        .padding(.bottom, 12)
                }
            }

            if let fileContextNotice {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.statusWarning)
                    Text(fileContextNotice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .overlay(Theme.borderSubtle)

            HStack(alignment: .center, spacing: 10) {
                FolderSelector(
                    workingDirectory: workingDirectory,
                    isLocked: !canEditContext,
                    lockHelpText: workingDirectoryLockHelpText
                )

                Button(action: {
                    composer.isShowingFilePicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "at")
                            .font(.system(size: 10, weight: .semibold))
                        Text("添加文件")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.bgGlass.opacity(0.72))
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(workingDirectory.wrappedValue == nil || !canEditContext)
                .opacity(workingDirectory.wrappedValue == nil || !canEditContext ? 0.52 : 1)
                .help(filePickerHelpText)

                if !composer.selectedFiles.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                        Text("\(composer.selectedFiles.count) 个文件")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.bgGlass.opacity(0.58))
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
                    )
                    .lineLimit(1)
                    .help(selectedFileSummaryHelp)
                }

                Spacer()

                ModelBadge(modelName: modelName, providerName: providerName)
                    .frame(maxWidth: 180, alignment: .trailing)
                    .layoutPriority(0)

                if let pendingDecisionHint, pendingUserDecision == nil {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.statusWarning)
                            .padding(.top, 1)

                        Text(pendingDecisionHint)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.statusWarning)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(pendingDecisionHint)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    .layoutPriority(2)
                }

                if let sendHint {
                    Text(sendHint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: maxCardWidth)
        .background(Theme.bgInput.opacity(0.92))
        .cornerRadius(Theme.radiusXL)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXL)
                .stroke(isInputFocused ? brandGreen.opacity(0.42) : Theme.borderDefault, lineWidth: 1)
        )
        .shadow(color: Theme.shadowStrong.opacity(0.52), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 24)
        .filePickerSheet(
            composer: composer,
            workingDirectory: workingDirectory.wrappedValue
        ) {
            inputText = composer.text
        }
        .onChange(of: canEditContext) { _, canEditContext in
            if !canEditContext {
                composer.isShowingFilePicker = false
            }
        }
    }

    private var sendButton: some View {
        Button(action: submitIfPossible) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                Text(sendButtonTitle)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(canSend ? .white : Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(canSend ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Theme.bgGlass))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .scaleEffect(canSend ? 1 : 0.92)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: canSend)
        .help(sendButtonHelp)
    }

    private var workspaceSummary: some View {
        Group {
            if shouldShowCompactStartSummary {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 1)

                    Text(workspaceHelpText)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.bgGlass.opacity(0.48))
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            } else {
                HStack(spacing: 10) {
                    SummaryPill(
                        icon: "folder",
                        title: "工作区",
                        value: currentWorkspaceName,
                        tone: workingDirectory.wrappedValue == nil ? Theme.textTertiary : Theme.statusInfo,
                        helpText: workspaceHelpText
                    )

                    SummaryPill(
                        icon: "paperclip",
                        title: "上下文",
                        value: composer.selectedFiles.isEmpty ? "未附加文件" : "\(composer.selectedFiles.count) 个文件",
                        tone: composer.selectedFiles.isEmpty ? Theme.textTertiary : Theme.accentPrimary
                    )

                    SummaryPill(
                        icon: "text.bubble",
                        title: "输入",
                        value: inputSummaryValue,
                        tone: inputSummaryTone
                    )
                }
            }
        }
        .frame(maxWidth: maxCardWidth)
        .padding(.horizontal, 24)
    }

    private var quickPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(quickPromptSectionTitle)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(quickPromptSectionTone)
                .textCase(.uppercase)

            if pendingUserDecision != nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.statusWarning)
                        .padding(.top, 1)

                    Text("输入“是”或“否”继续，也可以直接写新任务，系统会自动切换。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgGlass.opacity(0.75))
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.statusWarning.opacity(0.18), lineWidth: 1)
                )
            } else if !canAcceptInput {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.statusInfo)
                        .padding(.top, 1)

                    Text("当前任务正在执行。可以先整理下一步草稿，完成或停止后再发送。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgGlass.opacity(0.55))
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.statusInfo.opacity(0.16), lineWidth: 1)
                )
            } else if shouldShowQuickPromptGrid {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 10, alignment: .top)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(quickPrompts) { item in
                        QuickPromptButton(item: item) {
                            composer.updateText(item.prompt)
                            inputText = item.prompt
                            isInputFocused = true
                        }
                        .help(item.prompt)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 1)

                    Text("已开始编辑。发送后会直接执行；清空输入可重新选择模板。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgGlass.opacity(0.55))
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: maxCardWidth, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func submitIfPossible() {
        guard canSend else { return }
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let accepted = onSubmit(text)
        if accepted {
            composer.clearInput()
            inputText = ""
        } else {
            composer.updateText(text)
            inputText = text
        }
    }

    private var composerTextBinding: Binding<String> {
        Binding(
            get: { composer.text },
            set: { newValue in
                inputText = newValue
                composer.updateTextFromUserInput(
                    newValue,
                    canOpenFilePicker: workingDirectory.wrappedValue != nil && canEditContext
                )
            }
        )
    }

    private var headerTitle: String {
        if pendingUserDecision != nil {
            return "等待你的确认"
        }
        if !canAcceptInput {
            return "正在处理"
        }
        return "开始任务"
    }

    private var headerSubtitle: String {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "确认是否覆盖已有 AGENT.md，或直接切换到新任务"
            case .chooseExecutionModeForTask:
                return "确认继续多 Agent 还是改为单 Agent，或直接切换到新任务"
            }
        }
        if let path = workingDirectory.wrappedValue {
            if !canAcceptInput {
                return "\(URL(fileURLWithPath: path).lastPathComponent) 正在执行当前任务"
            }
            return "围绕 \(URL(fileURLWithPath: path).lastPathComponent) 直接开始"
        }
        if !canAcceptInput {
            return "当前任务运行中，完成后可继续输入"
        }
        return "直接写下要做的事"
    }

    private var sendButtonTitle: String {
        if pendingUserDecision != nil { return "提交回复" }
        if !canAcceptInput { return "处理中" }
        return "开始"
    }

    private var canSend: Bool {
        composer.canSend && canAcceptInput
    }

    private var canEditContext: Bool {
        canAcceptInput && pendingUserDecision == nil
    }

    private var shouldShowCompactStartSummary: Bool {
        canAcceptInput
            && pendingUserDecision == nil
            && workingDirectory.wrappedValue == nil
            && composer.selectedFiles.isEmpty
            && trimmedComposerText.isEmpty
    }

    private var shouldShowQuickPromptGrid: Bool {
        canAcceptInput && pendingUserDecision == nil && trimmedComposerText.isEmpty
    }

    private var shouldShowWorkspaceSummary: Bool {
        if pendingUserDecision != nil
            && workingDirectory.wrappedValue == nil
            && composer.selectedFiles.isEmpty
            && trimmedComposerText.isEmpty {
            return false
        }
        return true
    }

    private var currentWorkspaceName: String {
        guard let path = workingDirectory.wrappedValue else { return "未选择目录" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var workspaceHelpText: String {
        guard let path = workingDirectory.wrappedValue else {
            return "可以先直接描述任务；需要引用文件或扫描仓库时，再选择工作目录。"
        }
        return path
    }

    private var sendHint: String? {
        guard pendingUserDecision == nil else { return nil }
        if !canAcceptInput { return "当前任务处理中" }
        return canSend ? "Cmd+Return 发送" : "先写清楚任务"
    }

    private var inputSummaryValue: String {
        let hasInput = !composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if pendingUserDecision != nil {
            return hasInput ? "已填写回复" : "等待确认回复"
        }
        if !canAcceptInput {
            return hasInput ? "已暂存草稿" : "任务处理中"
        }
        return hasInput ? "已写入需求" : "等待任务"
    }

    private var inputSummaryTone: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if !canAcceptInput {
            return Theme.statusInfo
        }
        return canSend ? Theme.statusSuccess : Theme.textTertiary
    }

    private var quickPromptSectionTitle: String {
        if pendingUserDecision != nil { return "当前说明" }
        if !canAcceptInput { return "当前状态" }
        return "任务模板"
    }

    private var quickPromptSectionTone: Color {
        if pendingUserDecision != nil { return Theme.statusWarning }
        if !canAcceptInput { return Theme.statusInfo }
        return Theme.accentPrimary
    }

    private var selectedFileSummaryHelp: String {
        composer.selectedFiles
            .map { PathSecurity.relativePath($0, from: workingDirectory.wrappedValue) }
            .joined(separator: "\n")
    }

    private var fileContextNotice: String? {
        guard composer.text.hasSuffix("@") else { return nil }
        guard canEditContext else { return fileContextLockHelpText }
        guard workingDirectory.wrappedValue == nil else { return nil }
        return "可以先写任务；需要添加文件上下文时，再选择工作目录。"
    }

    private var pendingDecisionHint: String? {
        guard let pendingUserDecision else { return nil }
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "输入是/否，或直接写新任务"
        case .chooseExecutionModeForTask:
            return "输入是继续多 Agent，输入否改单 Agent，或直接写新任务"
        }
    }

    private var inputPlaceholder: String {
        guard let pendingUserDecision else {
            if !canAcceptInput {
                return "当前任务执行中，完成或停止后可继续输入"
            }
            return "把目标、限制和预期结果写清楚"
        }

        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "输入“是”覆盖，输入“否”取消，或直接写新任务"
        case .chooseExecutionModeForTask:
            return "输入“是”用 Multi-Agent，输入“否”改单 Agent，或直接写新任务"
        }
    }

    private var sendButtonHelp: String {
        guard pendingUserDecision == nil else {
            return "提交回复或新任务 (Cmd+Return)"
        }
        if !canAcceptInput {
            return "当前任务执行中，完成或停止后可继续发送"
        }
        return "发送 (Cmd+Return)"
    }

    private var filePickerHelpText: String {
        if !canEditContext {
            return fileContextLockHelpText
        }
        if workingDirectory.wrappedValue == nil {
            return "可以先写任务；需要添加文件上下文时，再选择工作目录"
        }
        return "添加文件上下文"
    }

    private var fileContextLockHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整文件上下文"
        }
        if !canAcceptInput {
            return "当前任务正在执行，完成或停止后再调整文件上下文"
        }
        return "当前状态下无法调整文件上下文"
    }

    private var workingDirectoryLockHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整工作目录"
        }
        if !canAcceptInput {
            return "当前任务正在执行，完成或停止后再调整工作目录"
        }
        return "当前状态下无法调整工作目录"
    }

    private var trimmedComposerText: String {
        composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QuickPrompt: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let prompt: String
}

private struct QuickPromptButton: View {
    let item: QuickPrompt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 16)

                Text(item.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Theme.bgGlass.opacity(0.36))
            .cornerRadius(Theme.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryPill: View {
    let icon: String
    let title: String
    let value: String
    let tone: Color
    var helpText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(helpText ?? value)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass.opacity(0.58))
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(tone.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - File Tag

struct FileTag: View {
    let filePath: String
    let workingDirectory: String?
    var isRemovable: Bool = true
    var removalDisabledReason: String? = nil
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(brandGreen)
            
            Text(displayPath)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isRemovable)
            .opacity(isRemovable ? 1 : 0.45)
            .help(isRemovable ? "移除文件上下文" : (removalDisabledReason ?? "当前状态下无法修改文件上下文"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(brandGreen.opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(brandGreen.opacity(0.3), lineWidth: 1)
        )
        .help(filePath)
    }

    private var displayPath: String {
        PathSecurity.relativePath(filePath, from: workingDirectory)
    }
}

struct SelectedFileTags: View {
    let selectedFiles: [String]
    var workingDirectory: String? = nil
    var horizontalPadding: CGFloat = 16
    var isRemovable: Bool = true
    var removalDisabledReason: String? = nil
    let onRemove: (String) -> Void

    var body: some View {
        if !selectedFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selectedFiles, id: \.self) { filePath in
                        FileTag(
                            filePath: filePath,
                            workingDirectory: workingDirectory,
                            isRemovable: isRemovable,
                            removalDisabledReason: removalDisabledReason
                        ) {
                            onRemove(filePath)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
            }
        }
    }
}

extension View {
    func filePickerSheet(
        composer: ComposerInputState,
        workingDirectory: String?,
        onSelectionApplied: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: Binding(
            get: { composer.isShowingFilePicker },
            set: { composer.isShowingFilePicker = $0 }
        )) {
            FilePickerView(workingDirectory: workingDirectory) { filePath in
                composer.addFileReference(filePath)
                onSelectionApplied()
            }
        }
    }
}

// MARK: - File Picker View

struct FilePickerView: View {
    let workingDirectory: String?
    let onSelect: (String) -> Void
    
    @State private var files: [String] = []
    @State private var isLoading = true
    @State private var didHitFileLimit = false
    @State private var loadingFailed = false
    @State private var searchText = ""
    @State private var selectedFileIndex: Int? = nil
    @State private var activeLoadRequestID: UUID?
    @Environment(\.dismiss) private var dismiss
    
    private let legacyRecentFilesKey = "recent_files_picker"
    private let maxRecentFiles = 5
    private let maxFilesToLoad = 2_000
    private let excludedDirectoryNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules",
        "dist", "coverage", ".next", ".nuxt", ".venv", "venv", "__pycache__"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("选择文件")
                            .font(.system(size: 16, weight: .semibold))
                        Text(headerSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Spacer()

                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    PickerSummaryPill(
                        icon: "folder",
                        title: "工作区",
                        value: workspaceName,
                        tone: workingDirectory == nil ? Theme.textTertiary : Theme.statusInfo,
                        helpText: workingDirectory
                    )
                    if hasWorkingDirectory {
                        PickerSummaryPill(
                            icon: "doc.text",
                            title: "可选文件",
                            value: fileCountSummary,
                            tone: didHitFileLimit ? Theme.statusWarning : (files.isEmpty ? Theme.textTertiary : Theme.accentPrimary)
                        )
                    }
                    if shouldShowRecentFilesSummary {
                        PickerSummaryPill(
                            icon: "clock",
                            title: "最近使用",
                            value: "\(recentFiles.count)",
                            tone: Theme.statusSuccess
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.bgSecondary)
            
            Divider()

            if hasWorkingDirectory {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索文件... (支持模糊匹配)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: searchText) { _, _ in
                            selectedFileIndex = nil
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.bgTertiary)
                
                Divider()
                
                // Recent files section (when no search)
                if didHitFileLimit {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.statusWarning)
                            .padding(.top, 2)
                        Text("文件列表已截断到前 \(maxFilesToLoad) 个结果。搜索只覆盖当前已加载列表；如果没找到，请缩小工作目录或直接输入 @file: 绝对路径。")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.statusWarning.opacity(0.08))

                    Divider()
                }

                if !isSearching && !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("最近使用")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.bgTertiary.opacity(0.5))
                        
                        ForEach(recentFiles, id: \.self) { filePath in
                            FileRow(filePath: filePath, workingDirectory: workingDirectory) {
                                recordRecentFile(filePath)
                                onSelect(filePath)
                                dismiss()
                            }
                        }
                    }
                    
                    Divider()
                }
            }
            
            // File list
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("加载文件列表...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if filteredFiles.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(emptyStateTitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    if let subtitle = emptyStateSubtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 4)
                    }
                    if workingDirectory == nil {
                        Text("可以先关闭这里继续写任务；需要文件上下文时，再从输入框下方选择目录。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            } else {
                List(Array(filteredFiles.enumerated()), id: \.element) { index, filePath in
                    FileRow(filePath: filePath, workingDirectory: workingDirectory) {
                        recordRecentFile(filePath)
                        onSelect(filePath)
                        dismiss()
                    }
                    .background(selectedFileIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 540, height: 460)
        .onAppear {
            loadFiles()
        }
        .onChange(of: workingDirectory) { _, _ in
            loadFiles()
        }
        .onKeyPress(.upArrow) {
            guard !filteredFiles.isEmpty else { return .ignored }
            let newIndex = max(0, (selectedFileIndex ?? 0) - 1)
            selectedFileIndex = newIndex
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !filteredFiles.isEmpty else { return .ignored }
            let newIndex = min(filteredFiles.count - 1, (selectedFileIndex ?? -1) + 1)
            selectedFileIndex = newIndex
            return .handled
        }
        .onKeyPress(.return) {
            guard !filteredFiles.isEmpty else { return .ignored }
            let idx = min(selectedFileIndex ?? 0, filteredFiles.count - 1)
            let filePath = filteredFiles[idx]
            recordRecentFile(filePath)
            onSelect(filePath)
            dismiss()
            return .handled
        }
    }
    
    private var recentFiles: [String] {
        let saved = storedRecentFiles
        // 只显示属于当前工作目录且确实存在的文件
        return saved.filter { path in
            PathSecurity.isWithinDirectory(path, workingDirectory: workingDirectory)
                && FileManager.default.fileExists(atPath: path)
        }
    }

    private var recentFilesKey: String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return legacyRecentFilesKey
        }

        let workspaceKey = Data(PathSecurity.normalizedPath(workingDirectory).utf8)
            .base64EncodedString()
        return "\(legacyRecentFilesKey).\(workspaceKey)"
    }

    private var storedRecentFiles: [String] {
        let scopedFiles = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        guard scopedFiles.isEmpty, recentFilesKey != legacyRecentFilesKey else {
            return scopedFiles
        }
        return UserDefaults.standard.stringArray(forKey: legacyRecentFilesKey) ?? []
    }

    private func migrateLegacyRecentFilesIfNeeded() {
        guard recentFilesKey != legacyRecentFilesKey else { return }
        let scopedFiles = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        guard scopedFiles.isEmpty else { return }

        let legacyFiles = UserDefaults.standard.stringArray(forKey: legacyRecentFilesKey) ?? []
        var migratedFiles: [String] = []
        for path in legacyFiles {
            let normalizedPath = PathSecurity.normalizedPath(path)
            guard PathSecurity.isWithinDirectory(normalizedPath, workingDirectory: workingDirectory),
                  FileManager.default.fileExists(atPath: normalizedPath),
                  !migratedFiles.contains(normalizedPath) else {
                continue
            }

            migratedFiles.append(normalizedPath)
            if migratedFiles.count >= maxRecentFiles {
                break
            }
        }

        if !migratedFiles.isEmpty {
            UserDefaults.standard.set(migratedFiles, forKey: recentFilesKey)
        }
    }

    private var hasWorkingDirectory: Bool {
        workingDirectory != nil
    }

    private var shouldShowRecentFilesSummary: Bool {
        hasWorkingDirectory && !recentFiles.isEmpty
    }

    private var emptyStateTitle: String {
        if workingDirectory == nil { return "还没有工作目录" }
        if loadingFailed { return "暂时无法读取文件" }
        if didHitFileLimit && isSearching { return "未匹配到已加载文件" }
        return isSearching ? "未匹配到文件" : "未找到代码文件"
    }

    private var emptyStateSubtitle: String? {
        if workingDirectory == nil { return "可以先写任务；需要文件上下文时再选择目录" }
        if loadingFailed { return "检查工作目录权限或路径是否仍然可用，然后重新打开这里" }
        if didHitFileLimit && isSearching { return "当前只搜索已加载的前 \(maxFilesToLoad) 个文件；如果没找到，请缩小工作目录或直接输入 @file: 绝对路径" }
        if isSearching { return "尝试不同的关键词或检查拼写" }
        return nil
    }

    private var fileCountSummary: String {
        if workingDirectory == nil { return "待选择" }
        if isLoading { return "加载中" }
        return didHitFileLimit ? "\(files.count)+" : "\(files.count)"
    }

    private var workspaceName: String {
        guard let workingDirectory else { return "未选择目录" }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    private var headerSubtitle: String {
        if let workingDirectory {
            return "从 \(URL(fileURLWithPath: workingDirectory).lastPathComponent) 中挑选需要的上下文"
        }
        return "需要文件上下文时，再选择工作目录"
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }
    
    private func recordRecentFile(_ path: String) {
        var saved = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        saved.removeAll { $0 == path }
        saved.insert(path, at: 0)
        if saved.count > maxRecentFiles {
            saved = Array(saved.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(saved, forKey: recentFilesKey)
    }
    
    private var filteredFiles: [String] {
        guard isSearching else { return files }
        let query = trimmedSearchText.lowercased()

        return files
            .compactMap { filePath -> (path: String, rank: Int, relativePath: String)? in
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent.lowercased()
                let relativePath = displayRelativePath(for: filePath).lowercased()
                guard let rank = searchRank(fileName: fileName, relativePath: relativePath, query: query) else {
                    return nil
                }
                return (filePath, rank, relativePath)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
            .map(\.path)
    }

    private func displayRelativePath(for filePath: String) -> String {
        PathSecurity.relativePath(filePath, from: workingDirectory)
    }

    private func searchRank(fileName: String, relativePath: String, query: String) -> Int? {
        if fileName.hasPrefix(query) { return 0 }
        if fileName.contains(query) { return 1 }
        if relativePath.hasPrefix(query) { return 2 }
        if relativePath.contains(query) { return 3 }
        return nil
    }
    
    private func loadFiles() {
        migrateLegacyRecentFilesIfNeeded()

        let requestID = UUID()
        activeLoadRequestID = requestID
        selectedFileIndex = nil
        files = []
        didHitFileLimit = false
        loadingFailed = false
        isLoading = true

        guard let workingDirectory = workingDirectory else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let resourceKeys = [URLResourceKey.nameKey, URLResourceKey.isDirectoryKey]
            var encounteredEnumerationError = false
            
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: workingDirectory),
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    encounteredEnumerationError = true
                    return true
                }
            ) else {
                DispatchQueue.main.async {
                    guard activeLoadRequestID == requestID, self.workingDirectory == workingDirectory else { return }
                    loadingFailed = true
                    isLoading = false
                }
                return
            }
            
            var filePaths: [String] = []
            var hitLimit = false
            let fileExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "html", "css", "json", 
                                 "md", "txt", "yml", "yaml", "xml", "plist", "xcconfig", "sh",
                                 "rb", "java", "kt", "go", "rs", "c", "cpp", "h", "hpp",
                                 "toml", "env", "cfg", "ini", "vue", "svelte", "astro"]
            
            for case let fileURL as URL in enumerator {
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                if resourceValues?.isDirectory == true {
                    if excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                
                let fileExtension = fileURL.pathExtension.lowercased()
                if fileExtensions.contains(fileExtension) {
                    filePaths.append(fileURL.path)
                    if filePaths.count >= maxFilesToLoad {
                        hitLimit = true
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                guard activeLoadRequestID == requestID, self.workingDirectory == workingDirectory else { return }
                files = filePaths.sorted {
                    PathSecurity.relativePath($0, from: workingDirectory)
                        .localizedStandardCompare(PathSecurity.relativePath($1, from: workingDirectory)) == .orderedAscending
                }
                didHitFileLimit = hitLimit
                loadingFailed = filePaths.isEmpty && encounteredEnumerationError
                isLoading = false
            }
        }
    }
}

private struct PickerSummaryPill: View {
    let icon: String
    let title: String
    let value: String
    let tone: Color
    var helpText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(helpText ?? value)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass.opacity(0.7))
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(tone.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - File Row

struct FileRow: View {
    let filePath: String
    let workingDirectory: String?
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: fileIcon)
                    .font(.system(size: 14))
                    .foregroundColor(fileIconColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(filePath)
                    
                    Text(relativePath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(filePath)
                }
                
                Spacer()
                
                Text(fileExtension.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension
    }
    
    private var relativePath: String {
        PathSecurity.relativePath(filePath, from: workingDirectory)
    }
    
    private var fileIcon: String {
        switch fileExtension.lowercased() {
        case "swift":
            return "swift"
        case "py":
            return "text.document"
        case "js", "ts", "jsx", "tsx":
            return "javascript"
        case "html", "css":
            return "globe"
        case "json", "plist":
            return "curlybraces"
        case "md":
            return "text.quote"
        case "txt":
            return "doc.text"
        case "yml", "yaml":
            return "gearshape.2"
        case "sh":
            return "terminal"
        default:
            return "doc"
        }
    }
    
    private var fileIconColor: Color {
        switch fileExtension.lowercased() {
        case "swift":
            return .orange
        case "py":
            return .blue
        case "js", "ts", "jsx", "tsx":
            return .yellow
        case "html", "css":
            return .purple
        case "json", "plist":
            return .green
        case "md":
            return .gray
        default:
            return .secondary
        }
    }
}
