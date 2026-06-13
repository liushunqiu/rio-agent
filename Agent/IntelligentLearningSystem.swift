import Foundation

/// Intelligent learning system that learns from user behavior and optimizes recommendations
class IntelligentLearningSystem {
    
    // MARK: - Learning Types
    
    enum LearningType {
        case toolPreference     // Learn preferred tools for task types
        case workflowPattern    // Learn common workflow patterns
        case errorPattern       // Learn from errors and their solutions
        case successPattern     // Learn from successful task completions
        case userCorrection     // Learn from user corrections to AI behavior
    }
    
    struct LearningEvent {
        let type: LearningType
        let timestamp: Date
        let context: [String: Any]
        let outcome: String
        let success: Bool
    }
    
    // MARK: - Learning Data
    
    private var learningEvents: [LearningEvent] = []
    private let maxEvents = 1000
    
    // MARK: - Learning Methods
    
    /// Record a learning event
    func recordEvent(_ event: LearningEvent) {
        learningEvents.append(event)
        
        // Keep only recent events
        if learningEvents.count > maxEvents {
            learningEvents.removeFirst(learningEvents.count - maxEvents)
        }
        
        // Process the event for learning
        processEvent(event)
    }
    
    /// Process a learning event to extract patterns
    private func processEvent(_ event: LearningEvent) {
        switch event.type {
        case .toolPreference:
            processToolPreference(event)
        case .workflowPattern:
            processWorkflowPattern(event)
        case .errorPattern:
            processErrorPattern(event)
        case .successPattern:
            processSuccessPattern(event)
        case .userCorrection:
            processUserCorrection(event)
        }
    }
    
    // MARK: - Tool Preference Learning
    
    private func processToolPreference(_ event: LearningEvent) {
        guard let _ = event.context["taskType"] as? String,
              let _ = event.context["tool"] as? String else {
            return
        }
        
        // Record successful tool usage
        if event.success {
            // This will be handled by AgentMemory
            // We're just tracking the pattern here
        }
    }
    
    // MARK: - Workflow Pattern Learning
    
    private func processWorkflowPattern(_ event: LearningEvent) {
        guard event.context["steps"] is [String] else {
            return
        }
        
        // Record successful workflow patterns
        if event.success {
            // This could be used to suggest similar workflows in the future
        }
    }
    
    // MARK: - Error Pattern Learning
    
    private func processErrorPattern(_ event: LearningEvent) {
        guard let _ = event.context["error"] as? String,
              let _ = event.context["solution"] as? String else {
            return
        }
        
        // Record error and solution for future reference
        // This will be handled by AgentMemory
    }
    
    // MARK: - Success Pattern Learning
    
    private func processSuccessPattern(_ event: LearningEvent) {
        guard let _ = event.context["taskType"] as? String,
              let _ = event.context["tool"] as? String else {
            return
        }
        
        // Record successful patterns
        // This will be handled by AgentMemory
    }
    
    // MARK: - User Correction Learning
    
    private func processUserCorrection(_ event: LearningEvent) {
        guard let _ = event.context["originalAction"] as? String,
              let _ = event.context["correctedAction"] as? String,
              let _ = event.context["reason"] as? String else {
            return
        }
        
        // Record user corrections
        // This will be handled by AgentMemory
    }
    
    // MARK: - Pattern Analysis
    
    /// Analyze patterns from learning events
    func analyzePatterns() -> LearningAnalysis {
        let recentEvents = learningEvents.suffix(100)
        
        var toolSuccessRates: [String: (success: Int, total: Int)] = [:]
        var workflowSuccessRates: [String: (success: Int, total: Int)] = [:]
        var errorPatterns: [String: Int] = [:]
        
        for event in recentEvents {
            switch event.type {
            case .toolPreference:
                if let tool = event.context["tool"] as? String {
                    let current = toolSuccessRates[tool] ?? (0, 0)
                    toolSuccessRates[tool] = (
                        success: current.success + (event.success ? 1 : 0),
                        total: current.total + 1
                    )
                }
                
            case .workflowPattern:
                if let workflow = event.context["workflow"] as? String {
                    let current = workflowSuccessRates[workflow] ?? (0, 0)
                    workflowSuccessRates[workflow] = (
                        success: current.success + (event.success ? 1 : 0),
                        total: current.total + 1
                    )
                }
                
            case .errorPattern:
                if let error = event.context["error"] as? String {
                    errorPatterns[error, default: 0] += 1
                }
                
            default:
                break
            }
        }
        
        return LearningAnalysis(
            toolSuccessRates: toolSuccessRates,
            workflowSuccessRates: workflowSuccessRates,
            errorPatterns: errorPatterns,
            totalEvents: recentEvents.count
        )
    }
    
    // MARK: - Recommendations
    
    /// Get recommendations based on learning
    func getRecommendations(for taskType: String) -> LearningRecommendations {
        let analysis = analyzePatterns()
        
        // Get best tools for this task type
        var recommendedTools: [String] = []
        for (tool, stats) in analysis.toolSuccessRates {
            let successRate = Double(stats.success) / Double(stats.total)
            if successRate > 0.7 && stats.total >= 3 {
                recommendedTools.append(tool)
            }
        }
        
        // Get common errors to avoid
        var commonErrors: [String] = []
        for (error, count) in analysis.errorPatterns {
            if count >= 3 {
                commonErrors.append(error)
            }
        }
        
        return LearningRecommendations(
            recommendedTools: recommendedTools,
            commonErrors: commonErrors,
            successRate: calculateOverallSuccessRate(analysis)
        )
    }
    
    // MARK: - Success Rate Calculation
    
    private func calculateOverallSuccessRate(_ analysis: LearningAnalysis) -> Double {
        var totalSuccess = 0
        var totalAttempts = 0
        
        for (_, stats) in analysis.toolSuccessRates {
            totalSuccess += stats.success
            totalAttempts += stats.total
        }
        
        for (_, stats) in analysis.workflowSuccessRates {
            totalSuccess += stats.success
            totalAttempts += stats.total
        }
        
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalSuccess) / Double(totalAttempts)
    }
    
    // MARK: - Memory Integration
    
    /// Integrate with AgentMemory for persistent learning
    func integrateWithMemory(_ memory: AgentMemory) {
        let analysis = analyzePatterns()
        
        // Update preferred tools based on success rates
        for (tool, stats) in analysis.toolSuccessRates {
            let successRate = Double(stats.success) / Double(stats.total)
            if successRate > 0.7 && stats.total >= 3 {
                // This tool is successful for certain task types
                // We could map task types to tools here
            }
        }
    }
    
    // MARK: - Learning Statistics
    
    /// Get learning statistics
    func getStatistics() -> LearningStatistics {
        let analysis = analyzePatterns()
        
        return LearningStatistics(
            totalEvents: learningEvents.count,
            toolSuccessRates: analysis.toolSuccessRates,
            workflowSuccessRates: analysis.workflowSuccessRates,
            errorPatterns: analysis.errorPatterns,
            overallSuccessRate: calculateOverallSuccessRate(analysis)
        )
    }
}

// MARK: - Supporting Types

struct LearningAnalysis {
    let toolSuccessRates: [String: (success: Int, total: Int)]
    let workflowSuccessRates: [String: (success: Int, total: Int)]
    let errorPatterns: [String: Int]
    let totalEvents: Int
}

struct LearningRecommendations {
    let recommendedTools: [String]
    let commonErrors: [String]
    let successRate: Double
}

struct LearningStatistics {
    let totalEvents: Int
    let toolSuccessRates: [String: (success: Int, total: Int)]
    let workflowSuccessRates: [String: (success: Int, total: Int)]
    let errorPatterns: [String: Int]
    let overallSuccessRate: Double
}
