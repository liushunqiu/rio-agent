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

// MARK: - Provider Configuration

struct ProviderConfig: Codable, Hashable {
    // apiKey is NOT encoded - stored in Keychain instead
    var apiKey: String
    var baseURL: String
    var planningModel: String
    var executionModel: String
    var isStreaming: Bool
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case baseURL, model, planningModel, executionModel, isStreaming, maxTokens
        // apiKey is excluded from encoding/decoding
    }

    init(
        apiKey: String = "",
        baseURL: String = "",
        model: String = "",
        isStreaming: Bool = true,
        maxTokens: Int = 0
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.executionModel = model
        self.planningModel = model
        self.isStreaming = isStreaming
        self.maxTokens = maxTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = "" // API keys are loaded from Keychain separately
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        executionModel = try container.decodeIfPresent(String.self, forKey: .executionModel) ?? legacyModel
        planningModel = executionModel // Always unified
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? true
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(planningModel, forKey: .planningModel)
        try container.encode(executionModel, forKey: .executionModel)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(maxTokens, forKey: .maxTokens)
        // apiKey is NOT encoded
    }

    var effectiveMaxTokens: Int {
        if maxTokens > 0 { return maxTokens }
        return AIProvider.defaultMaxTokens(for: executionModel)
    }

    var model: String {
        get { executionModel }
        set {
            executionModel = newValue
            planningModel = newValue
        }
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    var effectiveBaseURL: String {
        baseURL.isEmpty ? defaultBaseURL : baseURL
    }

    var defaultBaseURL: String {
        // Subclasses will override via provider
        ""
    }
}

struct AIConfiguration: Codable {
    var planningConfigSetId: UUID?
    var executionConfigSetId: UUID?

    // Context management
    var maxContextMessages: Int
    var enableStreaming: Bool

    enum CodingKeys: String, CodingKey {
        case planningConfigSetId, executionConfigSetId
        case maxContextMessages, enableStreaming
        // Legacy keys for backward compat
        case activeProvider, planningProvider, executionProvider
    }

    init(
        planningConfigSetId: UUID? = nil,
        executionConfigSetId: UUID? = nil,
        maxContextMessages: Int = 999,
        enableStreaming: Bool = true
    ) {
        self.planningConfigSetId = planningConfigSetId
        self.executionConfigSetId = executionConfigSetId
        self.maxContextMessages = maxContextMessages
        self.enableStreaming = enableStreaming
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planningConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .planningConfigSetId)
        executionConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .executionConfigSetId)
        maxContextMessages = try container.decode(Int.self, forKey: .maxContextMessages)
        enableStreaming = try container.decode(Bool.self, forKey: .enableStreaming)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(planningConfigSetId, forKey: .planningConfigSetId)
        try container.encodeIfPresent(executionConfigSetId, forKey: .executionConfigSetId)
        try container.encode(maxContextMessages, forKey: .maxContextMessages)
        try container.encode(enableStreaming, forKey: .enableStreaming)
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
