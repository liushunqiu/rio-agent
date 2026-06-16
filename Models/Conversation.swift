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
    var activeProvider: AIProvider
    var planningProvider: AIProvider
    var executionProvider: AIProvider
    var planningConfigSetId: UUID?
    var executionConfigSetId: UUID?

    // Context management
    var maxContextMessages: Int
    var enableStreaming: Bool

    // Use Keychain for API keys (not encoded to JSON)
    private var _apiKeyStorage: [AIProvider: String] = [:]

    enum CodingKeys: String, CodingKey {
        case activeProvider, planningProvider, executionProvider, planningConfigSetId, executionConfigSetId
        case maxContextMessages, enableStreaming
    }

    init(
        activeProvider: AIProvider = .claude,
        planningProvider: AIProvider? = nil,
        executionProvider: AIProvider? = nil,
        planningConfigSetId: UUID? = nil,
        executionConfigSetId: UUID? = nil,
        maxContextMessages: Int = 999,
        enableStreaming: Bool = true
    ) {
        self.activeProvider = activeProvider
        self.planningProvider = planningProvider ?? activeProvider
        self.executionProvider = executionProvider ?? activeProvider
        self.planningConfigSetId = planningConfigSetId
        self.executionConfigSetId = executionConfigSetId
        self.maxContextMessages = maxContextMessages
        self.enableStreaming = enableStreaming
        
        // Load API keys from Keychain on init
        loadAPIKeysFromKeychain()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProvider = try container.decode(AIProvider.self, forKey: .activeProvider)
        planningProvider = try container.decodeIfPresent(AIProvider.self, forKey: .planningProvider) ?? activeProvider
        executionProvider = try container.decodeIfPresent(AIProvider.self, forKey: .executionProvider) ?? activeProvider
        planningConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .planningConfigSetId)
        executionConfigSetId = try container.decodeIfPresent(UUID.self, forKey: .executionConfigSetId)
        maxContextMessages = try container.decode(Int.self, forKey: .maxContextMessages)
        enableStreaming = try container.decode(Bool.self, forKey: .enableStreaming)
        
        // Load API keys from Keychain
        loadAPIKeysFromKeychain()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeProvider, forKey: .activeProvider)
        try container.encode(planningProvider, forKey: .planningProvider)
        try container.encode(executionProvider, forKey: .executionProvider)
        try container.encodeIfPresent(planningConfigSetId, forKey: .planningConfigSetId)
        try container.encodeIfPresent(executionConfigSetId, forKey: .executionConfigSetId)
        try container.encode(maxContextMessages, forKey: .maxContextMessages)
        try container.encode(enableStreaming, forKey: .enableStreaming)
        // API keys are NOT encoded - they stay in Keychain
    }

    // MARK: - Keychain Integration

    /// Load API keys from Keychain into memory
    private mutating func loadAPIKeysFromKeychain() {
        for provider in AIProvider.allCases {
            if let key = KeychainManager.loadAPIKey(for: provider) {
                _apiKeyStorage[provider] = key
            }
        }
    }

    /// Save all API keys to Keychain
    func saveAPIKeysToKeychain() {
        for (provider, key) in _apiKeyStorage {
            if !key.isEmpty {
                try? KeychainManager.saveAPIKey(key, for: provider)
            }
        }
    }

    /// Save a specific API key to Keychain
    mutating func setAPIKey(_ key: String?, for provider: AIProvider) {
        _apiKeyStorage[provider] = key
        if let key = key, !key.isEmpty {
            try? KeychainManager.saveAPIKey(key, for: provider)
        } else {
            try? KeychainManager.deleteAPIKey(for: provider)
        }
    }

    /// Get API key for a specific provider
    func getAPIKey(for provider: AIProvider) -> String? {
        // First check in-memory storage
        if let key = _apiKeyStorage[provider], !key.isEmpty {
            return key
        }
        // Then check Keychain
        return KeychainManager.loadAPIKey(for: provider)
    }

    // MARK: - Convenience Accessors

    func config(for provider: AIProvider, configSetId: UUID?) -> ProviderConfig {
        guard let configSetId = configSetId else {
            return ProviderConfig()
        }
        
        let userDefaultsKey = "config_sets"
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let configSets = try? JSONDecoder().decode([ConfigSet].self, from: data),
              let configSet = configSets.first(where: { $0.id == configSetId }) else {
            return ProviderConfig()
        }
        return configSet.config(for: provider)
    }

    var currentConfig: ProviderConfig {
        config(for: executionProvider, configSetId: executionConfigSetId)
    }

    var planningConfig: ProviderConfig {
        config(for: planningProvider, configSetId: planningConfigSetId)
    }

    var executionConfig: ProviderConfig {
        config(for: executionProvider, configSetId: executionConfigSetId)
    }

    var apiKey: String? {
        guard let configSetId = executionConfigSetId else { return nil }
        let keychainKey = "config_set_\(configSetId.uuidString)_\(executionProvider.rawValue)_api_key"
        return KeychainManager.load(forKey: keychainKey)
    }

    func apiKey(for provider: AIProvider, configSetId: UUID?) -> String? {
        guard let configSetId = configSetId else { return nil }
        let keychainKey = "config_set_\(configSetId.uuidString)_\(provider.rawValue)_api_key"
        return KeychainManager.load(forKey: keychainKey)
    }

    var model: String {
        currentConfig.model
    }

    var planningModel: String {
        planningConfig.model
    }

    var executionModel: String {
        currentConfig.model
    }

    var maxTokens: Int {
        currentConfig.effectiveMaxTokens
    }

    var baseURL: String {
        baseURL(for: executionProvider)
    }

    func baseURL(for provider: AIProvider) -> String {
        let url = config(for: provider, configSetId: executionConfigSetId).baseURL
        if url.isEmpty {
            switch provider {
            case .claude: return "https://api.anthropic.com"
            case .openAI: return "https://api.openai.com"
            case .openAICompatible: return ""
            }
        }
        return url
    }

    var isStreaming: Bool {
        enableStreaming && executionConfig.isStreaming
    }

    // MARK: - Model Capabilities

    var capabilities: ModelCapabilities {
        return ModelCapabilities.capabilities(for: model)
    }

    // MARK: - Legacy Compatibility

    var provider: AIProvider {
        get { executionProvider }
        set {
            executionProvider = newValue
            activeProvider = newValue
        }
    }

    var claudeApiKey: String? {
        get { getAPIKey(for: .claude) }
        set { setAPIKey(newValue, for: .claude) }
    }

    var openAIApiKey: String? {
        get { getAPIKey(for: .openAI) }
        set { setAPIKey(newValue, for: .openAI) }
    }

    var compatibleApiKey: String? {
        get { getAPIKey(for: .openAICompatible) }
        set { setAPIKey(newValue, for: .openAICompatible) }
    }

    // MARK: - Validation

    var isConfigured: Bool {
        isConfigured(for: executionProvider)
    }

    func isConfigured(for provider: AIProvider) -> Bool {
        if provider == .openAICompatible {
            return !baseURL(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let key = getAPIKey(for: provider) else { return false }
        return !key.isEmpty
    }
}
