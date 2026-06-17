import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [Message]
    var workingDirectory: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        messages: [Message] = [],
        workingDirectory: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.updatedAt == rhs.updatedAt && lhs.messages.count == rhs.messages.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()

        // Auto-generate title from first user message
        if title == "新对话", message.role == .user {
            title = String(message.content.prefix(50))
            if message.content.count > 50 {
                title += "..."
            }
        }
    }
}

// MARK: - AI Provider Configuration

enum AIProvider: String, Codable, CaseIterable {
    case claude
    case openAI
    case openAICompatible

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "自定义端点"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        case .openAICompatible: return "gpt-4o"
        }
    }

    var defaultPlanningModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        case .openAICompatible: return "gpt-4o"
        }
    }

    var defaultExecutionModel: String {
        switch self {
        case .claude: return "claude-3-5-haiku-20241022"
        case .openAI: return "gpt-4o-mini"
        case .openAICompatible: return "gpt-4o-mini"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .openAI: return "sparkles"
        case .openAICompatible: return "server.rack"
        }
    }

    /// 获取模型对应的推荐 max_tokens 值
    static func defaultMaxTokens(for model: String) -> Int {
        ModelCapabilities.capabilities(for: model).maxOutputTokens
    }

    /// 获取模型的上下文窗口大小（token 数），用于自动压缩
    static func contextWindow(for model: String) -> Int {
        ModelCapabilities.capabilities(for: model).contextWindow
    }
}

struct AIConfiguration: Codable {
    var planningConfigSetId: UUID?
    var executionConfigSetId: UUID?

    // Context management
    var maxContextMessages: Int
    var enableStreaming: Bool
    var singleAgentSystemPrompt: String

    enum CodingKeys: String, CodingKey {
        case planningConfigSetId, executionConfigSetId
        case maxContextMessages, enableStreaming, singleAgentSystemPrompt
        // Legacy keys for backward compat
        case activeProvider, planningProvider, executionProvider
    }

    static let defaultSingleAgentSystemPrompt = """
    You are Rio Agent, an AI assistant with tool-calling capabilities for software engineering tasks. Always respond in the same language the user uses.

    Priorities:
    - Give the direct answer first. The first sentence should state what you found, changed, or concluded.
    - Keep reasoning private. Do not dump raw chain-of-thought. If useful, provide a short reasoning summary after the answer.
    - Before claiming progress or completion, verify the claim against tool results from this conversation. If something is not verified, say so explicitly.
    - Distinguish observed facts from inference. Do not invent file contents, command output, test results, or completion status.
    - Prefer natural prose and minimal formatting. Use lists only when they improve clarity.

    Available tools:
    - read_file: Read file content. Read-only, no confirmation needed. Prefer this over execute_command for reading files.
    - write_file: Write file content (complete overwrite, not append). Auto-executes within working directory; writes outside working directory require confirmation.
    - edit_file: Edit a file by search/replace. Safer than write_file for targeted changes. old_text must appear exactly once.
    - apply_patch: Apply a multi-file patch using diff format. Use for coordinated changes across files.
    - search_files: Search file contents by regex.
    - find_files: Find files by name pattern.
    - list_directory: List directory contents with metadata.
    - execute_command: Execute shell commands. Safe commands auto-execute; dangerous commands require confirmation.

    Tool strategy:
    - Explore first: use list_directory, find_files, and search_files before making changes.
    - Read before editing: inspect the current file content before modifying it.
    - Edit precisely: prefer edit_file or apply_patch for existing files.
    - Verify after acting: after a code or file change, read back the affected file or run an appropriate verification command.
    - Stop repeating failed attempts: if the same approach fails 2-3 times, explain the blocker and adjust.

    Safety rules:
    - Each file tool requires an absolute path. When the user gives a relative path, resolve it from the working directory.
    - Do not call tools when you already have enough evidence to answer.
    - For shell, package management, or git work, use execute_command.
    - If a command or edit has not been verified, do not present it as done.
    """

    init(
        planningConfigSetId: UUID? = nil,
        executionConfigSetId: UUID? = nil,
        maxContextMessages: Int = 999,
        enableStreaming: Bool = true,
        singleAgentSystemPrompt: String = AIConfiguration.defaultSingleAgentSystemPrompt
    ) {
        self.planningConfigSetId = planningConfigSetId
        self.executionConfigSetId = executionConfigSetId
        self.maxContextMessages = maxContextMessages
        self.enableStreaming = enableStreaming
        self.singleAgentSystemPrompt = singleAgentSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planningConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .planningConfigSetId)
        executionConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .executionConfigSetId)
        maxContextMessages = try container.decodeIfPresent(Int.self, forKey: .maxContextMessages) ?? 999
        enableStreaming = try container.decodeIfPresent(Bool.self, forKey: .enableStreaming) ?? true
        singleAgentSystemPrompt = try container.decodeIfPresent(String.self, forKey: .singleAgentSystemPrompt)
            ?? Self.defaultSingleAgentSystemPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(planningConfigSetId, forKey: .planningConfigSetId)
        try container.encodeIfPresent(executionConfigSetId, forKey: .executionConfigSetId)
        try container.encode(maxContextMessages, forKey: .maxContextMessages)
        try container.encode(enableStreaming, forKey: .enableStreaming)
        try container.encode(singleAgentSystemPrompt, forKey: .singleAgentSystemPrompt)
    }

    // MARK: - ConfigSet Lookup

    private func lookupConfigSet(_ id: UUID?) -> ConfigSet? {
        ConfigSetManager.shared.configSet(for: id)
    }

    var planningConfigSet: ConfigSet? { lookupConfigSet(planningConfigSetId) }
    var executionConfigSet: ConfigSet? { lookupConfigSet(executionConfigSetId) }

    // MARK: - Provider & Model Access

    var planningProvider: AIProvider {
        planningConfigSet?.provider ?? .openAICompatible
    }

    var executionProvider: AIProvider {
        executionConfigSet?.provider ?? .openAICompatible
    }

    var planningModel: String {
        planningConfigSet?.model ?? ""
    }

    var executionModel: String {
        executionConfigSet?.model ?? ""
    }

    var model: String { executionModel }

    var planningBaseURL: String {
        planningConfigSet?.baseURL ?? ""
    }

    var executionBaseURL: String {
        executionConfigSet?.baseURL ?? ""
    }

    var baseURL: String { executionBaseURL }

    var planningAPIKey: String? {
        planningConfigSet?.loadAPIKey()
    }

    var executionAPIKey: String? {
        executionConfigSet?.loadAPIKey()
    }

    var isStreaming: Bool { enableStreaming }

    var maxTokens: Int {
        ModelCapabilities.capabilities(for: executionModel).maxOutputTokens
    }

    var capabilities: ModelCapabilities {
        ModelCapabilities.capabilities(for: model)
    }

    // MARK: - Legacy Compat

    var activeProvider: AIProvider { executionProvider }

    var provider: AIProvider {
        get { executionProvider }
        set { /* no-op for compat */ }
    }

    var isConfigured: Bool {
        !(executionAPIKey?.isEmpty ?? true)
    }

    func isConfigured(for provider: AIProvider) -> Bool {
        if provider == .openAICompatible {
            return !executionBaseURL.isEmpty
        }
        return !(executionAPIKey?.isEmpty ?? true)
    }

    // MARK: - API Key helpers

    func apiKey(for provider: AIProvider, configSetId: UUID?) -> String? {
        lookupConfigSet(configSetId)?.loadAPIKey()
    }

    func baseURL(for provider: AIProvider) -> String {
        executionBaseURL
    }
}
