import Foundation

/// Intelligent code analyzer that provides code quality insights and suggestions
class IntelligentCodeAnalyzer {
    
    // MARK: - Code Quality Metrics
    
    enum CodeQualityMetric {
        case readability
        case maintainability
        case complexity
        case testability
        case documentation
        case performance
    }
    
    struct CodeQualityScore {
        let metric: CodeQualityMetric
        let score: Double // 0.0 - 1.0
        let issues: [CodeIssue]
        let suggestions: [String]
    }
    
    struct CodeIssue {
        let severity: IssueSeverity
        let message: String
        let line: Int?
        let column: Int?
    }
    
    enum IssueSeverity {
        case low
        case medium
        case high
        case critical
    }
    
    // MARK: - Analysis Methods
    
    /// Analyze code quality for a given file
    static func analyzeCodeQuality(_ content: String, fileType: ContextAwareness.FileType) -> [CodeQualityScore] {
        var scores: [CodeQualityScore] = []
        
        // Analyze readability
        scores.append(analyzeReadability(content, fileType: fileType))
        
        // Analyze maintainability
        scores.append(analyzeMaintainability(content, fileType: fileType))
        
        // Analyze complexity
        scores.append(analyzeComplexity(content, fileType: fileType))
        
        // Analyze testability
        scores.append(analyzeTestability(content, fileType: fileType))
        
        // Analyze documentation
        scores.append(analyzeDocumentation(content, fileType: fileType))
        
        return scores
    }
    
    // MARK: - Readability Analysis
    
    private static func analyzeReadability(_ content: String, fileType: ContextAwareness.FileType) -> CodeQualityScore {
        var issues: [CodeIssue] = []
        var suggestions: [String] = []
        var score = 1.0
        
        let lines = content.components(separatedBy: .newlines)
        
        // Check line length
        for (index, line) in lines.enumerated() {
            if line.count > 120 {
                issues.append(CodeIssue(
                    severity: .medium,
                    message: "Line is too long (\(line.count) characters)",
                    line: index + 1,
                    column: nil
                ))
                score -= 0.05
            }
        }
        
        // Check for empty lines (good practice)
        var emptyLineCount = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyLineCount += 1
            }
        }
        
        let emptyLineRatio = Double(emptyLineCount) / Double(max(lines.count, 1))
        if emptyLineRatio > 0.3 {
            suggestions.append("Consider reducing empty lines to improve readability")
            score -= 0.1
        }
        
        // Check for consistent indentation
        var indentationIssues = 0
        var previousIndentation = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let indentation = line.count - trimmed.count
            
            if indentation > previousIndentation + 4 && index > 0 {
                indentationIssues += 1
            }
            
            previousIndentation = indentation
        }
        
        if indentationIssues > 3 {
            issues.append(CodeIssue(
                severity: .low,
                message: "Inconsistent indentation detected",
                line: nil,
                column: nil
            ))
            score -= 0.1
        }
        
        return CodeQualityScore(
            metric: .readability,
            score: max(0.0, score),
            issues: issues,
            suggestions: suggestions
        )
    }
    
    // MARK: - Maintainability Analysis
    
    private static func analyzeMaintainability(_ content: String, fileType: ContextAwareness.FileType) -> CodeQualityScore {
        var issues: [CodeIssue] = []
        var suggestions: [String] = []
        var score = 1.0
        
        // Check for long functions/methods
        let functionPatterns = getFunctionPatterns(for: fileType)
        for pattern in functionPatterns {
            let functions = findFunctions(in: content, pattern: pattern)
            for function in functions {
                let lineCount = function.body.components(separatedBy: .newlines).count
                if lineCount > 50 {
                    issues.append(CodeIssue(
                        severity: .high,
                        message: "Function '\(function.name)' is too long (\(lineCount) lines)",
                        line: function.startLine,
                        column: nil
                    ))
                    score -= 0.15
                }
            }
        }
        
        // Check for code duplication
        let duplicatePatterns = findDuplicatePatterns(in: content)
        if duplicatePatterns.count > 2 {
            issues.append(CodeIssue(
                severity: .medium,
                message: "Potential code duplication detected",
                line: nil,
                column: nil
            ))
            suggestions.append("Consider refactoring duplicated code into reusable functions")
            score -= 0.1
        }
        
        // Check for magic numbers
        let magicNumbers = findMagicNumbers(in: content)
        if magicNumbers.count > 5 {
            issues.append(CodeIssue(
                severity: .medium,
                message: "Too many magic numbers found",
                line: nil,
                column: nil
            ))
            suggestions.append("Replace magic numbers with named constants")
            score -= 0.1
        }
        
        return CodeQualityScore(
            metric: .maintainability,
            score: max(0.0, score),
            issues: issues,
            suggestions: suggestions
        )
    }
    
    // MARK: - Complexity Analysis
    
    private static func analyzeComplexity(_ content: String, fileType: ContextAwareness.FileType) -> CodeQualityScore {
        var issues: [CodeIssue] = []
        var suggestions: [String] = []
        var score = 1.0
        
        let lines = content.components(separatedBy: .newlines)
        
        // Count control flow statements
        var controlFlowCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("if ") || trimmed.contains("else ") ||
               trimmed.contains("for ") || trimmed.contains("while ") ||
               trimmed.contains("switch ") || trimmed.contains("case ") ||
               trimmed.contains("guard ") || trimmed.contains("catch ") {
                controlFlowCount += 1
            }
        }
        
        let controlFlowDensity = Double(controlFlowCount) / Double(max(lines.count, 1))
        if controlFlowDensity > 0.3 {
            issues.append(CodeIssue(
                severity: .high,
                message: "High complexity detected - too many control flow statements",
                line: nil,
                column: nil
            ))
            suggestions.append("Consider refactoring to reduce complexity")
            score -= 0.2
        }
        
        // Check nesting depth
        var maxNestingDepth = 0
        var currentNestingDepth = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("{") {
                currentNestingDepth += 1
                maxNestingDepth = max(maxNestingDepth, currentNestingDepth)
            }
            if trimmed.contains("}") {
                currentNestingDepth = max(0, currentNestingDepth - 1)
            }
        }
        
        if maxNestingDepth > 5 {
            issues.append(CodeIssue(
                severity: .high,
                message: "Excessive nesting depth (\(maxNestingDepth) levels)",
                line: nil,
                column: nil
            ))
            suggestions.append("Reduce nesting by using early returns or refactoring")
            score -= 0.15
        }
        
        return CodeQualityScore(
            metric: .complexity,
            score: max(0.0, score),
            issues: issues,
            suggestions: suggestions
        )
    }
    
    // MARK: - Testability Analysis
    
    private static func analyzeTestability(_ content: String, fileType: ContextAwareness.FileType) -> CodeQualityScore {
        var issues: [CodeIssue] = []
        var suggestions: [String] = []
        var score = 1.0
        
        // Check for test files
        let isTestFile = content.lowercased().contains("test") || 
                         content.lowercased().contains("spec") ||
                         content.lowercased().contains("xctestcase")
        
        if isTestFile {
            // Analyze test quality
            let testPatterns = ["func test", "func test", "it(", "describe(", "context("]
            var testCount = 0
            for pattern in testPatterns {
                testCount += content.components(separatedBy: pattern).count - 1
            }
            
            if testCount == 0 {
                issues.append(CodeIssue(
                    severity: .medium,
                    message: "No test functions found in test file",
                    line: nil,
                    column: nil
                ))
                score -= 0.2
            }
        } else {
            // Check for dependency injection
            let hasDependencyInjection = content.contains("init(") || 
                                        content.contains("constructor") ||
                                        content.contains("@Inject")
            
            if !hasDependencyInjection {
                suggestions.append("Consider using dependency injection for better testability")
                score -= 0.1
            }
        }
        
        return CodeQualityScore(
            metric: .testability,
            score: max(0.0, score),
            issues: issues,
            suggestions: suggestions
        )
    }
    
    // MARK: - Documentation Analysis
    
    private static func analyzeDocumentation(_ content: String, fileType: ContextAwareness.FileType) -> CodeQualityScore {
        var issues: [CodeIssue] = []
        var suggestions: [String] = []
        var score = 1.0
        
        // Check for comments
        let commentPatterns = getCommentPatterns(for: fileType)
        var commentCount = 0
        for pattern in commentPatterns {
            commentCount += content.components(separatedBy: pattern).count - 1
        }
        
        let lines = content.components(separatedBy: .newlines)
        let commentDensity = Double(commentCount) / Double(max(lines.count, 1))
        
        if commentDensity < 0.1 {
            issues.append(CodeIssue(
                severity: .medium,
                message: "Low comment density - consider adding more documentation",
                line: nil,
                column: nil
            ))
            suggestions.append("Add comments to explain complex logic")
            score -= 0.15
        }
        
        // Check for TODO/FIXME comments
        let todoCount = content.components(separatedBy: "TODO").count - 1
        let fixmeCount = content.components(separatedBy: "FIXME").count - 1
        
        if todoCount > 5 || fixmeCount > 3 {
            issues.append(CodeIssue(
                severity: .low,
                message: "Many TODO/FIXME comments found (\(todoCount) TODO, \(fixmeCount) FIXME)",
                line: nil,
                column: nil
            ))
            suggestions.append("Address TODO/FIXME comments before production")
            score -= 0.05
        }
        
        return CodeQualityScore(
            metric: .documentation,
            score: max(0.0, score),
            issues: issues,
            suggestions: suggestions
        )
    }
    
    // MARK: - Helper Methods
    
    private struct FunctionInfo {
        let name: String
        let startLine: Int
        let body: String
    }
    
    private static func getFunctionPatterns(for fileType: ContextAwareness.FileType) -> [String] {
        switch fileType {
        case .swift:
            return ["func ", "private func ", "public func ", "internal func "]
        case .javascript, .typescript:
            return ["function ", "const ", "let ", "var ", "=>"]
        case .python:
            return ["def "]
        case .rust:
            return ["fn ", "pub fn "]
        case .go:
            return ["func "]
        case .java, .kotlin:
            return ["public ", "private ", "protected "]
        default:
            return ["function ", "func ", "def "]
        }
    }
    
    private static func getCommentPatterns(for fileType: ContextAwareness.FileType) -> [String] {
        switch fileType {
        case .swift, .javascript, .typescript, .java, .kotlin, .c, .cpp, .go, .rust:
            return ["//", "/*"]
        case .python, .ruby:
            return ["#"]
        case .html:
            return ["<!--"]
        default:
            return ["//", "#", "/*"]
        }
    }
    
    private static func findFunctions(in content: String, pattern: String) -> [FunctionInfo] {
        // Simplified function detection
        var functions: [FunctionInfo] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentFunction: (name: String, startLine: Int)?
        var braceCount = 0
        var functionBody = ""
        
        for (index, line) in lines.enumerated() {
            if line.contains(pattern) && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                // Found function declaration
                let name = extractFunctionName(from: line, pattern: pattern)
                currentFunction = (name: name, startLine: index + 1)
                functionBody = line
                braceCount = line.components(separatedBy: "{").count - line.components(separatedBy: "}").count
            } else if let current = currentFunction {
                functionBody += "\n" + line
                braceCount += line.components(separatedBy: "{").count - line.components(separatedBy: "}").count
                
                if braceCount <= 0 {
                    functions.append(FunctionInfo(
                        name: current.name,
                        startLine: current.startLine,
                        body: functionBody
                    ))
                    currentFunction = nil
                    functionBody = ""
                }
            }
        }
        
        return functions
    }
    
    private static func extractFunctionName(from line: String, pattern: String) -> String {
        // Simplified name extraction
        let components = line.components(separatedBy: pattern)
        guard components.count > 1 else { return "unknown" }
        
        let afterPattern = components[1].trimmingCharacters(in: .whitespaces)
        let nameComponents = afterPattern.components(separatedBy: "(")
        
        return nameComponents.first?.trimmingCharacters(in: .whitespaces) ?? "unknown"
    }
    
    private static func findDuplicatePatterns(in content: String) -> [String] {
        // Simplified duplicate detection
        let lines = content.components(separatedBy: .newlines)
        var duplicates: [String] = []
        
        // Look for repeated patterns of 3+ lines
        for i in 0..<lines.count - 3 {
            let pattern = lines[i...i+2].joined(separator: "\n")
            for j in i+3..<lines.count - 3 {
                let candidate = lines[j...j+2].joined(separator: "\n")
                if pattern == candidate && !duplicates.contains(pattern) {
                    duplicates.append(pattern)
                }
            }
        }
        
        return duplicates
    }
    
    private static func findMagicNumbers(in content: String) -> [String] {
        // Simplified magic number detection
        var magicNumbers: [String] = []
        let pattern = try! NSRegularExpression(pattern: "\\b\\d{2,}\\b")
        let range = NSRange(content.startIndex..., in: content)
        
        let matches = pattern.matches(in: content, range: range)
        for match in matches {
            if let range = Range(match.range, in: content) {
                let number = String(content[range])
                // Skip common numbers like 100, 1000, etc.
                if !["10", "12", "24", "60", "100", "1000", "1024"].contains(number) {
                    magicNumbers.append(number)
                }
            }
        }
        
        return magicNumbers
    }
    
    // MARK: - Code Suggestions
    
    /// Generate code improvement suggestions based on analysis
    static func generateSuggestions(for scores: [CodeQualityScore]) -> [String] {
        var suggestions: [String] = []
        
        for score in scores {
            if score.score < 0.7 {
                suggestions.append(contentsOf: score.suggestions)
                
                for issue in score.issues {
                    if issue.severity == .high || issue.severity == .critical {
                        suggestions.append(issue.message)
                    }
                }
            }
        }
        
        return suggestions
    }
    
    /// Format analysis results for display
    static func formatAnalysisResults(_ scores: [CodeQualityScore]) -> String {
        var result = "## Code Quality Analysis\n\n"
        
        for score in scores {
            let scorePercentage = Int(score.score * 100)
            let emoji: String
            switch score.score {
            case 0.8...1.0:
                emoji = "✅"
            case 0.6..<0.8:
                emoji = "⚠️"
            default:
                emoji = "❌"
            }
            
            result += "\(emoji) \(score.metric): \(scorePercentage)%\n"
            
            if !score.issues.isEmpty {
                for issue in score.issues {
                    result += "  - \(issue.severity): \(issue.message)\n"
                }
            }
            
            if !score.suggestions.isEmpty {
                result += "  Suggestions:\n"
                for suggestion in score.suggestions {
                    result += "    • \(suggestion)\n"
                }
            }
            
            result += "\n"
        }
        
        return result
    }
}
