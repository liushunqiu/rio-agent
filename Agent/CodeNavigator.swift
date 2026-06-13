import Foundation

/// 智能代码导航系统 - 提供代码结构分析、跳转定义、查找引用等功能
class CodeNavigator {
    
    // MARK: - 代码结构类型
    
    enum SymbolKind {
        case function
        case variable
        case `class`
        case `struct`
        case `enum`
        case `protocol`
        case `extension`
        case `import`
        case `typealias`
        case unknown
    }
    
    struct CodeSymbol {
        let name: String
        let kind: SymbolKind
        let filePath: String
        let lineNumber: Int
        let column: Int
        let signature: String?
        let documentation: String?
    }
    
    struct CodeReference {
        let symbol: CodeSymbol
        let filePath: String
        let lineNumber: Int
        let context: String
    }
    
    // MARK: - 代码结构缓存
    
    private static var symbolCache: [String: [CodeSymbol]] = [:]  // filePath -> symbols
    private static var referenceCache: [String: [CodeReference]] = [:]  // symbolName -> references
    private static var fileASTCache: [String: FileAST] = [:]  // filePath -> AST
    
    /// 文件抽象语法树（简化版）
    struct FileAST {
        let filePath: String
        let symbols: [CodeSymbol]
        let imports: [String]
        let dependencies: [String]
        let lines: [String]
    }
    
    // MARK: - 代码解析
    
    /// 解析文件，提取代码符号
    static func parseFile(_ filePath: String, content: String) -> FileAST {
        // 检查缓存
        if let cached = fileASTCache[filePath] {
            return cached
        }
        
        let lines = content.components(separatedBy: .newlines)
        var symbols: [CodeSymbol] = []
        var imports: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 解析导入语句
            if let importName = parseImport(trimmed) {
                imports.append(importName)
            }
            
            // 解析函数定义
            if let symbol = parseFunctionDefinition(trimmed, filePath: filePath, lineNumber: index + 1) {
                symbols.append(symbol)
            }
            
            // 解析类/结构体定义
            if let symbol = parseTypeDefinition(trimmed, filePath: filePath, lineNumber: index + 1) {
                symbols.append(symbol)
            }
            
            // 解析变量定义
            if let symbol = parseVariableDefinition(trimmed, filePath: filePath, lineNumber: index + 1) {
                symbols.append(symbol)
            }
        }
        
        let dependencies = extractDependencies(from: imports)
        
        let ast = FileAST(
            filePath: filePath,
            symbols: symbols,
            imports: imports,
            dependencies: dependencies,
            lines: lines
        )
        
        // 缓存结果
        fileASTCache[filePath] = ast
        symbolCache[filePath] = symbols
        
        return ast
    }
    
    /// 解析导入语句
    private static func parseImport(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Swift: import Foundation
        if trimmed.hasPrefix("import ") {
            let importName = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return importName
        }
        
        // JavaScript/TypeScript: import { x } from 'y' 或 import x from 'y'
        if trimmed.hasPrefix("import ") && (trimmed.contains("from") || trimmed.contains("{")) {
            return trimmed
        }
        
        // Python: import x 或 from x import y
        if trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ") {
            return trimmed
        }
        
        return nil
    }
    
    /// 解析函数定义
    private static func parseFunctionDefinition(_ line: String, filePath: String, lineNumber: Int) -> CodeSymbol? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Swift: func name(...) -> ReturnType
        if trimmed.hasPrefix("func ") || trimmed.hasPrefix("private func ") || 
           trimmed.hasPrefix("public func ") || trimmed.hasPrefix("internal func ") {
            let name = extractFunctionName(from: trimmed)
            return CodeSymbol(
                name: name,
                kind: .function,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        // JavaScript/TypeScript: function name(...) 或 const name = (...) =>
        if trimmed.hasPrefix("function ") || trimmed.hasPrefix("async function ") {
            let name = extractFunctionName(from: trimmed)
            return CodeSymbol(
                name: name,
                kind: .function,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        // Python: def name(...)
        if trimmed.hasPrefix("def ") {
            let name = extractFunctionName(from: trimmed)
            return CodeSymbol(
                name: name,
                kind: .function,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        return nil
    }
    
    /// 解析类型定义（类、结构体、枚举、协议）
    private static func parseTypeDefinition(_ line: String, filePath: String, lineNumber: Int) -> CodeSymbol? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Swift: class/struct/enum/protocol Name
        let typeKeywords = ["class ", "struct ", "enum ", "protocol ", "extension "]
        for keyword in typeKeywords {
            if trimmed.hasPrefix(keyword) {
                let name = extractTypeName(from: trimmed, keyword: keyword)
                let kind: SymbolKind
                if keyword == "class " {
                    kind = .class
                } else if keyword == "struct " {
                    kind = .struct
                } else if keyword == "enum " {
                    kind = .enum
                } else if keyword == "protocol " {
                    kind = .protocol
                } else {
                    kind = .extension
                }
                
                return CodeSymbol(
                    name: name,
                    kind: kind,
                    filePath: filePath,
                    lineNumber: lineNumber,
                    column: 0,
                    signature: trimmed,
                    documentation: nil
                )
            }
        }
        
        // JavaScript/TypeScript: class Name
        if trimmed.hasPrefix("class ") || trimmed.hasPrefix("export class ") {
            let name = extractTypeName(from: trimmed, keyword: "class ")
            return CodeSymbol(
                name: name,
                kind: .class,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        // Python: class Name
        if trimmed.hasPrefix("class ") {
            let name = extractTypeName(from: trimmed, keyword: "class ")
            return CodeSymbol(
                name: name,
                kind: .class,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        return nil
    }
    
    /// 解析变量定义
    private static func parseVariableDefinition(_ line: String, filePath: String, lineNumber: Int) -> CodeSymbol? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Swift: let/var name: Type = value
        if trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ") ||
           trimmed.hasPrefix("private let ") || trimmed.hasPrefix("private var ") ||
           trimmed.hasPrefix("public let ") || trimmed.hasPrefix("public var ") {
            let name = extractVariableName(from: trimmed)
            return CodeSymbol(
                name: name,
                kind: .variable,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        // JavaScript/TypeScript: const/let/var name = value
        if trimmed.hasPrefix("const ") || trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ") {
            let name = extractVariableName(from: trimmed)
            return CodeSymbol(
                name: name,
                kind: .variable,
                filePath: filePath,
                lineNumber: lineNumber,
                column: 0,
                signature: trimmed,
                documentation: nil
            )
        }
        
        return nil
    }
    
    // MARK: - 名称提取辅助方法
    
    private static func extractFunctionName(from line: String) -> String {
        // 去掉关键字
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
        
        // 提取到括号前
        if let parenIndex = name.firstIndex(of: "(") {
            name = String(name[..<parenIndex])
        }
        
        // 去掉空格
        name = name.trimmingCharacters(in: .whitespaces)
        
        return name.isEmpty ? "unknown" : name
    }
    
    private static func extractTypeName(from line: String, keyword: String) -> String {
        var name = line
        if name.hasPrefix(keyword) {
            name = String(name.dropFirst(keyword.count))
        }
        
        // 去掉继承和协议声明
        if let colonIndex = name.firstIndex(of: ":") {
            name = String(name[..<colonIndex])
        }
        if let braceIndex = name.firstIndex(of: "{") {
            name = String(name[..<braceIndex])
        }
        
        // 去掉空格
        name = name.trimmingCharacters(in: .whitespaces)
        
        return name.isEmpty ? "unknown" : name
    }
    
    private static func extractVariableName(from line: String) -> String {
        var name = line
        let keywords = ["let ", "var ", "const ", "private let ", "private var ",
                       "public let ", "public var ", "static let ", "static var "]
        
        for keyword in keywords {
            if name.hasPrefix(keyword) {
                name = String(name.dropFirst(keyword.count))
                break
            }
        }
        
        // 提取到冒号或等号前
        if let colonIndex = name.firstIndex(of: ":") {
            name = String(name[..<colonIndex])
        }
        if let equalsIndex = name.firstIndex(of: "=") {
            let beforeEquals = String(name[..<equalsIndex])
            if beforeEquals.contains(":") {
                name = beforeEquals
            }
        }
        
        // 去掉空格
        name = name.trimmingCharacters(in: .whitespaces)
        
        return name.isEmpty ? "unknown" : name
    }
    
    // MARK: - 依赖分析
    
    /// 提取依赖关系
    private static func extractDependencies(from imports: [String]) -> [String] {
        var dependencies: [String] = []
        
        for importStatement in imports {
            // Swift: import Foundation -> Foundation
            if importStatement.hasPrefix("import ") {
                let dep = String(importStatement.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                dependencies.append(dep)
            }
            // 其他语言的依赖提取...
        }
        
        return dependencies
    }
    
    // MARK: - 代码导航功能
    
    /// 查找符号定义
    static func findDefinition(of symbolName: String, in projectPath: String) -> CodeSymbol? {
        // 先搜索缓存
        for (_, symbols) in symbolCache {
            if let symbol = symbols.first(where: { $0.name == symbolName }) {
                return symbol
            }
        }
        
        // 如果缓存中没有，搜索文件
        return searchForDefinition(symbolName, in: projectPath)
    }
    
    /// 搜索符号定义
    private static func searchForDefinition(_ symbolName: String, in projectPath: String) -> CodeSymbol? {
        // 这里应该调用文件搜索工具
        // 简化实现：返回nil，让调用者使用其他方法
        return nil
    }
    
    /// 查找符号引用
    static func findReferences(of symbolName: String, in projectPath: String) -> [CodeReference] {
        // 检查缓存
        if let cached = referenceCache[symbolName] {
            return cached
        }
        
        let references: [CodeReference] = []
        
        // 搜索所有文件
        // 这里应该调用文件搜索工具
        // 简化实现：返回空数组
        
        // 缓存结果
        referenceCache[symbolName] = references
        
        return references
    }
    
    /// 获取文件结构概览
    static func getFileStructure(_ filePath: String, content: String) -> String {
        let ast = parseFile(filePath, content: content)
        
        var structure = "## 文件结构: \(filePath)\n\n"
        
        // 显示导入
        if !ast.imports.isEmpty {
            structure += "### 导入\n"
            for importStmt in ast.imports {
                structure += "- \(importStmt)\n"
            }
            structure += "\n"
        }
        
        // 显示符号
        let groupedSymbols = Dictionary(grouping: ast.symbols, by: { $0.kind })
        
        let kindOrder: [SymbolKind] = [.class, .struct, .enum, .protocol, .extension, .function, .variable]
        
        for kind in kindOrder {
            if let symbols = groupedSymbols[kind], !symbols.isEmpty {
                structure += "### \(symbolKindName(kind))\n"
                for symbol in symbols {
                    structure += "- **\(symbol.name)** (行 \(symbol.lineNumber))"
                    if let sig = symbol.signature {
                        structure += ": `\(sig)`"
                    }
                    structure += "\n"
                }
                structure += "\n"
            }
        }
        
        return structure
    }
    
    /// 获取符号类型名称
    private static func symbolKindName(_ kind: SymbolKind) -> String {
        switch kind {
        case .function: return "函数"
        case .variable: return "变量"
        case .class: return "类"
        case .struct: return "结构体"
        case .enum: return "枚举"
        case .protocol: return "协议"
        case .extension: return "扩展"
        case .import: return "导入"
        case .typealias: return "类型别名"
        case .unknown: return "其他"
        }
    }
    
    // MARK: - 智能提示
    
    /// 获取代码补全建议
    static func getCompletionSuggestions(for prefix: String, in filePath: String, content: String) -> [String] {
        let ast = parseFile(filePath, content: content)
        
        var suggestions: [String] = []
        
        // 匹配符号名称
        for symbol in ast.symbols {
            if symbol.name.lowercased().hasPrefix(prefix.lowercased()) {
                suggestions.append(symbol.name)
            }
        }
        
        // 匹配导入的模块
        for importStmt in ast.imports {
            if importStmt.lowercased().hasPrefix(prefix.lowercased()) {
                suggestions.append(importStmt)
            }
        }
        
        return suggestions
    }
    
    // MARK: - 缓存管理
    
    /// 清除缓存
    static func clearCache() {
        symbolCache.removeAll()
        referenceCache.removeAll()
        fileASTCache.removeAll()
    }
    
    /// 清除特定文件的缓存
    static func clearCache(for filePath: String) {
        symbolCache.removeValue(forKey: filePath)
        fileASTCache.removeValue(forKey: filePath)
        // 注意：引用缓存可能需要完全重建
    }
}
