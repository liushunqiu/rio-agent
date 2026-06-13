import Foundation

/// 智能重构建议系统 - 检测代码异味，提供重构建议
class RefactoringAdvisor {
    
    // MARK: - 代码异味类型
    
    enum CodeSmellType {
        case longFunction        // 函数过长
        case longParameterList   // 参数过多
        case duplicateCode       // 重复代码
        case magicNumbers        // 魔法数字
        case deepNesting         // 嵌套过深
        case godClass            // 上帝类（职责过多）
        case featureEnvy         // 功能嫉妒（过多使用其他类的数据）
        case dataClump           // 数据泥团（多个参数总是一起出现）
        case deadCode            // 死代码
        case complexCondition    // 复杂条件表达式
        
        var description: String {
            switch self {
            case .longFunction: return "函数过长"
            case .longParameterList: return "参数过多"
            case .duplicateCode: return "重复代码"
            case .magicNumbers: return "魔法数字"
            case .deepNesting: return "嵌套过深"
            case .godClass: return "上帝类（职责过多）"
            case .featureEnvy: return "功能嫉妒"
            case .dataClump: return "数据泥团"
            case .deadCode: return "死代码"
            case .complexCondition: return "复杂条件表达式"
            }
        }
    }
    
    struct CodeSmell {
        let type: CodeSmellType
        let filePath: String
        let lineNumber: Int
        let description: String
        let severity: Severity
        let suggestion: String
        
        enum Severity {
            case low
            case medium
            case high
            case critical
        }
    }
    
    struct RefactoringSuggestion {
        let smell: CodeSmell
        let refactoringType: String
        let steps: [String]
        let example: String?
        let estimatedEffort: String
    }
    
    // MARK: - 代码异味检测
    
    /// 分析文件，检测代码异味
    static func analyzeFile(_ filePath: String, content: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        // 检测长函数
        smells.append(contentsOf: detectLongFunctions(in: lines, filePath: filePath))
        
        // 检测魔法数字
        smells.append(contentsOf: detectMagicNumbers(in: lines, filePath: filePath))
        
        // 检测深嵌套
        smells.append(contentsOf: detectDeepNesting(in: lines, filePath: filePath))
        
        // 检测重复代码
        smells.append(contentsOf: detectDuplicateCode(in: lines, filePath: filePath))
        
        // 检测复杂条件
        smells.append(contentsOf: detectComplexConditions(in: lines, filePath: filePath))
        
        // 检测死代码
        smells.append(contentsOf: detectDeadCode(in: lines, filePath: filePath))
        
        return smells
    }
    
    // MARK: - 长函数检测
    
    private static func detectLongFunctions(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        var currentFunction: (name: String, startLine: Int)?
        var braceCount = 0
        var functionLength = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 检测函数开始
            if isFunctionDefinition(trimmed) {
                let name = extractFunctionName(from: trimmed)
                currentFunction = (name: name, startLine: index + 1)
                braceCount = 0
                functionLength = 0
            }
            
            // 计算大括号
            if currentFunction != nil {
                braceCount += trimmed.components(separatedBy: "{").count - 1
                braceCount -= trimmed.components(separatedBy: "}").count - 1
                functionLength += 1
                
                // 函数结束
                if braceCount <= 0 && functionLength > 1 {
                    let maxLength = 50
                    if functionLength > maxLength {
                        smells.append(CodeSmell(
                            type: .longFunction,
                            filePath: filePath,
                            lineNumber: currentFunction!.startLine,
                            description: "函数 '\(currentFunction!.name)' 有 \(functionLength) 行，超过建议的 \(maxLength) 行",
                            severity: functionLength > 100 ? .high : .medium,
                            suggestion: "考虑将此函数拆分为更小的子函数"
                        ))
                    }
                    currentFunction = nil
                }
            }
        }
        
        return smells
    }
    
    // MARK: - 魔法数字检测
    
    private static func detectMagicNumbers(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        let magicNumberPattern = try! NSRegularExpression(pattern: "\\b\\d{2,}\\b")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过注释和常量定义
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }
            
            // 跳过常量定义
            if trimmed.contains("let ") || trimmed.contains("var ") || 
               trimmed.contains("const ") || trimmed.contains("static ") {
                continue
            }
            
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = magicNumberPattern.matches(in: trimmed, range: range)
            
            for match in matches {
                if let matchRange = Range(match.range, in: trimmed) {
                    let number = String(trimmed[matchRange])
                    
                    // 跳过常见数字
                    let commonNumbers = ["10", "12", "24", "60", "100", "1000", "1024", "0", "1", "2"]
                    if !commonNumbers.contains(number) {
                        smells.append(CodeSmell(
                            type: .magicNumbers,
                            filePath: filePath,
                            lineNumber: index + 1,
                            description: "发现魔法数字: \(number)",
                            severity: .low,
                            suggestion: "将数字定义为命名常量，提高代码可读性"
                        ))
                    }
                }
            }
        }
        
        return smells
    }
    
    // MARK: - 深嵌套检测
    
    private static func detectDeepNesting(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        var currentDepth = 0
        var maxDepth = 0
        var maxDepthLine = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 计算嵌套深度
            for char in trimmed {
                if char == "{" {
                    currentDepth += 1
                    if currentDepth > maxDepth {
                        maxDepth = currentDepth
                        maxDepthLine = index + 1
                    }
                } else if char == "}" {
                    currentDepth = max(0, currentDepth - 1)
                }
            }
        }
        
        let maxAllowedDepth = 4
        if maxDepth > maxAllowedDepth {
            smells.append(CodeSmell(
                type: .deepNesting,
                filePath: filePath,
                lineNumber: maxDepthLine,
                description: "最大嵌套深度为 \(maxDepth) 层，超过建议的 \(maxAllowedDepth) 层",
                severity: maxDepth > 6 ? .high : .medium,
                suggestion: "考虑使用提前返回、提取子函数或策略模式来减少嵌套"
            ))
        }
        
        return smells
    }
    
    // MARK: - 重复代码检测
    
    private static func detectDuplicateCode(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        
        // 简化实现：检测连续3行以上的重复
        let minDuplicateLines = 3
        
        for i in 0..<lines.count - minDuplicateLines {
            let pattern = lines[i..<i + minDuplicateLines].joined(separator: "\n")
            
            for j in i + minDuplicateLines..<lines.count - minDuplicateLines {
                let candidate = lines[j..<j + minDuplicateLines].joined(separator: "\n")
                
                if pattern == candidate {
                    smells.append(CodeSmell(
                        type: .duplicateCode,
                        filePath: filePath,
                        lineNumber: i + 1,
                        description: "发现重复代码（行 \(i + 1) 和 \(j + 1)）",
                        severity: .medium,
                        suggestion: "将重复代码提取为独立函数"
                    ))
                    break
                }
            }
        }
        
        return smells
    }
    
    // MARK: - 复杂条件检测
    
    private static func detectComplexConditions(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 检测 if/while/guard 语句中的复杂条件
            if trimmed.hasPrefix("if ") || trimmed.hasPrefix("while ") || trimmed.hasPrefix("guard ") {
                // 计算逻辑运算符数量
                let andCount = trimmed.components(separatedBy: "&&").count - 1
                let orCount = trimmed.components(separatedBy: "||").count - 1
                let totalOperators = andCount + orCount
                
                if totalOperators >= 3 {
                    smells.append(CodeSmell(
                        type: .complexCondition,
                        filePath: filePath,
                        lineNumber: index + 1,
                        description: "条件表达式包含 \(totalOperators) 个逻辑运算符",
                        severity: totalOperators >= 5 ? .high : .medium,
                        suggestion: "考虑将复杂条件提取为命名布尔变量或函数"
                    ))
                }
            }
        }
        
        return smells
    }
    
    // MARK: - 死代码检测
    
    private static func detectDeadCode(in lines: [String], filePath: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        
        // 检测注释掉的代码块
        var commentBlockStart: Int?
        var commentBlockLines: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("//") {
                if commentBlockStart == nil {
                    commentBlockStart = index
                    commentBlockLines = []
                }
                commentBlockLines.append(trimmed)
            } else {
                if let start = commentBlockStart, commentBlockLines.count >= 3 {
                    // 检查是否看起来像代码而不是注释
                    let looksLikeCode = commentBlockLines.contains { line in
                        line.contains("func ") || line.contains("class ") || 
                        line.contains("var ") || line.contains("let ") ||
                        line.contains("if ") || line.contains("for ")
                    }
                    
                    if looksLikeCode {
                        smells.append(CodeSmell(
                            type: .deadCode,
                            filePath: filePath,
                            lineNumber: start + 1,
                            description: "发现 \(commentBlockLines.count) 行被注释掉的代码",
                            severity: .low,
                            suggestion: "删除被注释掉的代码，使用版本控制来保留历史"
                        ))
                    }
                }
                commentBlockStart = nil
                commentBlockLines = []
            }
        }
        
        return smells
    }
    
    // MARK: - 重构建议生成
    
    /// 生成重构建议
    static func generateSuggestions(for smells: [CodeSmell]) -> [RefactoringSuggestion] {
        var suggestions: [RefactoringSuggestion] = []
        
        for smell in smells {
            let suggestion = generateSuggestion(for: smell)
            suggestions.append(suggestion)
        }
        
        return suggestions
    }
    
    /// 为单个代码异味生成重构建议
    private static func generateSuggestion(for smell: CodeSmell) -> RefactoringSuggestion {
        switch smell.type {
        case .longFunction:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "提取函数",
                steps: [
                    "1. 识别函数中的逻辑块",
                    "2. 将每个逻辑块提取为独立的私有函数",
                    "3. 用函数调用替换原代码",
                    "4. 确保提取的函数有清晰的命名"
                ],
                example: """
                // 重构前
                func processData() {
                    // 100行代码...
                }
                
                // 重构后
                func processData() {
                    validateInput()
                    let result = transformData()
                    saveResult(result)
                }
                """,
                estimatedEffort: "中等"
            )
            
        case .magicNumbers:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "提取常量",
                steps: [
                    "1. 识别魔法数字",
                    "2. 创建命名常量",
                    "3. 用常量替换数字"
                ],
                example: """
                // 重构前
                if age > 18 { ... }
                
                // 重构后
                let legalAge = 18
                if age > legalAge { ... }
                """,
                estimatedEffort: "简单"
            )
            
        case .deepNesting:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "提前返回",
                steps: [
                    "1. 识别嵌套的条件",
                    "2. 将否定条件提前返回",
                    "3. 减少嵌套层级"
                ],
                example: """
                // 重构前
                if condition1 {
                    if condition2 {
                        if condition3 {
                            // 业务逻辑
                        }
                    }
                }
                
                // 重构后
                guard condition1 else { return }
                guard condition2 else { return }
                guard condition3 else { return }
                // 业务逻辑
                """,
                estimatedEffort: "简单"
            )
            
        case .duplicateCode:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "提取函数",
                steps: [
                    "1. 识别重复的代码块",
                    "2. 提取为独立函数",
                    "3. 用函数调用替换重复代码",
                    "4. 处理可能的参数差异"
                ],
                example: """
                // 重构前
                // 重复代码块1
                let a = x + 1
                let b = a * 2
                print(b)
                
                // 重复代码块2
                let c = y + 1
                let d = c * 2
                print(d)
                
                // 重构后
                func processAndPrint(_ value: Int) {
                    let result = (value + 1) * 2
                    print(result)
                }
                processAndPrint(x)
                processAndPrint(y)
                """,
                estimatedEffort: "中等"
            )
            
        case .complexCondition:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "提取布尔变量/函数",
                steps: [
                    "1. 识别复杂条件",
                    "2. 将条件提取为命名变量或函数",
                    "3. 用变量/函数替换原条件"
                ],
                example: """
                // 重构前
                if age >= 18 && hasLicense && !isSuspended && insuranceValid { ... }
                
                // 重构后
                let isEligibleToDrive = age >= 18 && hasLicense && !isSuspended && insuranceValid
                if isEligibleToDrive { ... }
                """,
                estimatedEffort: "简单"
            )
            
        case .deadCode:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "删除死代码",
                steps: [
                    "1. 确认代码确实不再使用",
                    "2. 删除被注释掉的代码",
                    "3. 使用版本控制保留历史"
                ],
                example: nil,
                estimatedEffort: "简单"
            )
            
        default:
            return RefactoringSuggestion(
                smell: smell,
                refactoringType: "重构",
                steps: ["分析代码结构", "识别问题", "应用适当的重构模式"],
                example: nil,
                estimatedEffort: "中等"
            )
        }
    }
    
    // MARK: - 辅助方法
    
    private static func isFunctionDefinition(_ line: String) -> Bool {
        let keywords = ["func ", "private func ", "public func ", "internal func ",
                       "fileprivate func ", "static func ", "class func ",
                       "function ", "async function ", "def "]
        return keywords.contains { line.hasPrefix($0) }
    }
    
    private static func extractFunctionName(from line: String) -> String {
        var name = line
        let keywords = ["func ", "private func ", "public func ", "internal func ",
                       "fileprivate func ", "static func ", "class func ",
                       "function ", "async function ", "def "]
        
        for keyword in keywords {
            if name.hasPrefix(keyword) {
                name = String(name.dropFirst(keyword.count))
                break
            }
        }
        
        if let parenIndex = name.firstIndex(of: "(") {
            name = String(name[..<parenIndex])
        }
        
        return name.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - 格式化输出
    
    /// 格式化分析结果
    static func formatAnalysisResults(_ smells: [CodeSmell], suggestions: [RefactoringSuggestion]) -> String {
        var result = "## 代码质量分析\n\n"
        
        if smells.isEmpty {
            result += "✅ 未发现明显的代码异味\n"
            return result
        }
        
        // 按严重程度分组
        let grouped = Dictionary(grouping: smells, by: { $0.severity })
        let severityOrder: [CodeSmell.Severity] = [.critical, .high, .medium, .low]
        
        for severity in severityOrder {
            if let severitySmells = grouped[severity], !severitySmells.isEmpty {
                let emoji: String
                switch severity {
                case .critical: emoji = "🔴"
                case .high: emoji = "🟠"
                case .medium: emoji = "🟡"
                case .low: emoji = "🟢"
                }
                
                result += "### \(emoji) \(severityName(severity))\n\n"
                
                for smell in severitySmells {
                    result += "**\(smell.type.description)** (行 \(smell.lineNumber))\n"
                    result += "\(smell.description)\n"
                    result += "💡 建议: \(smell.suggestion)\n\n"
                }
            }
        }
        
        // 显示重构建议
        if !suggestions.isEmpty {
            result += "## 重构建议\n\n"
            
            for suggestion in suggestions {
                result += "### \(suggestion.refactoringType)\n"
                result += "位置: \(suggestion.smell.filePath):\(suggestion.smell.lineNumber)\n"
                result += "工作量: \(suggestion.estimatedEffort)\n\n"
                
                result += "步骤:\n"
                for step in suggestion.steps {
                    result += "\(step)\n"
                }
                
                if let example = suggestion.example {
                    result += "\n示例:\n```swift\n\(example)\n```\n"
                }
                
                result += "\n"
            }
        }
        
        return result
    }
    
    private static func severityName(_ severity: CodeSmell.Severity) -> String {
        switch severity {
        case .critical: return "严重"
        case .high: return "高"
        case .medium: return "中等"
        case .low: return "低"
        }
    }
}
