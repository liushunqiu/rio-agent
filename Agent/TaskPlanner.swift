import Foundation
import os

/// Intelligent task planner that breaks down complex tasks into manageable steps
class TaskPlanner {
    
    // MARK: - Task Types
    
    enum TaskComplexity: CustomStringConvertible {
        case simple      // Single step, direct execution
        case moderate    // 2-3 steps, sequential execution
        case complex     // 4+ steps, may need parallel execution
        case veryComplex // 5+ steps, needs decomposition and parallel execution

        var description: String {
            switch self {
            case .simple: return "simple"
            case .moderate: return "moderate"
            case .complex: return "complex"
            case .veryComplex: return "veryComplex"
            }
        }
    }
    
    enum TaskStep {
        case explore      // Explore project structure
        case read         // Read file content
        case analyze      // Analyze code or data
        case modify       // Make changes to files
        case test         // Run tests or verify
        case document     // Generate documentation
        case commit       // Version control operations
        case deploy       // Deployment operations
    }
    
    // MARK: - Task Analysis
    
    struct TaskAnalysis {
        let complexity: TaskComplexity
        let estimatedSteps: Int
        let suggestedSteps: [TaskStep]
        let reasoning: String
        let estimatedTime: TimeInterval // in seconds

        /// Concrete steps returned by the planning model. Empty means the caller
        /// should fall back to local decomposition.
        let plannedSteps: [String]

        init(
            complexity: TaskComplexity,
            estimatedSteps: Int,
            suggestedSteps: [TaskStep],
            reasoning: String,
            estimatedTime: TimeInterval,
            plannedSteps: [String] = []
        ) {
            self.complexity = complexity
            self.estimatedSteps = estimatedSteps
            self.suggestedSteps = suggestedSteps
            self.reasoning = reasoning
            self.estimatedTime = estimatedTime
            self.plannedSteps = plannedSteps
        }
    }
    
    // MARK: - AI-Generated Task Plan
    
    struct AITaskPlan: Codable {
        let steps: [String]
        let reasoning: String
        let estimatedTime: String
        let complexity: String
    }
    
    // MARK: - Analysis Methods
    
    /// Analyze task complexity and suggest steps
    static func analyzeTask(_ input: String, memory: AgentMemory?) -> TaskAnalysis {
        let lowercased = input.lowercased()
        
        // Count complexity indicators
        var complexityScore = 0
        var suggestedSteps: [TaskStep] = []
        
        // Check for exploration needs
        if lowercased.contains("项目") || lowercased.contains("project") ||
           lowercased.contains("结构") || lowercased.contains("structure") ||
           lowercased.contains("目录") || lowercased.contains("directory") {
            complexityScore += 1
            suggestedSteps.append(.explore)
        }
        
        // Check for reading needs
        if lowercased.contains("读") || lowercased.contains("read") ||
           lowercased.contains("查看") ||
           lowercased.contains("内容") || lowercased.contains("content") {
            complexityScore += 1
            suggestedSteps.append(.read)
        }
        
        // Check for analysis needs
        if lowercased.contains("分析") || lowercased.contains("analyze") ||
           lowercased.contains("理解") || lowercased.contains("understand") ||
           lowercased.contains("解释") || lowercased.contains("explain") {
            complexityScore += 2
            suggestedSteps.append(.analyze)
        }
        
        // Check for modification needs
        if lowercased.contains("修改") || lowercased.contains("modify") ||
           lowercased.contains("改") || lowercased.contains("change") ||
           lowercased.contains("修复") || lowercased.contains("fix") ||
           lowercased.contains("重构") || lowercased.contains("refactor") ||
           lowercased.contains("添加") || lowercased.contains("add") ||
           lowercased.contains("删除") || lowercased.contains("delete") ||
           lowercased.contains("更新") || lowercased.contains("update") {
            complexityScore += 2
            suggestedSteps.append(.modify)
        }
        
        // Check for testing needs
        if lowercased.contains("测试") || lowercased.contains("test") ||
           lowercased.contains("验证") || lowercased.contains("verify") ||
           lowercased.contains("检查") || lowercased.contains("check") {
            complexityScore += 1
            suggestedSteps.append(.test)
        }
        
        // Check for documentation needs
        if lowercased.contains("文档") || lowercased.contains("document") ||
           lowercased.contains("说明") ||
           lowercased.contains("readme") {
            complexityScore += 1
            suggestedSteps.append(.document)
        }
        
        // Check for version control needs
        if lowercased.contains("git") || lowercased.contains("commit") ||
           lowercased.contains("提交") || lowercased.contains("版本") {
            complexityScore += 1
            suggestedSteps.append(.commit)
        }
        
        // Check for deployment needs
        if lowercased.contains("部署") || lowercased.contains("deploy") ||
           lowercased.contains("发布") || lowercased.contains("release") {
            complexityScore += 2
            suggestedSteps.append(.deploy)
        }
        
        // Check for multiple file operations
        if lowercased.contains("所有") || lowercased.contains("all") ||
           lowercased.contains("每个") || lowercased.contains("every") ||
           lowercased.contains("批量") || lowercased.contains("batch") ||
           lowercased.contains("多个") || lowercased.contains("multiple") {
            complexityScore += 2
        }

        // Check for complex patterns
        if lowercased.contains("系统") || lowercased.contains("system") ||
           lowercased.contains("架构") || lowercased.contains("architecture") ||
           lowercased.contains("设计") || lowercased.contains("design") ||
           lowercased.contains("整合") || lowercased.contains("integrate") {
            complexityScore += 3
        }

        // Check for command execution (commonly overlooked)
        if lowercased.contains("运行") || lowercased.contains("run") ||
           lowercased.contains("执行") || lowercased.contains("execute") ||
           lowercased.contains("命令") || lowercased.contains("command") {
            complexityScore += 1
        }

        // Determine complexity level (适度阈值，避免用户正常描述任务被误判为复杂)
        let complexity: TaskComplexity
        if complexityScore <= 2 {
            complexity = .simple
        } else if complexityScore <= 4 {
            complexity = .moderate
        } else if complexityScore <= 7 {
            complexity = .complex
        } else {
            complexity = .veryComplex
        }
        
        // Estimate steps based on complexity
        let estimatedSteps: Int
        switch complexity {
        case .simple:
            estimatedSteps = 1
        case .moderate:
            estimatedSteps = 2 + suggestedSteps.count
        case .complex:
            estimatedSteps = 3 + suggestedSteps.count
        case .veryComplex:
            estimatedSteps = 4 + suggestedSteps.count
        }
        
        // Estimate time (in seconds)
        let estimatedTime: TimeInterval
        switch complexity {
        case .simple:
            estimatedTime = 30
        case .moderate:
            estimatedTime = 60
        case .complex:
            estimatedTime = 120
        case .veryComplex:
            estimatedTime = 180
        }
        
        // Generate reasoning
        let reasoning = generateReasoning(
            complexity: complexity,
            suggestedSteps: suggestedSteps,
            input: input
        )
        
        RioLogger.agent.debug("📊 TaskPlanner - 复杂度分数: \(complexityScore), 复杂度: \(complexity, privacy: .public), 步骤类型: \(suggestedSteps.map { "\($0)" }, privacy: .public)")

        return TaskAnalysis(
            complexity: complexity,
            estimatedSteps: estimatedSteps,
            suggestedSteps: suggestedSteps,
            reasoning: reasoning,
            estimatedTime: estimatedTime
        )
    }
    
    // MARK: - Reasoning Generation
    
    private static func generateReasoning(
        complexity: TaskComplexity,
        suggestedSteps: [TaskStep],
        input: String
    ) -> String {
        var reasoning = "Based on the task description, I've identified the following:\n\n"
        
        // Describe complexity
        switch complexity {
        case .simple:
            reasoning += "This appears to be a simple task that can be completed in a single step.\n"
        case .moderate:
            reasoning += "This is a moderate task that requires a few steps to complete.\n"
        case .complex:
            reasoning += "This is a complex task that needs careful planning and multiple steps.\n"
        case .veryComplex:
            reasoning += "This is a very complex task that should be broken down into smaller sub-tasks.\n"
        }
        
        // Describe suggested steps
        if !suggestedSteps.isEmpty {
            reasoning += "\nSuggested steps:\n"
            for (index, step) in suggestedSteps.enumerated() {
                let stepDescription: String
                switch step {
                case .explore:
                    stepDescription = "Explore project structure to understand the codebase"
                case .read:
                    stepDescription = "Read relevant files to understand the context"
                case .analyze:
                    stepDescription = "Analyze code or data to identify patterns or issues"
                case .modify:
                    stepDescription = "Make necessary changes to files"
                case .test:
                    stepDescription = "Run tests or verify the changes work correctly"
                case .document:
                    stepDescription = "Update or create documentation"
                case .commit:
                    stepDescription = "Commit changes to version control"
                case .deploy:
                    stepDescription = "Deploy or publish the changes"
                }
                reasoning += "\(index + 1). \(stepDescription)\n"
            }
        }
        
        return reasoning
    }
    
    // MARK: - Task Decomposition
    
    /// Break down complex task into sub-tasks
    static func decomposeTask(_ input: String, memory: AgentMemory?) -> [String] {
        let analysis = analyzeTask(input, memory: memory)
        
        // For simple tasks, return as is
        guard analysis.complexity != .simple else {
            return [input]
        }
        
        // For moderate tasks, create a simple plan
        if analysis.complexity == .moderate {
            return createModeratePlan(input, analysis: analysis)
        }
        
        // For complex tasks, create a detailed plan
        if analysis.complexity == .complex {
            return createComplexPlan(input, analysis: analysis)
        }
        
        // For very complex tasks, create a comprehensive plan
        return createVeryComplexPlan(input, analysis: analysis)
    }
    
    // MARK: - Plan Creation
    
    private static func createModeratePlan(_ input: String, analysis: TaskAnalysis) -> [String] {
        var plan: [String] = []
        
        // Add exploration step if needed
        if analysis.suggestedSteps.contains(.explore) {
            plan.append("Explore the project structure to understand the codebase")
        }
        
        // Add reading step if needed
        if analysis.suggestedSteps.contains(.read) {
            plan.append("Read relevant files to understand the context")
        }
        
        // Add main task
        plan.append(input)
        
        return plan
    }
    
    private static func createComplexPlan(_ input: String, analysis: TaskAnalysis) -> [String] {
        var plan: [String] = []
        
        // Add exploration step
        if analysis.suggestedSteps.contains(.explore) {
            plan.append("Explore the project structure and identify key files")
        }
        
        // Add reading step
        if analysis.suggestedSteps.contains(.read) {
            plan.append("Read and analyze relevant files to understand the codebase")
        }
        
        // Add analysis step
        if analysis.suggestedSteps.contains(.analyze) {
            plan.append("Analyze the code to identify patterns, issues, or areas for improvement")
        }
        
        // Add modification step
        if analysis.suggestedSteps.contains(.modify) {
            plan.append("Make necessary changes to implement the requested modifications")
        }
        
        // Add testing step
        if analysis.suggestedSteps.contains(.test) {
            plan.append("Run tests to verify the changes work correctly")
        }
        
        // Add documentation step
        if analysis.suggestedSteps.contains(.document) {
            plan.append("Update documentation to reflect the changes")
        }
        
        // Add commit step
        if analysis.suggestedSteps.contains(.commit) {
            plan.append("Commit the changes to version control")
        }
        
        return plan
    }
    
    private static func createVeryComplexPlan(_ input: String, analysis: TaskAnalysis) -> [String] {
        var plan: [String] = []
        
        // Phase 1: Understanding
        plan.append("Phase 1: Understanding the Problem")
        if analysis.suggestedSteps.contains(.explore) {
            plan.append("- Explore project structure and identify all relevant files")
        }
        if analysis.suggestedSteps.contains(.read) {
            plan.append("- Read and analyze all relevant source files")
        }
        if analysis.suggestedSteps.contains(.analyze) {
            plan.append("- Analyze code patterns, dependencies, and potential issues")
        }
        
        // Phase 2: Planning
        plan.append("\nPhase 2: Planning the Solution")
        plan.append("- Design the approach for implementing the changes")
        plan.append("- Identify potential risks and mitigation strategies")
        plan.append("- Create a detailed implementation plan")
        
        // Phase 3: Implementation
        plan.append("\nPhase 3: Implementation")
        if analysis.suggestedSteps.contains(.modify) {
            plan.append("- Implement the changes step by step")
            plan.append("- Verify each change works as expected")
        }
        
        // Phase 4: Verification
        plan.append("\nPhase 4: Verification and Testing")
        if analysis.suggestedSteps.contains(.test) {
            plan.append("- Run comprehensive tests to verify the changes")
            plan.append("- Check for any regressions or side effects")
        }
        
        // Phase 5: Finalization
        plan.append("\nPhase 5: Finalization")
        if analysis.suggestedSteps.contains(.document) {
            plan.append("- Update documentation to reflect the changes")
        }
        if analysis.suggestedSteps.contains(.commit) {
            plan.append("- Commit the changes to version control")
        }
        if analysis.suggestedSteps.contains(.deploy) {
            plan.append("- Deploy or publish the changes")
        }
        
        return plan
    }
    
    // MARK: - Plan Formatting
    
    /// Format task plan for display
    static func formatPlan(_ plan: [String]) -> String {
        var formatted = "## Task Plan\n\n"

        for (index, step) in plan.enumerated() {
            // Check if this is a phase header
            if step.hasPrefix("Phase") || step.hasPrefix("阶段") {
                formatted += "\n### \(step)\n"
            } else if step.hasPrefix("-") {
                // This is a sub-step
                formatted += "\(step)\n"
            } else {
                // This is a main step
                formatted += "\(index + 1). \(step)\n"
            }
        }

        return formatted
    }

    /// Format task plan with complexity metadata for execution display
    static func formatPlanForExecution(_ plan: [String], analysis: TaskAnalysis) -> String {
        var formatted = "## Task Plan\n"
        formatted += "Complexity: \(analysis.complexity) | Steps: \(plan.count) | Est. time: \(Int(analysis.estimatedTime))s\n\n"

        for (index, step) in plan.enumerated() {
            if step.hasPrefix("Phase") || step.hasPrefix("阶段") {
                formatted += "\n### \(step)\n"
            } else if step.hasPrefix("-") {
                formatted += "\(step)\n"
            } else {
                formatted += "\(index + 1). \(step)\n"
            }
        }

        return formatted
    }

    // MARK: - Execution Guidance
    
    /// Generate execution guidance for the AI
    static func generateExecutionGuidance(
        analysis: TaskAnalysis,
        currentStep: Int?,
        totalSteps: Int?
    ) -> String {
        var guidance = "\n[Task Execution Guidance]\n"
        
        // Add complexity information
        guidance += "Task complexity: \(analysis.complexity)\n"
        guidance += "Estimated steps: \(analysis.estimatedSteps)\n"
        guidance += "Estimated time: \(Int(analysis.estimatedTime)) seconds\n"
        
        // Add current progress if available
        if let current = currentStep, let total = totalSteps {
            guidance += "Progress: \(current)/\(total) steps completed\n"
        }
        
        // Add reasoning
        guidance += "\n\(analysis.reasoning)\n"
        
        return guidance
    }
    
    // MARK: - AI-Enhanced Task Analysis

    /// Generate a plan using AI (to be called from AgentEngine)
    static func generatePlanWithAI(_ input: String, aiService: AIService, model: String = AIProvider.claude.defaultPlanningModel) async -> AITaskPlan? {
        let planPrompt = """
        分析以下任务，生成一个详细的执行计划。
        
        任务描述：\(input)
        
        请返回以下 JSON 格式：
        {
            "steps": ["步骤1", "步骤2", ...],
            "reasoning": "为什么这样规划",
            "estimatedTime": "预计时间",
            "complexity": "简单/中等/复杂/非常复杂"
        }
        
        注意：
        1. 每个步骤应该是具体的、可执行的
        2. 考虑任务的依赖关系
        3. 如果需要探索项目结构，应该作为第一步
        4. 如果需要修改文件，应该先读取理解
        5. 如果需要测试，应该在修改后进行
        """
        
        do {
            let response = try await aiService.sendMessage(
                [Message.system(planPrompt)],
                tools: [],
                model: model,
                maxTokens: 1000
            )
            
            if let content = response.content {
                // Try to parse JSON from the response
                if let jsonData = content.data(using: String.Encoding.utf8) {
                    let plan = try JSONDecoder().decode(AITaskPlan.self, from: jsonData)
                    return plan
                }
            }
        } catch {
            RioLogger.agent.error("AI 规划生成失败: \(error.localizedDescription, privacy: .public)")
        }
        
        return nil
    }
    
    /// Improved task analysis that uses AI when available
    static func analyzeTaskEnhanced(_ input: String, memory: AgentMemory?, aiService: AIService? = nil, model: String = AIProvider.claude.defaultPlanningModel) async -> TaskAnalysis {
        // First, do the quick analysis
        let quickAnalysis = analyzeTask(input, memory: memory)
        
        // If we have an AI service and the task is complex, try AI planning
        if let aiService = aiService, quickAnalysis.complexity != .simple {
            if let aiPlan = await generatePlanWithAI(input, aiService: aiService, model: model) {
                // Convert AI plan to TaskAnalysis
                let complexity: TaskComplexity
                switch aiPlan.complexity {
                case "简单":
                    complexity = .simple
                case "中等":
                    complexity = .moderate
                case "复杂":
                    complexity = .complex
                case "非常复杂":
                    complexity = .veryComplex
                default:
                    complexity = quickAnalysis.complexity
                }
                
                return TaskAnalysis(
                    complexity: complexity,
                    estimatedSteps: aiPlan.steps.count,
                    suggestedSteps: quickAnalysis.suggestedSteps, // Keep the suggested steps from quick analysis
                    reasoning: aiPlan.reasoning,
                    estimatedTime: parseEstimatedTime(aiPlan.estimatedTime),
                    plannedSteps: aiPlan.steps
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
        }
        
        // Fall back to quick analysis
        return quickAnalysis
    }
    
    /// Parse estimated time string to TimeInterval
    private static func parseEstimatedTime(_ timeString: String) -> TimeInterval {
        // Try to parse time like "5分钟", "10分钟", "1小时"
        let lowercased = timeString.lowercased()
        
        if lowercased.contains("分钟") || lowercased.contains("minute") {
            let numbers = timeString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
            if let minutes = numbers.first {
                return TimeInterval(minutes * 60)
            }
        }
        
        if lowercased.contains("小时") || lowercased.contains("hour") {
            let numbers = timeString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
            if let hours = numbers.first {
                return TimeInterval(hours * 3600)
            }
        }
        
        // Default to 5 minutes
        return 300
    }
}
