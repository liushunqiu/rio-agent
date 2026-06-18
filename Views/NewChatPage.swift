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
                        Spacer().frame(height: max(28, geometry.size.height * 0.12))

                        headerArea

                        Spacer().frame(height: 24)

                        inputCard

                        Spacer().frame(height: 16)

                        workspaceSummary

                        Spacer().frame(height: 18)

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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.bgGlass)
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .stroke(Theme.borderDefault, lineWidth: 1)
                    )
                    .shadow(color: Theme.accentPrimary.opacity(0.20), radius: 18, x: 0, y: 8)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(brandGradient)
            }

            VStack(spacing: 6) {
                Text("开始一个可执行的任务")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
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
                isRemovable: pendingUserDecision == nil,
                removalDisabledReason: "请先完成当前确认，再调整文件上下文"
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

            Divider()
                .overlay(Theme.borderSubtle)

            HStack(spacing: 10) {
                FolderSelector(
                    workingDirectory: workingDirectory,
                    isLocked: pendingUserDecision != nil,
                    lockHelpText: "请先完成当前确认，再调整工作目录"
                )

                Button(action: {
                    composer.isShowingFilePicker = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "at")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加文件")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.bgGlass)
                    .cornerRadius(Theme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(workingDirectory.wrappedValue == nil || pendingUserDecision != nil)
                .opacity(workingDirectory.wrappedValue == nil || pendingUserDecision != nil ? 0.52 : 1)
                .help(filePickerHelpText)

                if !composer.selectedFiles.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                        Text("\(composer.selectedFiles.count) 个上下文")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.bgGlass.opacity(0.75))
                    .cornerRadius(Theme.radiusSM)
                    .help(selectedFileSummaryHelp)
                }

                Spacer()

                ModelBadge(modelName: modelName, providerName: providerName)

                if let pendingDecisionHint {
                    Text(pendingDecisionHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.statusWarning)
                        .lineLimit(1)
                }

                Text(sendHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: maxCardWidth)
        .background(Theme.bgInput.opacity(0.92))
        .cornerRadius(Theme.radiusXL)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXL)
                .stroke(isInputFocused ? brandGreen.opacity(0.42) : Theme.borderDefault, lineWidth: 1)
        )
        .shadow(color: Theme.shadowStrong.opacity(0.7), radius: 28, x: 0, y: 18)
        .padding(.horizontal, 24)
        .filePickerSheet(
            composer: composer,
            workingDirectory: workingDirectory.wrappedValue
        ) {
            inputText = composer.text
        }
    }

    private var sendButton: some View {
        Button(action: submitIfPossible) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                Text("开始")
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
        HStack(spacing: 10) {
            SummaryPill(
                icon: "folder",
                title: "工作区",
                value: currentWorkspaceName,
                tone: workingDirectory.wrappedValue == nil ? Theme.textTertiary : Theme.statusInfo,
                helpText: workingDirectory.wrappedValue
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
                value: composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "等待任务" : "已写入需求",
                tone: canSend ? Theme.statusSuccess : Theme.textTertiary
            )
        }
        .frame(maxWidth: maxCardWidth)
        .padding(.horizontal, 24)
    }

    private var quickPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("直接开始")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accentPrimary)
                .textCase(.uppercase)

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
                    .disabled(pendingUserDecision != nil)
                    .opacity(pendingUserDecision == nil ? 1 : 0.45)
                    .help(pendingUserDecision == nil ? item.prompt : "请先处理当前确认，或直接在输入框写新任务")
                }
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
                    canOpenFilePicker: workingDirectory.wrappedValue != nil && pendingUserDecision == nil
                )
            }
        )
    }

    private var headerSubtitle: String {
        if let path = workingDirectory.wrappedValue {
            return "围绕 \(URL(fileURLWithPath: path).lastPathComponent) 直接开始"
        }
        return "先定任务，再补上下文，然后直接执行"
    }

    private var canSend: Bool {
        composer.canSend && canAcceptInput
    }

    private var currentWorkspaceName: String {
        guard let path = workingDirectory.wrappedValue else { return "未选择目录" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var sendHint: String {
        if pendingUserDecision != nil {
            return canSend ? "Cmd+Return 提交回复" : "等待确认回复"
        }
        return canSend ? "Cmd+Return 发送" : "先写清楚任务"
    }

    private var selectedFileSummaryHelp: String {
        composer.selectedFiles
            .map { PathSecurity.relativePath($0, from: workingDirectory.wrappedValue) }
            .joined(separator: "\n")
    }

    private var pendingDecisionHint: String? {
        guard let pendingUserDecision else { return nil }
        switch pendingUserDecision {
        case .overwriteAgentFile:
            return "回复是/否，或直接输入新任务"
        case .chooseExecutionModeForTask:
            return "回复是继续多 Agent，回复否改为单 Agent"
        }
    }

    private var inputPlaceholder: String {
        guard let pendingUserDecision else {
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
        return "发送 (Cmd+Return)"
    }

    private var filePickerHelpText: String {
        if pendingUserDecision != nil {
            return "请先完成当前确认，再调整文件上下文"
        }
        if workingDirectory.wrappedValue == nil {
            return "先选择工作目录，再添加文件上下文"
        }
        return "添加文件上下文"
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accentPrimary)
                    .frame(width: 18)

                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(Theme.bgGlass.opacity(0.75))
            .cornerRadius(Theme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgGlass.opacity(0.72))
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(tone.opacity(0.16), lineWidth: 1)
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
    @State private var searchText = ""
    @State private var selectedFileIndex: Int? = nil
    @Environment(\.dismiss) private var dismiss
    
    private let recentFilesKey = "recent_files_picker"
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
                    PickerSummaryPill(
                        icon: "doc.text",
                        title: "可选文件",
                        value: fileCountSummary,
                        tone: didHitFileLimit ? Theme.statusWarning : (files.isEmpty ? Theme.textTertiary : Theme.accentPrimary)
                    )
                    PickerSummaryPill(
                        icon: "clock",
                        title: "最近使用",
                        value: "\(recentFiles.count)",
                        tone: recentFiles.isEmpty ? Theme.textTertiary : Theme.statusSuccess
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.bgSecondary)
            
            Divider()
            
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

            if searchText.isEmpty && !recentFiles.isEmpty {
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
                        Text("先在首页或输入框下方选择目录，再回来添加上下文。")
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
            if let idx = selectedFileIndex, idx < filteredFiles.count {
                let filePath = filteredFiles[idx]
                recordRecentFile(filePath)
                onSelect(filePath)
                dismiss()
                return .handled
            }
            return .ignored
        }
    }
    
    private var recentFiles: [String] {
        let saved = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        // 只显示属于当前工作目录且确实存在的文件
        return saved.filter { path in
            PathSecurity.isWithinDirectory(path, workingDirectory: workingDirectory)
                && FileManager.default.fileExists(atPath: path)
        }
    }

    private var emptyStateTitle: String {
        if workingDirectory == nil { return "先选择工作目录" }
        return searchText.isEmpty ? "未找到代码文件" : "未匹配到文件"
    }

    private var emptyStateSubtitle: String? {
        if workingDirectory == nil { return "选择目录后可添加文件上下文" }
        if didHitFileLimit && !searchText.isEmpty { return "当前只搜索已加载的前 \(maxFilesToLoad) 个文件" }
        if !searchText.isEmpty { return "尝试不同的关键词或检查拼写" }
        return nil
    }

    private var fileCountSummary: String {
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
        return "先选择工作目录，再从代码里补充上下文"
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
        guard !searchText.isEmpty else { return files }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return files }

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
        guard let workingDirectory = workingDirectory else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let resourceKeys = [URLResourceKey.nameKey, URLResourceKey.isDirectoryKey]
            
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: workingDirectory),
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else {
                DispatchQueue.main.async {
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
                files = filePaths.sorted {
                    PathSecurity.relativePath($0, from: workingDirectory)
                        .localizedStandardCompare(PathSecurity.relativePath($1, from: workingDirectory)) == .orderedAscending
                }
                didHitFileLimit = hitLimit
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
