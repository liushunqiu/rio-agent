import Foundation

/// 多文件协调系统 - 理解文件关系，协调多文件修改
class MultiFileCoordinator {
    private let skippedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".next",
        ".nuxt",
        ".swiftpm",
        ".venv",
        "__pycache__",
        "DerivedData",
        "dist",
        "node_modules",
        "venv"
    ]
    
    // MARK: - 文件关系类型
    
    enum FileRelationType {
        case imports         // 导入关系
        case inherits        // 继承关系
        case implements      // 实现关系
        case references      // 引用关系
        case tests           // 测试关系
        case configures      // 配置关系
        case generates       // 生成关系
    }
    
    struct FileRelation {
        let sourceFile: String
        let targetFile: String
        let relationType: FileRelationType
        let strength: Double  // 0.0 - 1.0
    }
    
    struct FileChange {
        let filePath: String
        let changeType: ChangeType
        let description: String
        let lineRange: Range<Int>?
        
        enum ChangeType {
            case add
            case modify
            case delete
            case rename
        }
    }
    
    struct CoordinatedChange {
        let primaryChange: FileChange
        let relatedChanges: [FileChange]
        let order: [String]  // 执行顺序
        let warnings: [String]
    }
    
    // MARK: - 文件关系图
    
    private var relationGraph: [String: [FileRelation]] = [:]
    private var fileCache: [String: FileAnalysis] = [:]
    
    struct FileAnalysis {
        let filePath: String
        let imports: [String]
        let exports: [String]
        let classes: [String]
        let functions: [String]
        let references: [String]
        let lastAnalyzed: Date
    }
    
    // MARK: - 文件分析
    
    /// 分析文件关系
    func analyzeFileRelations(in projectPath: String) {
        let fileManager = FileManager.default
        relationGraph.removeAll(keepingCapacity: true)
        fileCache.removeAll(keepingCapacity: true)
        guard let enumerator = fileManager.enumerator(atPath: projectPath) else { return }
        
        // 收集所有代码文件
        var codeFiles: [String] = []
        while let file = enumerator.nextObject() as? String {
            let pathComponents = file.split(separator: "/")
            if let directoryName = pathComponents.last, skippedDirectoryNames.contains(String(directoryName)) {
                enumerator.skipDescendants()
                continue
            }
            if pathComponents.contains(where: { skippedDirectoryNames.contains(String($0)) }) {
                continue
            }
            let ext = (file as NSString).pathExtension.lowercased()
            let codeExtensions = ["swift", "js", "ts", "jsx", "tsx", "py", "rs", "go", "java", "kt"]
            if codeExtensions.contains(ext) {
                codeFiles.append(file)
            }
        }
        
        // 分析每个文件
        for file in codeFiles {
            let fullPath = (projectPath as NSString).appendingPathComponent(file)
            if let content = readFile(at: fullPath) {
                let analysis = analyzeFile(file, content: content)
                fileCache[file] = analysis
                
                // 建立关系
                buildRelations(for: file, analysis: analysis, in: projectPath)
            }
        }
    }
    
    /// 分析单个文件
    private func analyzeFile(_ filePath: String, content: String) -> FileAnalysis {
        let lines = content.components(separatedBy: .newlines)
        
        var imports: [String] = []
        var exports: [String] = []
        var classes: [String] = []
        var functions: [String] = []
        var references: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 解析导入
            if trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ") {
                imports.append(trimmed)
            }
            
            // 解析导出
            if trimmed.hasPrefix("export ") || trimmed.hasPrefix("public ") {
                exports.append(trimmed)
            }
            
            // 解析类定义
            if trimmed.contains("class ") || trimmed.contains("struct ") || 
               trimmed.contains("interface ") || trimmed.contains("protocol ") {
                if let name = extractTypeName(from: trimmed) {
                    classes.append(name)
                }
            }
            
            // 解析函数定义
            if trimmed.hasPrefix("func ") || trimmed.hasPrefix("function ") || 
               trimmed.hasPrefix("def ") || trimmed.hasPrefix("async func ") {
                if let name = extractFunctionName(from: trimmed) {
                    functions.append(name)
                }
            }
            
            // 解析引用（简化实现）
            let referencePatterns = ["self.", "this.", "super.", "Self."]
            for pattern in referencePatterns {
                if trimmed.contains(pattern) {
                    references.append(pattern)
                    break
                }
            }
        }
        
        return FileAnalysis(
            filePath: filePath,
            imports: imports,
            exports: exports,
            classes: classes,
            functions: functions,
            references: references,
            lastAnalyzed: Date()
        )
    }
    
    /// 建立文件关系
    private func buildRelations(for file: String, analysis: FileAnalysis, in projectPath: String) {
        var relations: [FileRelation] = []
        
        // 基于导入建立关系
        for importStatement in analysis.imports {
            if let targetFile = resolveImport(importStatement, from: file, in: projectPath) {
                relations.append(FileRelation(
                    sourceFile: file,
                    targetFile: targetFile,
                    relationType: .imports,
                    strength: 0.8
                ))
            }
        }
        
        // 基于类名建立关系
        for className in analysis.classes {
            // 查找可能的测试文件
            let testFile = findTestFile(for: file, className: className, in: projectPath)
            if let testFile = testFile {
                relations.append(FileRelation(
                    sourceFile: file,
                    targetFile: testFile,
                    relationType: .tests,
                    strength: 0.6
                ))
            }
        }
        
        relationGraph[file] = relations
    }
    
    // MARK: - 协调修改
    
    /// 协调多文件修改
    func coordinateChanges(_ changes: [FileChange], in projectPath: String) -> CoordinatedChange {
        guard let primaryChange = changes.first else {
            return CoordinatedChange(
                primaryChange: FileChange(filePath: "", changeType: .modify, description: "", lineRange: nil),
                relatedChanges: [],
                order: [],
                warnings: ["No changes provided"]
            )
        }
        
        var relatedChanges: [FileChange] = []
        var warnings: [String] = []
        var executionOrder: [String] = []
        
        // 分析主变更的影响
        let impactedFiles = findImpactedFiles(for: primaryChange.filePath, in: projectPath)
        
        // 检查是否需要更新相关文件
        for impactedFile in impactedFiles {
            if let relation = getRelation(from: primaryChange.filePath, to: impactedFile) {
                switch relation.relationType {
                case .imports:
                    // 如果修改了导出，需要更新导入的文件
                    if primaryChange.changeType == .modify || primaryChange.changeType == .delete {
                        relatedChanges.append(FileChange(
                            filePath: impactedFile,
                            changeType: .modify,
                            description: "Update import from \(primaryChange.filePath)",
                            lineRange: nil
                        ))
                        warnings.append("⚠️ \(impactedFile) imports \(primaryChange.filePath) - may need update")
                    }
                    
                case .tests:
                    // 如果修改了代码，可能需要更新测试
                    relatedChanges.append(FileChange(
                        filePath: impactedFile,
                        changeType: .modify,
                        description: "Update tests for \(primaryChange.filePath)",
                        lineRange: nil
                    ))
                    warnings.append("⚠️ \(impactedFile) tests \(primaryChange.filePath) - verify tests still pass")
                    
                case .configures:
                    // 配置文件可能需要更新
                    warnings.append("ℹ️ \(impactedFile) configures \(primaryChange.filePath) - check configuration")
                    
                default:
                    break
                }
            }
        }
        
        // 确定执行顺序
        executionOrder = determineExecutionOrder(primaryChange: primaryChange, relatedChanges: relatedChanges)
        
        return CoordinatedChange(
            primaryChange: primaryChange,
            relatedChanges: relatedChanges,
            order: executionOrder,
            warnings: warnings
        )
    }
    
    /// 查找受影响的文件
    func findImpactedFiles(for filePath: String, in projectPath: String) -> [String] {
        var impactedFiles: [String] = []
        
        // 查找直接关系
        if let directRelations = relationGraph[filePath] {
            for relation in directRelations {
                impactedFiles.append(relation.targetFile)
            }
        }
        
        // 查找反向关系（谁导入了这个文件）
        for (source, relations) in relationGraph {
            for relation in relations where relation.targetFile == filePath {
                if !impactedFiles.contains(source) {
                    impactedFiles.append(source)
                }
            }
        }
        
        return impactedFiles
    }
    
    /// 获取两个文件之间的关系
    func getRelation(from source: String, to target: String) -> FileRelation? {
        return relationGraph[source]?.first { $0.targetFile == target }
    }
    
    /// 确定执行顺序
    private func determineExecutionOrder(primaryChange: FileChange, relatedChanges: [FileChange]) -> [String] {
        var order: [String] = []
        
        // 主变更优先
        order.append(primaryChange.filePath)
        
        // 按关系强度排序相关变更
        let sortedRelated = relatedChanges.sorted { change1, change2 in
            let strength1 = getRelation(from: primaryChange.filePath, to: change1.filePath)?.strength ?? 0
            let strength2 = getRelation(from: primaryChange.filePath, to: change2.filePath)?.strength ?? 0
            return strength1 > strength2
        }
        
        for change in sortedRelated {
            if !order.contains(change.filePath) {
                order.append(change.filePath)
            }
        }
        
        return order
    }
    
    // MARK: - 重构支持
    
    /// 分析重命名影响
    func analyzeRenameImpact(oldName: String, newName: String, in projectPath: String) -> [FileChange] {
        var changes: [FileChange] = []
        
        // 搜索所有引用
        for (file, _) in fileCache {
            let fullPath = (projectPath as NSString).appendingPathComponent(file)
            if let content = readFile(at: fullPath) {
                let lines = content.components(separatedBy: .newlines)
                
                for (index, line) in lines.enumerated() {
                    if line.contains(oldName) {
                        changes.append(FileChange(
                            filePath: file,
                            changeType: .modify,
                            description: "Rename \(oldName) to \(newName) at line \(index + 1)",
                            lineRange: index..<(index + 1)
                        ))
                    }
                }
            }
        }
        
        return changes
    }
    
    /// 分析删除影响
    func analyzeDeleteImpact(filePath: String, in projectPath: String) -> [String] {
        var warnings: [String] = []
        
        let impactedFiles = findImpactedFiles(for: filePath, in: projectPath)
        
        for impactedFile in impactedFiles {
            if let relation = getRelation(from: impactedFile, to: filePath) {
                switch relation.relationType {
                case .imports:
                    warnings.append("⚠️ \(impactedFile) imports \(filePath) - will break")
                case .tests:
                    warnings.append("⚠️ \(impactedFile) tests \(filePath) - tests will fail")
                case .references:
                    warnings.append("⚠️ \(impactedFile) references \(filePath) - will cause errors")
                default:
                    warnings.append("ℹ️ \(impactedFile) is related to \(filePath)")
                }
            }
        }
        
        return warnings
    }
    
    // MARK: - 辅助方法
    
    private func resolveImport(_ importStatement: String, from file: String, in projectPath: String) -> String? {
        // 简化实现：基于文件扩展名猜测
        let ext = (file as NSString).pathExtension
        
        if importStatement.hasPrefix("import ") {
            let moduleName = String(importStatement.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let possiblePath = "\(moduleName).\(ext)"
            return possiblePath
        }
        
        return nil
    }
    
    private func findTestFile(for file: String, className: String, in projectPath: String) -> String? {
        let testPatterns = ["Test", "Spec", "_test", "_spec"]
        let baseName = (file as NSString).deletingPathExtension
        
        for pattern in testPatterns {
            let testFile = "\(baseName)\(pattern).\((file as NSString).pathExtension)"
            let fullPath = (projectPath as NSString).appendingPathComponent(testFile)
            if FileManager.default.fileExists(atPath: fullPath) {
                return testFile
            }
        }
        
        return nil
    }
    
    private func extractTypeName(from line: String) -> String? {
        let keywords = ["class ", "struct ", "interface ", "protocol "]
        for keyword in keywords {
            if let range = line.range(of: keyword) {
                let afterKeyword = line[range.upperBound...]
                let name = afterKeyword.components(separatedBy: CharacterSet.alphanumerics.inverted).first
                return name
            }
        }
        return nil
    }
    
    private func extractFunctionName(from line: String) -> String? {
        let keywords = ["func ", "function ", "def ", "async func "]
        for keyword in keywords {
            if let range = line.range(of: keyword) {
                let afterKeyword = line[range.upperBound...]
                let name = afterKeyword.components(separatedBy: "(").first?
                    .trimmingCharacters(in: .whitespaces)
                return name
            }
        }
        return nil
    }
    
    private func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - 报告生成
    
    /// 生成文件关系报告
    func generateRelationReport(for filePath: String) -> String {
        var report = "## 文件关系分析: \(filePath)\n\n"
        
        guard let relations = relationGraph[filePath], !relations.isEmpty else {
            report += "未发现文件关系\n"
            return report
        }
        
        // 按关系类型分组
        let grouped = Dictionary(grouping: relations, by: { $0.relationType })
        
        let typeNames: [FileRelationType: String] = [
            .imports: "导入关系",
            .inherits: "继承关系",
            .implements: "实现关系",
            .references: "引用关系",
            .tests: "测试关系",
            .configures: "配置关系",
            .generates: "生成关系"
        ]
        
        for (type, typeRelations) in grouped {
            let typeName = typeNames[type] ?? "未知关系"
            report += "### \(typeName)\n"
            for relation in typeRelations {
                let strength = Int(relation.strength * 100)
                report += "- \(relation.targetFile) (强度: \(strength)%)\n"
            }
            report += "\n"
        }
        
        // 反向关系
        var reverseRelations: [FileRelation] = []
        for (source, relations) in relationGraph {
            for relation in relations where relation.targetFile == filePath {
                reverseRelations.append(FileRelation(
                    sourceFile: source,
                    targetFile: filePath,
                    relationType: relation.relationType,
                    strength: relation.strength
                ))
            }
        }
        
        if !reverseRelations.isEmpty {
            report += "### 被引用\n"
            for relation in reverseRelations {
                report += "- \(relation.sourceFile)\n"
            }
        }
        
        return report
    }
    
    /// 生成协调变更报告
    func generateChangeReport(_ coordinatedChange: CoordinatedChange) -> String {
        var report = "## 协调变更计划\n\n"
        
        report += "### 主要变更\n"
        report += "- 文件: \(coordinatedChange.primaryChange.filePath)\n"
        report += "- 类型: \(coordinatedChange.primaryChange.changeType)\n"
        report += "- 描述: \(coordinatedChange.primaryChange.description)\n\n"
        
        if !coordinatedChange.relatedChanges.isEmpty {
            report += "### 相关变更\n"
            for change in coordinatedChange.relatedChanges {
                report += "- \(change.filePath): \(change.description)\n"
            }
            report += "\n"
        }
        
        if !coordinatedChange.warnings.isEmpty {
            report += "### 警告\n"
            for warning in coordinatedChange.warnings {
                report += "- \(warning)\n"
            }
            report += "\n"
        }
        
        report += "### 执行顺序\n"
        for (index, file) in coordinatedChange.order.enumerated() {
            report += "\(index + 1). \(file)\n"
        }
        
        return report
    }
}
