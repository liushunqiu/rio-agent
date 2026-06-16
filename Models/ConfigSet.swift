import Foundation

// MARK: - Config Set

struct ConfigSet: Identifiable, Codable {
    let id: UUID
    var name: String
    var claudeConfig: ProviderConfig
    var openAIConfig: ProviderConfig
    var customConfig: ProviderConfig
    
    init(
        id: UUID = UUID(),
        name: String,
        claudeConfig: ProviderConfig = ProviderConfig(
            baseURL: "https://api.anthropic.com",
            model: AIProvider.claude.defaultModel
        ),
        openAIConfig: ProviderConfig = ProviderConfig(
            baseURL: "https://api.openai.com",
            model: AIProvider.openAI.defaultModel
        ),
        customConfig: ProviderConfig = ProviderConfig(
            baseURL: "",
            model: AIProvider.openAICompatible.defaultModel
        )
    ) {
        self.id = id
        self.name = name
        self.claudeConfig = claudeConfig
        self.openAIConfig = openAIConfig
        self.customConfig = customConfig
    }
    
    func config(for provider: AIProvider) -> ProviderConfig {
        switch provider {
        case .claude: return claudeConfig
        case .openAI: return openAIConfig
        case .openAICompatible: return customConfig
        }
    }
    
    mutating func setConfig(_ config: ProviderConfig, for provider: AIProvider) {
        switch provider {
        case .claude: claudeConfig = config
        case .openAI: openAIConfig = config
        case .openAICompatible: customConfig = config
        }
    }
}

// MARK: - Config Set Manager

class ConfigSetManager: ObservableObject {
    static let shared = ConfigSetManager()
    
    @Published var configSets: [ConfigSet] = []
    @Published var selectedPlanningConfigSetId: UUID?
    @Published var selectedExecutionConfigSetId: UUID?
    
    var selectedPlanningConfigSet: ConfigSet? {
        configSets.first { $0.id == selectedPlanningConfigSetId }
    }
    
    var selectedExecutionConfigSet: ConfigSet? {
        configSets.first { $0.id == selectedExecutionConfigSetId }
    }
    
    init() {
        loadFromUserDefaults()
    }
    
    // MARK: - CRUD Operations
    
    func addConfigSet(_ configSet: ConfigSet) {
        configSets.append(configSet)
        saveToUserDefaults()
    }
    
    func updateConfigSet(_ configSet: ConfigSet) {
        if let index = configSets.firstIndex(where: { $0.id == configSet.id }) {
            configSets[index] = configSet
            saveToUserDefaults()
        }
    }
    
    func deleteConfigSet(id: UUID) {
        configSets.removeAll { $0.id == id }
        if selectedPlanningConfigSetId == id {
            selectedPlanningConfigSetId = configSets.first?.id
        }
        if selectedExecutionConfigSetId == id {
            selectedExecutionConfigSetId = configSets.first?.id
        }
        saveToUserDefaults()
    }
    
    func selectPlanningConfigSet(id: UUID?) {
        selectedPlanningConfigSetId = id
        saveToUserDefaults()
    }
    
    func selectExecutionConfigSet(id: UUID?) {
        selectedExecutionConfigSetId = id
        saveToUserDefaults()
    }
    
    // MARK: - Persistence
    
    private let userDefaultsKey = "config_sets"
    
    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(configSets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.set(selectedPlanningConfigSetId?.uuidString, forKey: "selected_planning_config_set_id")
            UserDefaults.standard.set(selectedExecutionConfigSetId?.uuidString, forKey: "selected_execution_config_set_id")
        }
    }
    
    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let sets = try? JSONDecoder().decode([ConfigSet].self, from: data) {
            configSets = sets
        }
        
        if let planningIdStr = UserDefaults.standard.string(forKey: "selected_planning_config_set_id"),
           let planningId = UUID(uuidString: planningIdStr) {
            selectedPlanningConfigSetId = planningId
        }
        
        if let executionIdStr = UserDefaults.standard.string(forKey: "selected_execution_config_set_id"),
           let executionId = UUID(uuidString: executionIdStr) {
            selectedExecutionConfigSetId = executionId
        }
        
        if configSets.isEmpty {
            createDefaultConfigSet()
        }
    }
    
    private func createDefaultConfigSet() {
        let defaultSet = ConfigSet(name: "默认配置")
        configSets.append(defaultSet)
        selectedPlanningConfigSetId = defaultSet.id
        selectedExecutionConfigSetId = defaultSet.id
        saveToUserDefaults()
    }
    
    func loadConfigSetAPIKey(configSetId: UUID, provider: AIProvider) -> String? {
        return KeychainManager.loadConfigSetAPIKey(configSetId: configSetId, provider: provider)
    }
}

// MARK: - Keychain Extension for Config Sets

extension KeychainManager {
    private static func configSetKey(_ configSetId: UUID, provider: AIProvider) -> String {
        "config_set_\(configSetId.uuidString)_\(provider.rawValue)_api_key"
    }
    
    static func saveConfigSetAPIKey(_ key: String, configSetId: UUID, provider: AIProvider) {
        let keychainKey = configSetKey(configSetId, provider: provider)
        try? saveAPIKey(key, for: keychainKey)
    }
    
    static func loadConfigSetAPIKey(configSetId: UUID, provider: AIProvider) -> String? {
        let keychainKey = configSetKey(configSetId, provider: provider)
        return loadAPIKey(for: keychainKey)
    }
    
    static func deleteConfigSetAPIKey(configSetId: UUID, provider: AIProvider) {
        let keychainKey = configSetKey(configSetId, provider: provider)
        try? deleteAPIKey(for: keychainKey)
    }
}
