import Foundation

/// Manages agent's memory for learning and adaptation
@MainActor
class AgentMemory: ObservableObject {
    struct MemoryNote: Equatable, Identifiable {
        let id: String
        let summary: String
        let body: [String]

        init(id: String = UUID().uuidString, summary: String, body: [String]) {
            self.id = id
            self.summary = summary
            self.body = body
        }
    }
    
    // MARK: - Memory Types
    
    /// Short-term memory: current session context
    struct SessionMemory {
        var recentFiles: [String] = []
        var recentCommands: [String] = []
        var currentTask: String?
        var userPreferences: [String: String] = [:]
        var workingPatterns: [String: Int] = [:] // tool -> usage count
    }
    
    /// Long-term memory: persistent user preferences and patterns
    struct LongTermMemory: Codable {
        var preferredTools: [String: String] = [:] // task_type -> preferred_tool
        var codingStyle: CodingStyle = CodingStyle()
        var projectKnowledge: [String: ProjectKnowledge] = [:] // project_path -> knowledge
        var errorPatterns: [ErrorPattern] = []
        var userCorrections: [UserCorrection] = []
    }
    
    struct CodingStyle: Codable {
        var indentStyle: String = "spaces" // "spaces" or "tabs"
        var indentSize: Int = 4
        var lineEnding: String = "lf" // "lf" or "crlf"
        var preferredLanguage: String = "en" // "en", "zh", etc.
        var commentStyle: String = "line" // "line" or "block"
    }
    
    struct ProjectKnowledge: Codable {
        var framework: String?
        var buildSystem: String?
        var testFramework: String?
        var keyFiles: [String] = []
        var commonCommands: [String] = []
        var lastAccessed: Date = Date()
    }
    
    struct ErrorPattern: Codable {
        let errorType: String
        let context: String
        let solution: String
        let timestamp: Date
        var successCount: Int = 0
    }
    
    struct UserCorrection: Codable {
        let originalAction: String
        let correctedAction: String
        let reason: String
        let timestamp: Date
    }
    
    // MARK: - Properties
    
    @Published var session: SessionMemory = SessionMemory()
    @Published private(set) var persistedNotes: [MemoryNote] = []
    private var longTerm: LongTermMemory = LongTermMemory()

    private let userDefaults: UserDefaults
    private let memoryKey: String
    private let customMarkdownURL: URL?
    private let maxRecentItems = 20
    private let maxErrorPatterns = 100
    private let markdownFileName = "MEMORY.md"
    
    // MARK: - Initialization
    
    init(
        userDefaults: UserDefaults = .standard,
        memoryKey: String = "agent_long_term_memory",
        markdownURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.memoryKey = memoryKey
        self.customMarkdownURL = markdownURL
        loadLongTermMemory()
        loadMemoryMarkdown()
        refreshPersistedNotes()
    }
    
    // MARK: - Session Memory Methods
    
    /// Record a file access
    func recordFileAccess(_ path: String) {
        session.recentFiles.removeAll { $0 == path }
        session.recentFiles.insert(path, at: 0)
        if session.recentFiles.count > maxRecentItems {
            session.recentFiles.removeLast()
        }
    }
    
    /// Record a command execution
    func recordCommand(_ command: String) {
        session.recentCommands.removeAll { $0 == command }
        session.recentCommands.insert(command, at: 0)
        if session.recentCommands.count > maxRecentItems {
            session.recentCommands.removeLast()
        }
    }
    
    /// Record tool usage
    func recordToolUsage(_ toolName: String) {
        session.workingPatterns[toolName, default: 0] += 1
    }
    
    /// Set current task context
    func setCurrentTask(_ task: String?) {
        session.currentTask = task
    }
    
    /// Get most used tools in this session
    func getMostUsedTools(limit: Int = 5) -> [(tool: String, count: Int)] {
        return session.workingPatterns
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (tool: $0.key, count: $0.value) }
    }
    
    // MARK: - Long-term Memory Methods
    
    /// Record a successful tool usage pattern
    func recordSuccessfulPattern(taskType: String, tool: String) {
        longTerm.preferredTools[taskType] = tool
        saveLongTermMemory()
        upsertMemoryNote(
            summary: "【摘要】任务类型 \(taskType) 优先使用 \(tool)",
            body: [
                "- 验证过的正确做法：在任务类型 \(taskType) 下，\(tool) 是稳定的首选工具。",
                "- 为什么重要：减少不必要的工具试探，降低重复失败概率。"
            ]
        )
    }
    
    /// Get preferred tool for a task type
    func getPreferredTool(for taskType: String) -> String? {
        return longTerm.preferredTools[taskType]
    }

    /// Get all preferred tools mapping
    func getAllPreferredTools() -> [String: String] {
        return longTerm.preferredTools
    }
    
    /// Learn from user correction
    func learnFromCorrection(original: String, corrected: String, reason: String) {
        let correction = UserCorrection(
            originalAction: original,
            correctedAction: corrected,
            reason: reason,
            timestamp: Date()
        )
        longTerm.userCorrections.append(correction)
        
        // Keep only recent corrections
        if longTerm.userCorrections.count > 50 {
            longTerm.userCorrections.removeFirst()
        }
        
        saveLongTermMemory()
        upsertMemoryNote(
            summary: "【摘要】用户纠正：\(original) 应改为 \(corrected)",
            body: [
                "- 纠错内容：\(original)",
                "- 验证过的正确做法：\(corrected)",
                "- 为什么重要：\(reason)"
            ]
        )
    }
    
    /// Get relevant user corrections
    func getRelevantCorrections(for action: String) -> [UserCorrection] {
        return longTerm.userCorrections.filter { correction in
            correction.originalAction.lowercased().contains(action.lowercased()) ||
            action.lowercased().contains(correction.originalAction.lowercased())
        }
    }
    
    /// Record error pattern and solution
    func recordErrorPattern(error: String, context: String, solution: String) {
        let pattern = ErrorPattern(
            errorType: error,
            context: context,
            solution: solution,
            timestamp: Date()
        )
        longTerm.errorPatterns.append(pattern)
        
        // Keep only recent patterns
        if longTerm.errorPatterns.count > maxErrorPatterns {
            longTerm.errorPatterns.removeFirst()
        }
        
        saveLongTermMemory()
    }
    
    /// Find similar error patterns
    func findSimilarErrors(_ error: String) -> [ErrorPattern] {
        let errorLower = error.lowercased()
        return longTerm.errorPatterns.filter { pattern in
            pattern.errorType.lowercased().contains(errorLower) ||
            errorLower.contains(pattern.errorType.lowercased())
        }
        .sorted { $0.successCount > $1.successCount }
    }
    
    /// Record successful error resolution
    func recordErrorSuccess(_ pattern: ErrorPattern) {
        if let index = longTerm.errorPatterns.firstIndex(where: { 
            $0.errorType == pattern.errorType && $0.context == pattern.context 
        }) {
            longTerm.errorPatterns[index].successCount += 1
            saveLongTermMemory()
            upsertMemoryNote(
                summary: "【摘要】错误 \(pattern.errorType) 的修复路径已验证有效",
                body: [
                    "- 错误上下文：\(pattern.context)",
                    "- 验证过的正确做法：\(pattern.solution.isEmpty ? "按后续成功执行路径修复。" : pattern.solution)",
                    "- 为什么重要：相同或相似错误再次出现时可直接复用。"
                ]
            )
        }
    }
    
    // MARK: - Project Knowledge
    
    /// Record knowledge about a project
    func recordProjectKnowledge(path: String, knowledge: ProjectKnowledge) {
        longTerm.projectKnowledge[path] = knowledge
        saveLongTermMemory()
    }
    
    /// Get knowledge about a project
    func getProjectKnowledge(path: String) -> ProjectKnowledge? {
        return longTerm.projectKnowledge[path]
    }
    
    /// Update project access time
    func updateProjectAccess(path: String) {
        if var knowledge = longTerm.projectKnowledge[path] {
            knowledge.lastAccessed = Date()
            longTerm.projectKnowledge[path] = knowledge
            saveLongTermMemory()
        }
    }
    
    // MARK: - Coding Style
    
    /// Update coding style preferences
    func updateCodingStyle(_ style: CodingStyle) {
        longTerm.codingStyle = style
        saveLongTermMemory()
    }
    
    /// Get current coding style
    func getCodingStyle() -> CodingStyle {
        return longTerm.codingStyle
    }
    
    /// Infer coding style from file content
    func inferCodingStyle(from content: String, filename: String) {
        var style = longTerm.codingStyle
        
        // Detect indentation
        let lines = content.components(separatedBy: .newlines)
        var spaceCount = 0
        var tabCount = 0
        
        for line in lines.prefix(50) { // Check first 50 lines
            if line.hasPrefix("\t") {
                tabCount += 1
            } else if line.hasPrefix("    ") || line.hasPrefix("  ") {
                spaceCount += 1
            }
        }
        
        if tabCount > spaceCount {
            style.indentStyle = "tabs"
        } else {
            style.indentStyle = "spaces"
            // Detect indent size
            if content.contains("    ") {
                style.indentSize = 4
            } else if content.contains("  ") {
                style.indentSize = 2
            }
        }
        
        // Detect line endings
        if content.contains("\r\n") {
            style.lineEnding = "crlf"
        } else {
            style.lineEnding = "lf"
        }
        
        longTerm.codingStyle = style
        saveLongTermMemory()
    }
    
    // MARK: - Memory Injection
    
    /// Generate memory context for system prompt
    func generateMemoryContext() -> String {
        var context = ""
        
        // Add session context
        if !session.recentFiles.isEmpty {
            context += "\n## Recent Files\n"
            context += session.recentFiles.prefix(5).map { "- \($0)" }.joined(separator: "\n")
        }
        
        if let task = session.currentTask {
            context += "\n## Current Task\n\(task)\n"
        }
        
        // Add most used tools
        let topTools = getMostUsedTools(limit: 3)
        if !topTools.isEmpty {
            context += "\n## Frequently Used Tools\n"
            context += topTools.map { "- \($0.tool) (\($0.count) times)" }.joined(separator: "\n")
        }
        
        // Add coding style if set
        let style = longTerm.codingStyle
        if style.indentStyle != "spaces" || style.indentSize != 4 {
            context += "\n## Coding Style\n"
            context += "- Indentation: \(style.indentStyle == "tabs" ? "tabs" : "\(style.indentSize) spaces")\n"
        }
        
        // Add relevant error patterns
        if !longTerm.errorPatterns.isEmpty {
            let recentPatterns = longTerm.errorPatterns.suffix(3)
            if !recentPatterns.isEmpty {
                context += "\n## Recent Error Solutions\n"
                for pattern in recentPatterns {
                    context += "- \(pattern.errorType): \(pattern.solution)\n"
                }
            }
        }
        
        // Add user corrections
        if !longTerm.userCorrections.isEmpty {
            let recentCorrections = longTerm.userCorrections.suffix(2)
            if !recentCorrections.isEmpty {
                context += "\n## User Preferences\n"
                for correction in recentCorrections {
                    context += "- When \(correction.originalAction), prefer: \(correction.correctedAction)\n"
                }
            }
        }
        
        // Add preferred tools based on task types
        if !longTerm.preferredTools.isEmpty {
            context += "\n## Preferred Tools by Task Type\n"
            for (taskType, tool) in longTerm.preferredTools.sorted(by: { $0.key < $1.key }) {
                context += "- \(taskType): \(tool)\n"
            }
        }

        let notes = persistedNotes.prefix(3)
        if !notes.isEmpty {
            context += "\n## Verified Memory Notes\n"
            for note in notes {
                context += "- \(note.summary)\n"
            }
        }
        
        return context
    }
    
    /// Generate project-specific context
    func generateProjectContext(for projectPath: String) -> String {
        guard let knowledge = getProjectKnowledge(path: projectPath) else {
            return ""
        }
        
        var context = "\n## Project Knowledge\n"
        
        if let framework = knowledge.framework {
            context += "- Framework: \(framework)\n"
        }
        if let buildSystem = knowledge.buildSystem {
            context += "- Build system: \(buildSystem)\n"
        }
        if let testFramework = knowledge.testFramework {
            context += "- Test framework: \(testFramework)\n"
        }
        if !knowledge.commonCommands.isEmpty {
            context += "- Common commands: \(knowledge.commonCommands.joined(separator: ", "))\n"
        }
        
        return context
    }
    
    // MARK: - Persistence
    
    private func loadLongTermMemory() {
        guard let data = userDefaults.data(forKey: memoryKey) else {
            return
        }
        
        do {
            longTerm = try JSONDecoder().decode(LongTermMemory.self, from: data)
        } catch {
            RioLogger.config.error("⚠️ 加载长期记忆失败: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func saveLongTermMemory() {
        do {
            let data = try JSONEncoder().encode(longTerm)
            userDefaults.set(data, forKey: memoryKey)
        } catch {
            RioLogger.config.error("⚠️ 保存长期记忆失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadMemoryMarkdown() {
        let fm = FileManager.default
        let path = memoryMarkdownPath()
        guard !fm.fileExists(atPath: path) else { return }

        let initial = """
        # Agent Memory

        只记录经过验证的正确做法、用户纠错和重要原因。不要记录代码库里已经存在的内容，不要记录纯会话噪音。
        """

        do {
            try ensureMemoryDirectoryExists()
            try initial.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            RioLogger.config.error("⚠️ 初始化 MEMORY.md 失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func memoryMarkdownPath() -> String {
        if let customMarkdownURL {
            return customMarkdownURL.path
        }

        let baseURL: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = appSupport.appendingPathComponent("RioAgent", isDirectory: true)
        } else {
            baseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".rio-agent", isDirectory: true)
        }
        return baseURL.appendingPathComponent(markdownFileName).path
    }

    private func ensureMemoryDirectoryExists() throws {
        let path = memoryMarkdownPath()
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func loadMemoryMarkdownContent() -> String {
        (try? String(contentsOfFile: memoryMarkdownPath(), encoding: .utf8)) ?? ""
    }

    func loadMemoryNotes() -> [MemoryNote] {
        persistedNotes
    }

    func refreshPersistedNotes() {
        persistedNotes = readPersistedNotesFromDisk()
    }

    private func readPersistedNotesFromDisk() -> [MemoryNote] {
        let content = loadMemoryMarkdownContent()
        let chunks = content
            .components(separatedBy: "\n\n## ")
            .enumerated()
            .compactMap { index, raw -> MemoryNote? in
                let chunk = index == 0 ? raw : "## " + raw
                guard chunk.contains("## ") else { return nil }
                let lines = chunk.components(separatedBy: .newlines)
                let bodyLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard let summary = bodyLines.first else { return nil }
                return MemoryNote(
                    id: "\(index)-\(summary)",
                    summary: summary,
                    body: Array(bodyLines.dropFirst())
                )
            }
        return chunks.reversed()
    }

    func deleteMemoryNote(id: String) throws {
        let remaining = persistedNotes.filter { $0.id != id }
        try saveMemoryNotes(remaining)
    }

    func deleteMemoryNote(summary: String) throws {
        guard let note = persistedNotes.first(where: { $0.summary == summary }) else { return }
        try deleteMemoryNote(id: note.id)
    }

    func clearMemoryMarkdown() throws {
        try saveMemoryNotes([])
    }

    private func upsertMemoryNote(summary: String, body: [String]) {
        guard shouldPersistMemory(summary: summary, body: body) else { return }

        let existing = persistedNotes
        var deduped = existing.filter { $0.summary != summary }
        deduped.insert(MemoryNote(summary: summary, body: body), at: 0)
        let limited = Array(deduped.prefix(40))
        do {
            try saveMemoryNotes(limited)
        } catch {
            RioLogger.config.error("⚠️ 保存 MEMORY.md 失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldPersistMemory(summary: String, body: [String]) -> Bool {
        guard summary.hasPrefix("【摘要】") else { return false }
        guard !body.isEmpty else { return false }
        let joined = body.joined(separator: "\n")
        if joined.contains("solution: ") && !joined.contains("验证过") {
            return false
        }
        return true
    }

    private func saveMemoryNotes(_ notes: [MemoryNote]) throws {
        let header = """
        # Agent Memory

        只记录经过验证的正确做法、用户纠错和重要原因。不要记录代码库里已经存在的内容，不要记录纯会话噪音。
        """

        let sections = notes.map { note in
            """
            ## Note
            \(note.summary)
            \(note.body.joined(separator: "\n"))
            """
        }

        let content = ([header] + sections).joined(separator: "\n\n")

        try ensureMemoryDirectoryExists()
        try content.write(toFile: memoryMarkdownPath(), atomically: true, encoding: .utf8)
        persistedNotes = notes
    }
    
    // MARK: - Memory Management
    
    /// Clear session memory
    func clearSession() {
        session = SessionMemory()
    }
    
    /// Clear all memory
    func clearAllMemory() {
        session = SessionMemory()
        longTerm = LongTermMemory()
        saveLongTermMemory()
        do {
            try saveMemoryNotes([])
        } catch {
            RioLogger.config.error("⚠️ 清空 MEMORY.md 失败: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Get memory statistics
    func getStatistics() -> [String: Any] {
        return [
            "session_files": session.recentFiles.count,
            "session_commands": session.recentCommands.count,
            "session_tools": session.workingPatterns.count,
            "long_term_preferences": longTerm.preferredTools.count,
            "error_patterns": longTerm.errorPatterns.count,
            "user_corrections": longTerm.userCorrections.count,
            "projects_known": longTerm.projectKnowledge.count
        ]
    }
}
