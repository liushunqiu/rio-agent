import SwiftUI

private let brandGreen = Theme.accentPrimary
private let brandGradient = Theme.accentGradient

struct NewChatPage: View {
    @State private var viewModel = NewChatViewModel()
    let onSubmit: (String) -> Void
    let workingDirectory: Binding<String?>

    @FocusState private var isInputFocused: Bool
    @State private var appears = false

    private let maxCardWidth: CGFloat = 700

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(28, geometry.size.height * 0.12))

                        headerArea

                        Spacer().frame(height: 26)

                        inputCard

                        Spacer().frame(height: 12)

                        workingDirectorySection
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
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
                Text("不止聊天，搞定一切")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Text("本地运行、自主规划、安全可控的 AI 工作搭子")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            // 已选择的文件标签
            if !viewModel.selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.selectedFiles, id: \.self) { filePath in
                            FileTag(filePath: filePath) {
                                viewModel.removeFileReference(filePath)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
            }
            
            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty {
                    Text("描述任务，/ 快捷调用，@ 添加上下文")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    TextField("", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(minHeight: 84, maxHeight: 140)
                        .onSubmit {
                            submitIfPossible()
                        }
                        .onChange(of: viewModel.inputText) { oldValue, newValue in
                            viewModel.handleInput(newValue)
                        }

                    sendButton
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                }
            }
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
        .sheet(isPresented: $viewModel.isShowingFilePicker) {
            FilePickerView(workingDirectory: workingDirectory.wrappedValue) { filePath in
                viewModel.addFileReference(filePath)
            }
        }
    }

    private var sendButton: some View {
        Button(action: submitIfPossible) {
            Circle()
                .fill(viewModel.canSend ? brandGreen : Color.primary.opacity(0.08))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(viewModel.canSend ? .white : .secondary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend)
        .scaleEffect(viewModel.canSend ? 1 : 0.92)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: viewModel.canSend)
        .help("发送")
    }

    private var workingDirectorySection: some View {
        Button(action: pickFolder) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(brandGreen)

                Text(folderDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.bgGlass)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var folderDisplayName: String {
        guard let dir = workingDirectory.wrappedValue else { return "选择工作目录" }
        return URL(fileURLWithPath: dir).lastPathComponent
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择工作目录"
        panel.prompt = "选择"
        if let dir = workingDirectory.wrappedValue {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory.wrappedValue = url.path
        #endif
    }

    private func submitIfPossible() {
        guard viewModel.canSend else { return }
        let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.clearInput()
        onSubmit(text)
    }
}

// MARK: - File Tag

struct FileTag: View {
    let filePath: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(brandGreen)
            
            Text(URL(fileURLWithPath: filePath).lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(brandGreen.opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(brandGreen.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - File Picker View

struct FilePickerView: View {
    let workingDirectory: String?
    let onSelect: (String) -> Void
    
    @State private var files: [String] = []
    @State private var isLoading = true
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
            HStack {
                Text("选择文件")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
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
            guard let wd = workingDirectory else { return false }
            return path.hasPrefix(wd) && FileManager.default.fileExists(atPath: path)
        }
    }

    private var emptyStateTitle: String {
        if workingDirectory == nil { return "先选择工作目录" }
        return searchText.isEmpty ? "未找到代码文件" : "未匹配到文件"
    }

    private var emptyStateSubtitle: String? {
        if workingDirectory == nil { return "选择目录后可添加文件上下文" }
        if !searchText.isEmpty { return "尝试不同的关键词或检查拼写" }
        return nil
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
        let query = searchText.lowercased()
        return files.filter { filePath in
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent.lowercased()
            let relativePath = filePath.lowercased()
            // 先匹配文件名, 再匹配路径
            return fileName.contains(query) || relativePath.contains(query)
        }.sorted { a, b in
            // 文件名匹配优先于路径匹配
            let aName = URL(fileURLWithPath: a).lastPathComponent.lowercased()
            let bName = URL(fileURLWithPath: b).lastPathComponent.lowercased()
            let aNameMatch = aName.contains(query)
            let bNameMatch = bName.contains(query)
            if aNameMatch != bNameMatch { return aNameMatch }
            return aName < bName
        }
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
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                files = filePaths.sorted()
                isLoading = false
            }
        }
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
                    
                    Text(relativePath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
        guard let workingDirectory = workingDirectory else { return filePath }
        return filePath.replacingOccurrences(of: workingDirectory + "/", with: "")
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
