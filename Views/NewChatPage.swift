import SwiftUI

private let brandGreen = Color(red: 0.30, green: 0.85, blue: 0.55)
private let brandGradient = LinearGradient(
    colors: [Color(red: 0.25, green: 0.80, blue: 0.50), Color(red: 0.35, green: 0.90, blue: 0.60)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct NewChatPage: View {
    @State private var viewModel = NewChatViewModel()
    let onSubmit: (String) -> Void
    let workingDirectory: Binding<String?>

    @FocusState private var isInputFocused: Bool
    @State private var appears = false

    private let maxCardWidth: CGFloat = 640

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: max(20, geometry.size.height * 0.10))

                        headerArea

                        Spacer()
                            .frame(height: max(20, geometry.size.height * 0.03))

                        inputCard

                        Spacer()
                            .frame(height: 10)

                        workingDirectorySection
                    }
                    .frame(minHeight: geometry.size.height * 0.7)
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
        }
        .background(windowBackground)
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(brandGreen.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(brandGreen.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(brandGradient)
            }

            VStack(spacing: 4) {
                Text("不止聊天，搞定一切")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("本地运行、自主规划、安全可控的 AI 工作搭子")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    TextField("", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(minHeight: 72, maxHeight: 120)
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
        .background(Theme.bgTertiary)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isInputFocused ? brandGreen.opacity(0.35) : Theme.borderDefault, lineWidth: 1)
        )
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
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.03))
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
        let text = viewModel.inputText
        viewModel.clearInput()
        onSubmit(text)
    }

    private var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
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
    @Environment(\.dismiss) private var dismiss
    
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索文件...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bgTertiary)
            
            Divider()
            
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
                    Text("未找到文件")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                List(filteredFiles, id: \.self) { filePath in
                    FileRow(filePath: filePath, workingDirectory: workingDirectory) {
                        onSelect(filePath)
                        dismiss()
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadFiles()
        }
    }
    
    private var filteredFiles: [String] {
        guard !searchText.isEmpty else { return files }
        return files.filter { filePath in
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent.lowercased()
            return fileName.contains(searchText.lowercased())
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
            
            for case let fileURL as URL in enumerator {
                // 跳过目录
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                if resourceValues?.isDirectory == true {
                    continue
                }
                
                // 只包含常见代码文件
                let fileExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "html", "css", "json", 
                                     "md", "txt", "yml", "yaml", "xml", "plist", "xcconfig", "sh",
                                     "rb", "java", "kt", "go", "rs", "c", "cpp", "h", "hpp"]
                
                let fileExtension = fileURL.pathExtension.lowercased()
                if fileExtensions.contains(fileExtension) {
                    filePaths.append(fileURL.path)
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
