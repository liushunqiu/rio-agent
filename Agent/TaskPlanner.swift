import Foundation

/// Intelligent task planner that breaks down complex tasks into manageable steps
class TaskPlanner {
    
    // MARK: - Task Types
    
    enum TaskComplexity {
        case simple      // Single step, direct execution
        case moderate    // 2-3 steps, sequential execution
        case complex     // 4+ steps, may need parallel execution
        case veryComplex // 5+ steps, needs decomposition and parallel execution
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
           lowercased.contains("查看") || lowercased.contains("查看") ||
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
           lowercased.contains("重构") || lowercased.contains("refactor") {
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
           lowercased.contains("说明") || lowercased.contains("说明") ||
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
           lowercased.contains("批量") || lowercased.contains("batch") {
            complexityScore += 2
        }
        
        // Check for complex patterns
        if lowercased.contains("系统") || lowercased.contains("system") ||
           lowercased.contains("架构") || lowercased.contains("architecture") ||
           lowercased.contains("设计") || lowercased.contains("design") {
            complexityScore += 3
        }
        
        // Determine complexity level
        let complexity: TaskComplexity
        if complexityScore <= 2 {
            complexity = .simple
        } else if complexityScore <= 4 {
            complexity = .moderate
        } else if complexityScore <= 6 {
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
    
    // MARK: - Adaptive Planning
    
    /// Adjust plan based on progress and results
    static func adjustPlan(
        originalPlan: [String],
        completedSteps: [String],
        currentResults: [String: String]
    ) -> [String] {
        // For now, return the original plan
        // In a more advanced implementation, this would analyze results
        // and adjust the plan accordingly
        return originalPlan
    }
    
    // MARK: - Memory Integration
    
    /// Learn from task execution
    static func learnFromExecution(
        task: String,
        analysis: TaskAnalysis,
        success: Bool,
        executionTime: TimeInterval,
        memory: AgentMemory?
    ) {
        // Record successful patterns
        if success {
            // Note: Memory integration will be handled by the caller
            // due to actor isolation constraints
        }
        
        // Update project knowledge if needed
        // This could be expanded to learn more about the project
    }
}
