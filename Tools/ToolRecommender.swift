import Foundation

/// Analyzes user intent and recommends optimal tool combinations
class ToolRecommender {
    
    /// Task types that can be inferred from user input
    enum TaskType: String {
        case fileExploration        // "show me the project structure", "what files are in..."
        case codeReading            // "read this file", "show me the code"
        case codeSearch             // "find all usages of", "search for pattern"
        case codeModification       // "change this to", "fix the bug in"
        case multiFileRefactoring   // "rename this function everywhere", "update all imports"
        case projectSetup           // "initialize project", "set up configuration"
        case debugging              // "fix this error", "debug the issue"
        case testing                // "run tests", "check if this works"
        case versionControl         // "commit changes", "check git status"
        case unknown
        
        var description: String {
            return self.rawValue
        }
    }
    
    /// Recommended tool sequence for each task type
    struct ToolRecommendation {
        let primaryTools: [String]      // Main tools to use
        let optionalTools: [String]     // May be useful
        let avoidTools: [String]        // Don't use these
        let reasoning: String           // Why this recommendation
    }
    
    /// Analyze user input and determine task type
    static func classifyTask(_ input: String) -> TaskType {
        let lowercased = input.lowercased()
        
        // File exploration patterns
        if lowercased.contains("structure") || lowercased.contains("目录") ||
           lowercased.contains("文件夹") || lowercased.contains("list files") ||
           lowercased.contains("show me") && (lowercased.contains("project") || lowercased.contains("directory")) {
            return .fileExploration
        }
        
        // Code reading patterns
        if lowercased.contains("read") || lowercased.contains("show") ||
           lowercased.contains("查看") || lowercased.contains("看一") ||
           lowercased.contains("内容") {
            return .codeReading
        }
        
        // Code search patterns
        if lowercased.contains("find") || lowercased.contains("search") ||
           lowercased.contains("查找") || lowercased.contains("搜索") ||
           lowercased.contains("where") || lowercased.contains("哪里") {
            return .codeSearch
        }
        
        // Code modification patterns
        if lowercased.contains("fix") || lowercased.contains("change") ||
           lowercased.contains("modify") || lowercased.contains("update") ||
           lowercased.contains("修改") || lowercased.contains("修复") ||
           lowercased.contains("改") {
            return .codeModification
        }
        
        // Multi-file refactoring patterns
        if lowercased.contains("rename") || lowercased.contains("refactor") ||
           lowercased.contains("everywhere") || lowercased.contains("all") ||
           lowercased.contains("重命名") || lowercased.contains("重构") ||
           lowercased.contains("所有") || lowercased.contains("全部") {
            return .multiFileRefactoring
        }
        
        // Debugging patterns
        if lowercased.contains("debug") || lowercased.contains("error") ||
           lowercased.contains("bug") || lowercased.contains("issue") ||
           lowercased.contains("调试") || lowercased.contains("错误") ||
           lowercased.contains("问题") {
            return .debugging
        }
        
        // Testing patterns
        if lowercased.contains("test") || lowercased.contains("测试") ||
           lowercased.contains("check") || lowercased.contains("验证") {
            return .testing
        }
        
        // Version control patterns
        if lowercased.contains("git") || lowercased.contains("commit") ||
           lowercased.contains("push") || lowercased.contains("pull") ||
           lowercased.contains("提交") || lowercased.contains("版本") {
            return .versionControl
        }
        
        return .unknown
    }
    
    /// Get tool recommendations based on task type
    static func recommend(for taskType: TaskType) -> ToolRecommendation {
        switch taskType {
        case .fileExploration:
            return ToolRecommendation(
                primaryTools: ["list_directory", "find_files"],
                optionalTools: ["read_file"],
                avoidTools: ["execute_command", "write_file"],
                reasoning: "Start with directory listing to understand structure, then find specific files"
            )
            
        case .codeReading:
            return ToolRecommendation(
                primaryTools: ["read_file"],
                optionalTools: ["search_files", "list_directory"],
                avoidTools: ["execute_command", "write_file"],
                reasoning: "Use read_file for direct file access, avoid shell commands for reading"
            )
            
        case .codeSearch:
            return ToolRecommendation(
                primaryTools: ["search_files", "find_files"],
                optionalTools: ["read_file"],
                avoidTools: ["execute_command"],
                reasoning: "Use search_files for content search, find_files for name-based search"
            )
            
        case .codeModification:
            return ToolRecommendation(
                primaryTools: ["read_file", "edit_file"],
                optionalTools: ["search_files"],
                avoidTools: ["write_file"],
                reasoning: "First read to understand context, then use edit_file for targeted changes"
            )
            
        case .multiFileRefactoring:
            return ToolRecommendation(
                primaryTools: ["search_files", "apply_patch"],
                optionalTools: ["read_file", "find_files"],
                avoidTools: ["write_file", "execute_command"],
                reasoning: "Search for all occurrences, then use apply_patch for coordinated changes"
            )
            
        case .projectSetup:
            return ToolRecommendation(
                primaryTools: ["list_directory", "read_file", "write_file"],
                optionalTools: ["execute_command"],
                avoidTools: [],
                reasoning: "Explore existing structure, then create configuration files"
            )
            
        case .debugging:
            return ToolRecommendation(
                primaryTools: ["read_file", "search_files", "execute_command"],
                optionalTools: ["list_directory", "find_files"],
                avoidTools: ["write_file"],
                reasoning: "Read error context, search for related code, run diagnostic commands"
            )
            
        case .testing:
            return ToolRecommendation(
                primaryTools: ["execute_command"],
                optionalTools: ["read_file", "search_files"],
                avoidTools: ["write_file", "edit_file"],
                reasoning: "Use execute_command to run tests, read test files if needed"
            )
            
        case .versionControl:
            return ToolRecommendation(
                primaryTools: ["execute_command"],
                optionalTools: ["read_file"],
                avoidTools: ["write_file", "edit_file"],
                reasoning: "Use git commands via execute_command for version control operations"
            )
            
        case .unknown:
            return ToolRecommendation(
                primaryTools: ["list_directory", "read_file"],
                optionalTools: ["search_files", "find_files"],
                avoidTools: [],
                reasoning: "Start by exploring the project structure to understand context"
            )
        }
    }
    
    /// Generate a brief tool usage hint for the system prompt
    static func generateHint(for input: String) -> String {
        let taskType = classifyTask(input)
        let recommendation = recommend(for: taskType)
        
        guard taskType != .unknown else { return "" }
        
        var hint = "\n[Tool Recommendation]\n"
        hint += "Task type: \(taskType)\n"
        hint += "Primary tools: \(recommendation.primaryTools.joined(separator: ", "))\n"
        
        if !recommendation.avoidTools.isEmpty {
            hint += "Avoid: \(recommendation.avoidTools.joined(separator: ", "))\n"
        }
        
        hint += "Reasoning: \(recommendation.reasoning)\n"
        
        return hint
    }
    
    /// Generate tool hint with memory integration
    static func generateHintWithMemory(for input: String, memory: AgentMemory?, config: IntelligentAssistantConfig? = nil) -> String {
        // Check if tool recommendations are enabled
        let enableRecommendations = config?.enableToolRecommendations ?? true
        guard enableRecommendations else { return "" }
        
        let taskType = classifyTask(input)
        let recommendation = recommend(for: taskType)
        
        guard taskType != .unknown else { return "" }
        
        var hint = "\n[Tool Recommendation]\n"
        hint += "Task type: \(taskType)\n"
        
        // Note: We can't directly access memory here due to actor isolation
        // The memory integration will be handled in the system prompt generation
        
        hint += "Primary tools: \(recommendation.primaryTools.joined(separator: ", "))\n"
        
        if !recommendation.avoidTools.isEmpty {
            hint += "Avoid: \(recommendation.avoidTools.joined(separator: ", "))\n"
        }
        
        hint += "Reasoning: \(recommendation.reasoning)\n"
        
        return hint
    }
}
