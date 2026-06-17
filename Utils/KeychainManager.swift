import Foundation
import Security

/// macOS Keychain wrapper for secure storage of API keys and sensitive data
enum KeychainManager {
    private enum StorageMode: String {
        case keychain
        case userDefaults
    }
    
    // MARK: - Error Types
    
    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case dataConversionError
        
        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Keychain item already exists"
            case .itemNotFound:
                return "Keychain item not found"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .dataConversionError:
                return "Failed to convert data"
            }
        }
    }
    
    // MARK: - Service Identifier

    private static let service = "com.rio-agent.api-keys"
    private static let accessGroup = "com.rioagent.app"
    private static let cacheLock = NSLock()
    private static var cachedValues: [String: String] = [:]
    private static var didLogUserDefaultsFallback = false

    private static var storageMode: StorageMode {
        if ProcessInfo.processInfo.environment["RIO_AGENT_DISABLE_KEYCHAIN"] == "1" {
            return .userDefaults
        }

        if let flag = Bundle.main.object(forInfoDictionaryKey: "RIOUnsignedBuild") as? Bool, flag {
            return .userDefaults
        }

        return .keychain
    }

    private static func cacheKey(for key: String, mode: StorageMode) -> String {
        "\(mode.rawValue)::\(key)"
    }

    private static func userDefaultsStorageKey(for key: String) -> String {
        "rio_agent_userdefaults_secret_\(key)"
    }

    private static func logUserDefaultsFallbackIfNeeded() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard !didLogUserDefaultsFallback else { return }
        didLogUserDefaultsFallback = true
        RioLogger.config.warning("Keychain unavailable for current build; falling back to UserDefaults storage")
    }

    private static func cachedValue(forKey key: String, mode: StorageMode) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedValues[cacheKey(for: key, mode: mode)]
    }

    private static func cache(_ value: String, forKey key: String, mode: StorageMode) {
        cacheLock.lock()
        cachedValues[cacheKey(for: key, mode: mode)] = value
        cacheLock.unlock()
    }

    private static func removeCachedValue(forKey key: String) {
        cacheLock.lock()
        cachedValues.removeValue(forKey: cacheKey(for: key, mode: .keychain))
        cachedValues.removeValue(forKey: cacheKey(for: key, mode: .userDefaults))
        cacheLock.unlock()
    }
    
    // MARK: - Public Methods
    
    /// Save a string value to Keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    ///   - accessibility: Keychain accessibility level (default: whenUnlocked)
    static func save(_ value: String, forKey key: String, 
                     accessibility: CFString = kSecAttrAccessibleWhenUnlocked) throws {
        let mode = storageMode

        if mode == .userDefaults {
            logUserDefaultsFallbackIfNeeded()
            UserDefaults.standard.set(value, forKey: userDefaultsStorageKey(for: key))
            cache(value, forKey: key, mode: mode)
            return
        }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        // Delete any existing item first
        try? delete(forKey: key)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        cache(value, forKey: key, mode: mode)
        
        RioLogger.config.info("🔐 Keychain: Saved \(key, privacy: .public)")
    }
    
    /// Load a string value from Keychain
    /// - Parameter key: The key to look up
    /// - Returns: The stored string value, or nil if not found
    static func load(forKey key: String) -> String? {
        let mode = storageMode

        if let cached = cachedValue(forKey: key, mode: mode) {
            return cached
        }

        if mode == .userDefaults {
            logUserDefaultsFallbackIfNeeded()
            guard let value = UserDefaults.standard.string(forKey: userDefaultsStorageKey(for: key)) else {
                return nil
            }
            cache(value, forKey: key, mode: mode)
            return value
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, 
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        cache(string, forKey: key, mode: mode)
        
        return string
    }
    
    /// Delete a value from Keychain
    /// - Parameter key: The key to delete
    static func delete(forKey key: String) throws {
        let mode = storageMode

        if mode == .userDefaults {
            UserDefaults.standard.removeObject(forKey: userDefaultsStorageKey(for: key))
            removeCachedValue(forKey: key)
            return
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }

        removeCachedValue(forKey: key)
    }
    
    /// Check if a key exists in Keychain
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists
    static func exists(forKey key: String) -> Bool {
        return load(forKey: key) != nil
    }
    
    // MARK: - Convenience Methods for API Keys
    
    /// Save an API key for a specific provider
    static func saveAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        let key = "api_key_\(provider.rawValue)"
        try save(apiKey, forKey: key)
    }
    
    /// Load an API key for a specific provider
    static func loadAPIKey(for provider: AIProvider) -> String? {
        let key = "api_key_\(provider.rawValue)"
        return load(forKey: key)
    }
    
    /// Delete an API key for a specific provider
    static func deleteAPIKey(for provider: AIProvider) throws {
        let key = "api_key_\(provider.rawValue)"
        try delete(forKey: key)
    }
    
    // MARK: - String Key Methods (for Config Sets)
    
    /// Save an API key with a custom string key
    static func saveAPIKey(_ apiKey: String, for key: String) throws {
        try save(apiKey, forKey: key)
    }
    
    /// Load an API key with a custom string key
    static func loadAPIKey(for key: String) -> String? {
        return load(forKey: key)
    }
    
    /// Delete an API key with a custom string key
    static func deleteAPIKey(for key: String) throws {
        try delete(forKey: key)
    }
    
    /// Migrate API keys from UserDefaults to Keychain
    /// Returns the number of keys migrated
    @discardableResult
    static func migrateFromUserDefaults() -> Int {
        var migratedCount = 0
        
        let providers: [(AIProvider, String)] = [
            (.claude, "claude_api_key"),
            (.openAI, "openai_api_key"),
            (.openAICompatible, "compatible_api_key")
        ]
        
        for (provider, userDefaultsKey) in providers {
            if let apiKey = UserDefaults.standard.string(forKey: userDefaultsKey), !apiKey.isEmpty {
                do {
                    try saveAPIKey(apiKey, for: provider)
                    // Optionally remove from UserDefaults after successful migration
                    // UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                    migratedCount += 1
                    RioLogger.config.info("🔄 Migrated API key for \(provider.displayName, privacy: .public) to Keychain")
                } catch {
                    RioLogger.config.error("⚠️ Failed to migrate API key for \(provider.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        return migratedCount
    }
}
