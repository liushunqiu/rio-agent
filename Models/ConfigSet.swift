import Foundation

// MARK: - Config Set (每个配置集 = 一个模型)

struct ConfigSet: Identifiable, Codable {
    let id: UUID
    var name: String
    var provider: AIProvider
    var baseURL: String
    var model: String
    
    init(
        id: UUID = UUID(),
        name: String,
        provider: AIProvider = .openAICompatible,
        baseURL: String = "",
        model: String = ""
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
    }
    
    var isConfigured: Bool {
        !loadAPIKey().isEmpty
    }
    
    // MARK: - API Key (Keychain)
    
    func loadAPIKey() -> String {
        KeychainManager.load(forKey: apiKeyKeychainKey) ?? ""
    }
    
    func saveAPIKey(_ key: String) {
        if key.isEmpty {
            try? KeychainManager.delete(forKey: apiKeyKeychainKey)
        } else {
            try? KeychainManager.save(key, forKey: apiKeyKeychainKey)
        }
    }
    
    private var apiKeyKeychainKey: String {
        "config_set_\(id.uuidString)_api_key"
    }
}

// MARK: - Config Set Manager

class ConfigSetManager: ObservableObject {
    static let shared = ConfigSetManager()
    
    @Published var configSets: [ConfigSet] = []
    
    init() {
        loadFromUserDefaults()
    }
    
    // MARK: - CRUD
    
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
        saveToUserDefaults()
    }
    
    func configSet(for id: UUID?) -> ConfigSet? {
        guard let id else { return nil }
        return configSets.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private let userDefaultsKey = "config_sets_v2"
    
    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(configSets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let sets = try? JSONDecoder().decode([ConfigSet].self, from: data) {
            configSets = sets
        }
    }
}
