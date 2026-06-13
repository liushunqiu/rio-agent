import Foundation

/// 智能学习系统 - 从用户行为中学习，优化推荐和预测
class IntelligentLearningSystem {
    
    // MARK: - 学习类型
    
    enum LearningType {
        case toolPreference      // 学习用户偏好的工具
        case workflowPattern     // 学习常见工作流模式
        case errorPattern        // 从错误中学习
        case successPattern      // 从成功中学习
        case userCorrection      // 从用户纠正中学习
        case projectPattern      // 项目特定模式
        case timePattern         // 时间相关模式
    }
    
    struct LearningEvent {
        let type: LearningType
        let timestamp: Date
        let context: [String: Any]
        let outcome: String
        let success: Bool
    }
    
    // MARK: - 用户行为画像
    
    struct UserProfile: Codable {
        // 工具偏好 (taskType -> [tool -> score])
        var toolPreferences: [String: [String: Double]] = [:]
        
        // 工作流模式 (成功的工作流序列)
        var workflowPatterns: [WorkflowPattern] = []
        
        // 项目特定知识
        var projectKnowledge: [String: ProjectKnowledge] = [:]
        
        // 错误解决方案库
        var errorSolutions: [ErrorSolution] = []
        
        // 用户偏好设置
        var preferences: UserPreferences = UserPreferences()
        
        // 统计数据
        var statistics: LearningStatisticsData = LearningStatisticsData()
    }
    
    struct WorkflowPattern: Codable {
        let steps: [String]
        let successCount: Int
        let failureCount: Int
        let averageTime: TimeInterval
        let lastUsed: Date
        
        var successRate: Double {
            let total = successCount + failureCount
            return total > 0 ? Double(successCount) / Double(total) : 0
        }
    }
    
    struct ProjectKnowledge: Codable {
        let projectPath: String
        var buildCommands: [String] = []
        var testCommands: [String] = []
        var commonPatterns: [String] = []
        var fileRelationships: [String: [String]] = [:]  // file -> related files
        var lastAnalyzed: Date = Date()
    }
    
    struct ErrorSolution: Codable {
        let errorPattern: String
        let solution: String
        let successCount: Int
        let lastUsed: Date
        
        var confidence: Double {
            return min(1.0, Double(successCount) / 5.0)  // 5次成功后达到最高置信度
        }
    }
    
    struct UserPreferences: Codable {
        var preferredLanguage: String = "zh"  // 偏好语言
        var verboseOutput: Bool = false       // 是否详细输出
        var autoConfirmSafe: Bool = true      // 自动确认安全命令
        var showLearningInsights: Bool = true // 显示学习洞察
        var maxPlanSteps: Int = 10            // 最大计划步骤数
    }
    
    struct LearningStatisticsData: Codable {
        var totalInteractions: Int = 0
        var successfulTasks: Int = 0
        var failedTasks: Int = 0
        var toolUsageCounts: [String: Int] = [:]
        var taskTypeCounts: [String: Int] = [:]
        var averageTaskTime: [String: TimeInterval] = [:]
        var lastActiveDate: Date = Date()
    }
    
    // MARK: - 学习数据
    
    private var userProfile: UserProfile
    private var learningEvents: [LearningEvent] = []
    private let maxEvents = 1000
    private let persistenceKey = "intelligent_learning_system_profile"
    
    // MARK: - 派生模式存储
    
    /// taskType -> [tool -> successCount]
    private var toolSuccessByTask: [String: [String: Int]] = [:]
    /// taskType -> [tool -> totalCount]
    private var toolTotalByTask: [String: [String: Int]] = [:]
    /// 成功的工作流模式
    private var workflowPatterns: [[String]] = []
    /// 最近的错误-解决方案对
    private var recentErrorSolutions: [(error: String, solution: String)] = []
    /// 用户纠正偏好
    private var userPreferences: [String: String] = [:]
    
    // MARK: - 初始化
    
    init() {
        self.userProfile = IntelligentLearningSystem.loadProfile()
        rebuildDerivedData()
    }
    
    // MARK: - 持久化
    
    private static func loadProfile() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: "intelligent_learning_system_profile"),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return UserProfile()
        }
        return profile
    }
    
    private func saveProfile() {
        userProfile.statistics.lastActiveDate = Date()
        if let data = try? JSONEncoder().encode(userProfile) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    private func rebuildDerivedData() {
        // 从 userProfile 重建派生数据
        for (taskType, tools) in userProfile.toolPreferences {
            for (tool, score) in tools {
                let count = Int(score * 10)  // 估算使用次数
                toolTotalByTask[taskType, default: [:]][tool, default: 0] += count
                if score > 0.5 {
                    toolSuccessByTask[taskType, default: [:]][tool, default: 0] += count
                }
            }
        }
        
        for pattern in userProfile.workflowPatterns where pattern.successRate > 0.7 {
            workflowPatterns.append(pattern.steps)
        }
        
        for solution in userProfile.errorSolutions {
            recentErrorSolutions.append((error: solution.errorPattern, solution: solution.solution))
        }
    }
    
    // MARK: - 学习方法
    
    /// 记录学习事件
    func recordEvent(_ event: LearningEvent) {
        learningEvents.append(event)
        
        // 保持最近事件
        if learningEvents.count > maxEvents {
            learningEvents.removeFirst(learningEvents.count - maxEvents)
        }
        
        // 处理事件
        processEvent(event)
        
        // 更新统计
        userProfile.statistics.totalInteractions += 1
        if event.success {
            userProfile.statistics.successfulTasks += 1
        } else {
            userProfile.statistics.failedTasks += 1
        }
        
        // 定期保存
        if learningEvents.count % 10 == 0 {
            saveProfile()
        }
    }
    
    /// 处理学习事件
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
        case .projectPattern:
            processProjectPattern(event)
        case .timePattern:
            processTimePattern(event)
        }
    }
    
    // MARK: - 工具偏好学习
    
    private func processToolPreference(_ event: LearningEvent) {
        guard let taskType = event.context["taskType"] as? String,
              let tool = event.context["tool"] as? String else {
            return
        }
        
        // 更新派生数据
        toolTotalByTask[taskType, default: [:]][tool, default: 0] += 1
        if event.success {
            toolSuccessByTask[taskType, default: [:]][tool, default: 0] += 1
        }
        
        // 更新用户画像
        let currentScore = userProfile.toolPreferences[taskType]?[tool] ?? 0.5
        let newScore = event.success ? min(1.0, currentScore + 0.1) : max(0.0, currentScore - 0.1)
        userProfile.toolPreferences[taskType, default: [:]][tool] = newScore
        
        // 更新使用统计
        userProfile.statistics.toolUsageCounts[tool, default: 0] += 1
    }
    
    // MARK: - 工作流模式学习
    
    private func processWorkflowPattern(_ event: LearningEvent) {
        guard let steps = event.context["steps"] as? [String] else {
            return
        }
        
        if event.success {
            // 查找现有模式
            if let index = userProfile.workflowPatterns.firstIndex(where: { $0.steps == steps }) {
                // 更新现有模式
                let existing = userProfile.workflowPatterns[index]
                userProfile.workflowPatterns[index] = WorkflowPattern(
                    steps: steps,
                    successCount: existing.successCount + 1,
                    failureCount: existing.failureCount,
                    averageTime: existing.averageTime,
                    lastUsed: Date()
                )
            } else {
                // 添加新模式
                userProfile.workflowPatterns.append(WorkflowPattern(
                    steps: steps,
                    successCount: 1,
                    failureCount: 0,
                    averageTime: 0,
                    lastUsed: Date()
                ))
            }
            
            // 保持最近的工作流模式
            if userProfile.workflowPatterns.count > 50 {
                userProfile.workflowPatterns.sort { $0.lastUsed > $1.lastUsed }
                userProfile.workflowPatterns = Array(userProfile.workflowPatterns.prefix(50))
            }
            
            workflowPatterns.append(steps)
            if workflowPatterns.count > 20 {
                workflowPatterns.removeFirst()
            }
        }
    }
    
    // MARK: - 错误模式学习
    
    private func processErrorPattern(_ event: LearningEvent) {
        guard let error = event.context["error"] as? String else {
            return
        }
        
        let solution = event.context["solution"] as? String ?? ""
        
        if !solution.isEmpty {
            // 查找现有解决方案
            if let index = userProfile.errorSolutions.firstIndex(where: { 
                $0.errorPattern == error || error.contains($0.errorPattern) 
            }) {
                // 更新现有解决方案
                let existing = userProfile.errorSolutions[index]
                userProfile.errorSolutions[index] = ErrorSolution(
                    errorPattern: existing.errorPattern,
                    solution: solution,
                    successCount: existing.successCount + 1,
                    lastUsed: Date()
                )
            } else {
                // 添加新解决方案
                userProfile.errorSolutions.append(ErrorSolution(
                    errorPattern: error,
                    solution: solution,
                    successCount: 1,
                    lastUsed: Date()
                ))
            }
            
            // 保持最近的解决方案
            if userProfile.errorSolutions.count > 100 {
                userProfile.errorSolutions.sort { $0.lastUsed > $1.lastUsed }
                userProfile.errorSolutions = Array(userProfile.errorSolutions.prefix(100))
            }
            
            recentErrorSolutions.append((error: error, solution: solution))
            if recentErrorSolutions.count > 10 {
                recentErrorSolutions.removeFirst()
            }
        }
    }
    
    // MARK: - 成功模式学习
    
    private func processSuccessPattern(_ event: LearningEvent) {
        guard let taskType = event.context["taskType"] as? String,
              let tool = event.context["tool"] as? String else {
            return
        }
        
        toolTotalByTask[taskType, default: [:]][tool, default: 0] += 1
        toolSuccessByTask[taskType, default: [:]][tool, default: 0] += 1
        
        // 更新用户画像中的工具偏好
        let currentScore = userProfile.toolPreferences[taskType]?[tool] ?? 0.5
        userProfile.toolPreferences[taskType, default: [:]][tool] = min(1.0, currentScore + 0.05)
        
        // 更新任务类型统计
        userProfile.statistics.taskTypeCounts[taskType, default: 0] += 1
    }
    
    // MARK: - 用户纠正学习
    
    private func processUserCorrection(_ event: LearningEvent) {
        guard let originalAction = event.context["originalAction"] as? String,
              let correctedAction = event.context["correctedAction"] as? String else {
            return
        }
        
        let reason = event.context["reason"] as? String ?? ""
        userPreferences[originalAction] = correctedAction + (reason.isEmpty ? "" : " (reason: \(reason))")
    }
    
    // MARK: - 项目模式学习
    
    private func processProjectPattern(_ event: LearningEvent) {
        guard let projectPath = event.context["projectPath"] as? String else {
            return
        }
        
        var knowledge = userProfile.projectKnowledge[projectPath] ?? ProjectKnowledge(projectPath: projectPath)
        
        if let buildCommand = event.context["buildCommand"] as? String {
            if !knowledge.buildCommands.contains(buildCommand) {
                knowledge.buildCommands.append(buildCommand)
            }
        }
        
        if let testCommand = event.context["testCommand"] as? String {
            if !knowledge.testCommands.contains(testCommand) {
                knowledge.testCommands.append(testCommand)
            }
        }
        
        if let pattern = event.context["pattern"] as? String {
            if !knowledge.commonPatterns.contains(pattern) {
                knowledge.commonPatterns.append(pattern)
            }
        }
        
        knowledge.lastAnalyzed = Date()
        userProfile.projectKnowledge[projectPath] = knowledge
    }
    
    // MARK: - 时间模式学习
    
    private func processTimePattern(_ event: LearningEvent) {
        // 记录任务执行时间
        if let taskType = event.context["taskType"] as? String,
           let duration = event.context["duration"] as? TimeInterval {
            let currentAvg = userProfile.statistics.averageTaskTime[taskType] ?? 0
            let count = userProfile.statistics.taskTypeCounts[taskType] ?? 1
            userProfile.statistics.averageTaskTime[taskType] = (currentAvg * Double(count - 1) + duration) / Double(count)
        }
    }
    
    // MARK: - 模式分析
    
    /// 分析模式
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
    
    // MARK: - 推荐生成
    
    /// 获取推荐
    func getRecommendations(for taskType: String) -> LearningRecommendations {
        let analysis = analyzePatterns()
        
        // 获取最佳工具
        var recommendedTools: [String] = []
        for (tool, stats) in analysis.toolSuccessRates {
            let successRate = Double(stats.success) / Double(stats.total)
            if successRate > 0.7 && stats.total >= 3 {
                recommendedTools.append(tool)
            }
        }
        
        // 获取常见错误
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
    
    /// 获取工作流预测
    func predictNextSteps(currentSteps: [String], taskType: String) -> [String] {
        // 查找匹配的工作流模式
        let matchingPatterns = userProfile.workflowPatterns.filter { pattern in
            pattern.steps.starts(with: currentSteps) && pattern.successRate > 0.7
        }
        
        // 按成功率排序
        let sortedPatterns = matchingPatterns.sorted { $0.successRate > $1.successRate }
        
        // 返回下一步建议
        if let bestPattern = sortedPatterns.first,
           bestPattern.steps.count > currentSteps.count {
            return Array(bestPattern.steps.suffix(from: currentSteps.count))
        }
        
        return []
    }
    
    /// 获取错误解决方案
    func getSolutionForError(_ error: String) -> String? {
        // 精确匹配
        if let solution = userProfile.errorSolutions.first(where: { $0.errorPattern == error }) {
            return solution.solution
        }
        
        // 模糊匹配
        let errorLower = error.lowercased()
        if let solution = userProfile.errorSolutions.first(where: { 
            errorLower.contains($0.errorPattern.lowercased()) || 
            $0.errorPattern.lowercased().contains(errorLower)
        }) {
            return solution.solution
        }
        
        return nil
    }
    
    /// 获取项目特定知识
    func getProjectKnowledge(for projectPath: String) -> ProjectKnowledge? {
        return userProfile.projectKnowledge[projectPath]
    }
    
    // MARK: - 成功率计算
    
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
    
    // MARK: - 记忆集成
    
    /// 与 AgentMemory 集成
    func integrateWithMemory(_ memory: AgentMemory) {
        let analysis = analyzePatterns()
        
        // 更新首选工具
        for (_, stats) in analysis.toolSuccessRates {
            let successRate = Double(stats.success) / Double(stats.total)
            if successRate > 0.7 && stats.total >= 3 {
                // 可以在这里映射任务类型到工具
            }
        }
    }
    
    // MARK: - 学习统计
    
    /// 获取学习统计
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
    
    /// 获取用户画像摘要
    func getUserProfileSummary() -> String {
        var summary = "## 用户学习画像\n\n"
        
        // 工具偏好
        if !userProfile.toolPreferences.isEmpty {
            summary += "### 工具偏好\n"
            for (taskType, tools) in userProfile.toolPreferences.prefix(5) {
                let topTools = tools.sorted { $0.value > $1.value }.prefix(3)
                let toolList = topTools.map { "\($0.key) (\(Int($0.value * 100))%)" }.joined(separator: ", ")
                summary += "- \(taskType): \(toolList)\n"
            }
            summary += "\n"
        }
        
        // 工作流模式
        let successfulPatterns = userProfile.workflowPatterns.filter { $0.successRate > 0.7 }
        if !successfulPatterns.isEmpty {
            summary += "### 成功工作流 (\(successfulPatterns.count) 个)\n"
            for pattern in successfulPatterns.prefix(3) {
                summary += "- \(pattern.steps.joined(separator: " → ")) (成功率: \(Int(pattern.successRate * 100))%)\n"
            }
            summary += "\n"
        }
        
        // 错误解决方案
        if !userProfile.errorSolutions.isEmpty {
            summary += "### 已学习的错误解决方案 (\(userProfile.errorSolutions.count) 个)\n"
            for solution in userProfile.errorSolutions.prefix(3) {
                summary += "- \(solution.errorPattern): \(solution.solution)\n"
            }
            summary += "\n"
        }
        
        // 统计数据
        summary += "### 统计数据\n"
        summary += "- 总交互次数: \(userProfile.statistics.totalInteractions)\n"
        summary += "- 成功任务: \(userProfile.statistics.successfulTasks)\n"
        summary += "- 失败任务: \(userProfile.statistics.failedTasks)\n"
        let successRate = userProfile.statistics.totalInteractions > 0 
            ? Double(userProfile.statistics.successfulTasks) / Double(userProfile.statistics.totalInteractions) * 100 
            : 0
        summary += "- 总体成功率: \(String(format: "%.1f", successRate))%\n"
        
        return summary
    }
    
    // MARK: - 洞察生成
    
    /// 生成学习洞察字符串用于系统提示注入
    func generateInsightsPrompt(forTaskType taskType: String, sessionTopTools: [(tool: String, count: Int)] = []) -> String {
        var sections: [String] = []
        
        // 1. 历史有效的工具
        if let toolTotals = toolTotalByTask[taskType], !toolTotals.isEmpty {
            var effectiveTools: [(tool: String, rate: Double)] = []
            let toolSuccesses = toolSuccessByTask[taskType] ?? [:]
            
            for (tool, total) in toolTotals where total >= 3 {
                let successes = toolSuccesses[tool] ?? 0
                let rate = Double(successes) / Double(total)
                if rate > 0.7 {
                    effectiveTools.append((tool: tool, rate: rate))
                }
            }
            
            if !effectiveTools.isEmpty {
                effectiveTools.sort { $0.rate > $1.rate }
                let toolList = effectiveTools.prefix(3).map { "\($0.tool) (\(Int($0.rate * 100))% success)" }.joined(separator: ", ")
                sections.append("- Historically effective tools for '\(taskType)': \(toolList)")
            }
        }
        
        // 2. 错误解决方案
        if !recentErrorSolutions.isEmpty {
            let recent = recentErrorSolutions.suffix(3)
            var errorSection = "- Known error patterns:\n"
            for entry in recent {
                errorSection += "  - \(entry.error): \(entry.solution)\n"
            }
            sections.append(errorSection)
        }
        
        // 3. 用户偏好
        if !userPreferences.isEmpty {
            var prefSection = "- User preferences:\n"
            for (original, corrected) in userPreferences.prefix(5) {
                prefSection += "  - Instead of '\(original)', prefer: \(corrected)\n"
            }
            sections.append(prefSection)
        }
        
        // 4. 会话级工具频率
        if !sessionTopTools.isEmpty {
            let toolList = sessionTopTools.map { "\($0.tool) (\($0.count)x)" }.joined(separator: ", ")
            sections.append("- Frequently used this session: \(toolList)")
        }
        
        // 5. 工作流预测
        let successfulPatterns = userProfile.workflowPatterns.filter { $0.successRate > 0.8 }
        if !successfulPatterns.isEmpty {
            let patternList = successfulPatterns.prefix(2).map { 
                $0.steps.joined(separator: " → ") 
            }.joined(separator: "; ")
            sections.append("- Successful workflows: \(patternList)")
        }
        
        guard !sections.isEmpty else { return "" }
        
        return "\n## Learning Insights\n" + sections.joined(separator: "\n")
    }
    
    // MARK: - 清除学习数据
    
    /// 清除所有学习数据
    func clearAllData() {
        userProfile = UserProfile()
        learningEvents.removeAll()
        toolSuccessByTask.removeAll()
        toolTotalByTask.removeAll()
        workflowPatterns.removeAll()
        recentErrorSolutions.removeAll()
        userPreferences.removeAll()
        saveProfile()
    }
    
    /// 清除特定项目的学习数据
    func clearProjectData(for projectPath: String) {
        userProfile.projectKnowledge.removeValue(forKey: projectPath)
        saveProfile()
    }
}

// MARK: - 支持类型

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
