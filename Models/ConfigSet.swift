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
        readinessIssue == nil
    }

    var readinessIssue: String? {
        let hasModel = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasModel else { return "缺少模型标识" }

        switch provider {
        case .openAICompatible:
            return baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "缺少 API 端点" : nil
        case .claude, .openAI:
            return loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "缺少 API Key" : nil
        }
    }
    
    // MARK: - API Key (Keychain)
    
    func loadAPIKey() -> String {
        KeychainManager.load(forKey: apiKeyKeychainKey) ?? ""
    }
    
    func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedKey.isEmpty {
            try KeychainManager.delete(forKey: apiKeyKeychainKey)
        } else {
            try KeychainManager.save(trimmedKey, forKey: apiKeyKeychainKey)
        }
    }
    
    private var apiKeyKeychainKey: String {
        "config_set_\(id.uuidString)_api_key"
    }
}

enum ConfigSetPersistenceError: LocalizedError {
    case encodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .encodeFailed(let error):
            return "模型配置无法编码：\(error.localizedDescription)"
        }
    }
}

// MARK: - Config Set Manager

class ConfigSetManager: ObservableObject {
    static let shared = ConfigSetManager()
    static let storageKey = "config_sets_v2"

    private let userDefaults: UserDefaults
    private let saveKey: String
    
    @Published var configSets: [ConfigSet] = [] {
        didSet {
            revision &+= 1
        }
    }
    @Published private(set) var revision: Int = 0
    
    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = ConfigSetManager.storageKey
    ) {
        self.userDefaults = userDefaults
        self.saveKey = storageKey
        loadFromUserDefaults()
    }
    
    // MARK: - CRUD
    
    func addConfigSet(_ configSet: ConfigSet) throws {
        let previousConfigSets = configSets
        configSets.append(configSet)
        do {
            try saveToUserDefaults()
        } catch {
            configSets = previousConfigSets
            throw error
        }
    }
    
    func updateConfigSet(_ configSet: ConfigSet) throws {
        if let index = configSets.firstIndex(where: { $0.id == configSet.id }) {
            let previousConfigSets = configSets
            configSets[index] = configSet
            do {
                try saveToUserDefaults()
            } catch {
                configSets = previousConfigSets
                throw error
            }
        }
    }
    
    func deleteConfigSet(id: UUID) throws {
        if let configSet = configSets.first(where: { $0.id == id }) {
            try configSet.saveAPIKey("")
        }
        let previousConfigSets = configSets
        configSets.removeAll { $0.id == id }
        do {
            try saveToUserDefaults()
        } catch {
            configSets = previousConfigSets
            throw error
        }
    }
    
    func configSet(for id: UUID?) -> ConfigSet? {
        guard let id else { return nil }
        return configSets.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private func saveToUserDefaults() throws {
        do {
            let data = try JSONEncoder().encode(configSets)
            userDefaults.set(data, forKey: saveKey)
        } catch {
            throw ConfigSetPersistenceError.encodeFailed(error)
        }
    }
    
    private func loadFromUserDefaults() {
        if let data = userDefaults.data(forKey: saveKey),
           let sets = try? JSONDecoder().decode([ConfigSet].self, from: data) {
            configSets = sets
        }
    }
}
