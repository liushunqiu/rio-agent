import Foundation

/// Configuration for intelligent assistant features
struct IntelligentAssistantConfig: Codable, Equatable {
    
    // MARK: - Learning Settings
    
    /// Enable/disable learning from user behavior
    var enableLearning: Bool = true
    
    /// Enable/disable tool recommendations based on history
    var enableToolRecommendations: Bool = true
    
    /// Enable/disable task planning for complex tasks
    var enableTaskPlanning: Bool = true
    
    /// Enable/disable code quality analysis
    var enableCodeAnalysis: Bool = true
    
    /// Enable/disable context awareness
    var enableContextAwareness: Bool = true
    
    // MARK: - Analysis Settings
    
    /// Maximum number of learning events to store
    var maxLearningEvents: Int = 1000
    
    /// Minimum success rate for tool recommendations
    var minSuccessRateForRecommendation: Double = 0.7
    
    /// Minimum number of uses before recommending a tool
    var minUsesForRecommendation: Int = 3
    
    // MARK: - Task Planning Settings
    
    /// Enable automatic task decomposition
    var enableAutoDecomposition: Bool = true
    
    /// Maximum number of sub-tasks for decomposition
    var maxSubTasks: Int = 10
    
    /// Enable parallel task execution
    var enableParallelExecution: Bool = true
    
    // MARK: - Code Analysis Settings
    
    /// Enable real-time code analysis
    var enableRealTimeAnalysis: Bool = false
    
    /// Maximum line length for readability check
    var maxLineLength: Int = 120
    
    /// Maximum function length for maintainability check
    var maxFunctionLength: Int = 50
    
    /// Maximum nesting depth for complexity check
    var maxNestingDepth: Int = 5
    
    // MARK: - Context Awareness Settings
    
    /// Enable file type detection
    var enableFileTypeDetection: Bool = true
    
    /// Enable project type detection
    var enableProjectTypeDetection: Bool = true
    
    /// Enable framework detection
    var enableFrameworkDetection: Bool = true
    
    // MARK: - Memory Settings
    
    /// Enable long-term memory
    var enableLongTermMemory: Bool = true
    
    /// Maximum number of recent files to remember
    var maxRecentFiles: Int = 20
    
    /// Maximum number of recent commands to remember
    var maxRecentCommands: Int = 20
    
    /// Maximum number of error patterns to store
    var maxErrorPatterns: Int = 100
    
    // MARK: - UI Settings
    
    /// Show task plan to user
    var showTaskPlan: Bool = true
    
    /// Show code analysis results
    var showCodeAnalysis: Bool = true
    
    /// Show tool recommendations
    var showToolRecommendations: Bool = true
    
    /// Show learning progress
    var showLearningProgress: Bool = false
    
    // MARK: - Persistence
    
    private static let configKey = "intelligent_assistant_config"
    
    /// Save configuration to UserDefaults
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.configKey)
        } catch {
            print("Failed to save intelligent assistant config: \(error)")
        }
    }
    
    /// Load configuration from UserDefaults
    static func load() -> IntelligentAssistantConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey) else {
            return IntelligentAssistantConfig()
        }
        
        do {
            return try JSONDecoder().decode(IntelligentAssistantConfig.self, from: data)
        } catch {
            print("Failed to load intelligent assistant config: \(error)")
            return IntelligentAssistantConfig()
        }
    }
    
    /// Reset to default configuration
    mutating func resetToDefaults() {
        self = IntelligentAssistantConfig()
    }
}

// MARK: - Configuration Presets

extension IntelligentAssistantConfig {
    
    /// Conservative preset - minimal learning and analysis
    static var conservative: IntelligentAssistantConfig {
        var config = IntelligentAssistantConfig()
        config.enableLearning = false
        config.enableToolRecommendations = false
        config.enableTaskPlanning = false
        config.enableCodeAnalysis = false
        config.enableRealTimeAnalysis = false
        config.showTaskPlan = false
        config.showCodeAnalysis = false
        config.showToolRecommendations = false
        return config
    }
    
    /// Balanced preset - moderate learning and analysis
    static var balanced: IntelligentAssistantConfig {
        var config = IntelligentAssistantConfig()
        config.enableLearning = true
        config.enableToolRecommendations = true
        config.enableTaskPlanning = true
        config.enableCodeAnalysis = false
        config.enableRealTimeAnalysis = false
        config.showTaskPlan = true
        config.showCodeAnalysis = false
        config.showToolRecommendations = true
        return config
    }
    
    /// Aggressive preset - maximum learning and analysis
    static var aggressive: IntelligentAssistantConfig {
        var config = IntelligentAssistantConfig()
        config.enableLearning = true
        config.enableToolRecommendations = true
        config.enableTaskPlanning = true
        config.enableCodeAnalysis = true
        config.enableRealTimeAnalysis = true
        config.showTaskPlan = true
        config.showCodeAnalysis = true
        config.showToolRecommendations = true
        config.showLearningProgress = true
        return config
    }
}

// MARK: - Configuration Manager

class IntelligentAssistantConfigManager: ObservableObject {
    
    @Published var config: IntelligentAssistantConfig
    
    static let shared = IntelligentAssistantConfigManager()
    
    private init() {
        self.config = IntelligentAssistantConfig.load()
    }
    
    /// Save current configuration
    func save() {
        config.save()
    }
    
    /// Load configuration
    func load() {
        config = IntelligentAssistantConfig.load()
    }
    
    /// Reset to defaults
    func resetToDefaults() {
        config.resetToDefaults()
        save()
    }
    
    /// Apply preset
    func applyPreset(_ preset: IntelligentAssistantConfig) {
        config = preset
        save()
    }
}
