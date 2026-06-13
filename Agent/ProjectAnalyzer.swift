import Foundation

/// 项目理解增强系统 - 自动分析项目架构、识别依赖关系、生成项目文档
class ProjectAnalyzer {
    
    // MARK: - 项目结构类型
    
    enum ProjectType {
        case iosApp
        case macosApp
        case webFrontend
        case webBackend
        case cliTool
        case library
        case dataScience
        case devops
        case mixed
        case unknown
        
        var description: String {
            switch self {
            case .iosApp: return "iOS 应用"
            case .macosApp: return "macOS 应用"
            case .webFrontend: return "Web 前端"
            case .webBackend: return "Web 后端"
            case .cliTool: return "命令行工具"
            case .library: return "库/框架"
            case .dataScience: return "数据科学"
            case .devops: return "DevOps"
            case .mixed: return "混合项目"
            case .unknown: return "未知"
            }
        }
    }
    
    struct ProjectInfo {
        let type: ProjectType
        let name: String
        let languages: [String]
        let frameworks: [String]
        let buildSystems: [String]
        let dependencies: [Dependency]
        let structure: ProjectStructure
        let entryPoints: [String]
        let testFiles: [String]
        let configFiles: [String]
    }
    
    struct Dependency {
        let name: String
        let version: String?
        let type: DependencyType
        
        enum DependencyType {
            case direct
            case dev
            case peer
            case transitive
        }
    }
    
    struct ProjectStructure {
        let rootPath: String
        let directories: [DirectoryInfo]
        let keyFiles: [String]
        let totalFiles: Int
        let totalLines: Int
    }
    
    struct DirectoryInfo {
        let path: String
        let purpose: String
        let fileCount: Int
        let subdirectories: [String]
    }
    
    // MARK: - 项目分析
    
    /// 分析项目
    static func analyzeProject(at path: String) -> ProjectInfo {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return ProjectInfo(
                type: .unknown,
                name: (path as NSString).lastPathComponent,
                languages: [],
                frameworks: [],
                buildSystems: [],
                dependencies: [],
                structure: ProjectStructure(rootPath: path, directories: [], keyFiles: [], totalFiles: 0, totalLines: 0),
                entryPoints: [],
                testFiles: [],
                configFiles: []
            )
        }
        
        // 检测项目类型
        let projectType = detectProjectType(from: contents, path: path)
        
        // 检测语言
        let languages = detectLanguages(from: contents, path: path)
        
        // 检测框架
        let frameworks = detectFrameworks(from: contents, path: path)
        
        // 检测构建系统
        let buildSystems = detectBuildSystems(from: contents)
        
        // 分析依赖
        let dependencies = analyzeDependencies(from: contents, path: path)
        
        // 分析目录结构
        let structure = analyzeStructure(at: path, contents: contents)
        
        // 查找入口点
        let entryPoints = findEntryPoints(in: contents, path: path)
        
        // 查找测试文件
        let testFiles = findTestFiles(in: contents, path: path)
        
        // 查找配置文件
        let configFiles = findConfigFiles(in: contents)
        
        let name = (path as NSString).lastPathComponent
        
        return ProjectInfo(
            type: projectType,
            name: name,
            languages: languages,
            frameworks: frameworks,
            buildSystems: buildSystems,
            dependencies: dependencies,
            structure: structure,
            entryPoints: entryPoints,
            testFiles: testFiles,
            configFiles: configFiles
        )
    }
    
    // MARK: - 项目类型检测
    
    private static func detectProjectType(from contents: [String], path: String) -> ProjectType {
        let lowerContents = contents.map { $0.lowercased() }
        
        // iOS/macOS 应用
        if lowerContents.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            if lowerContents.contains(where: { $0.contains("ios") || $0.contains("iphone") }) {
                return .iosApp
            }
            return .macosApp
        }
        
        // Swift Package
        if lowerContents.contains("package.swift") {
            if lowerContents.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                return .macosApp
            }
            if lowerContents.contains("sources") && lowerContents.contains("main.swift") {
                return .cliTool
            }
            return .library
        }
        
        // Web 前端
        if lowerContents.contains("package.json") {
            if lowerContents.contains("vite.config.js") || lowerContents.contains("vite.config.ts") ||
               lowerContents.contains("next.config.js") || lowerContents.contains("next.config.ts") ||
               lowerContents.contains("nuxt.config.js") || lowerContents.contains("nuxt.config.ts") ||
               lowerContents.contains("angular.json") || lowerContents.contains("vue.config.js") {
                return .webFrontend
            }
        }
        
        // Web 后端
        if lowerContents.contains("requirements.txt") || lowerContents.contains("pyproject.toml") {
            if lowerContents.contains("manage.py") || lowerContents.contains("app.py") || lowerContents.contains("main.py") {
                return .webBackend
            }
        }
        
        if lowerContents.contains("go.mod") {
            return .webBackend
        }
        
        // 命令行工具
        if lowerContents.contains("main.go") || lowerContents.contains("main.rs") {
            return .cliTool
        }
        
        // 数据科学
        if lowerContents.contains(where: { $0.hasSuffix(".ipynb") }) {
            return .dataScience
        }
        
        // DevOps
        if lowerContents.contains("dockerfile") || lowerContents.contains("docker-compose.yml") ||
           lowerContents.contains(".github") || lowerContents.contains("terraform") {
            return .devops
        }
        
        return .unknown
    }
    
    // MARK: - 语言检测
    
    private static func detectLanguages(from contents: [String], path: String) -> [String] {
        var languages: Set<String> = []
        
        // 扫描文件扩展名
        let languageMap: [String: String] = [
            "swift": "Swift",
            "js": "JavaScript",
            "mjs": "JavaScript",
            "cjs": "JavaScript",
            "ts": "TypeScript",
            "tsx": "TypeScript",
            "jsx": "JavaScript",
            "py": "Python",
            "rs": "Rust",
            "go": "Go",
            "java": "Java",
            "kt": "Kotlin",
            "c": "C",
            "cpp": "C++",
            "cc": "C++",
            "cxx": "C++",
            "rb": "Ruby",
            "php": "PHP",
            "html": "HTML",
            "css": "CSS",
            "scss": "SCSS",
            "sass": "Sass",
            "less": "Less",
            "sql": "SQL",
            "sh": "Shell",
            "bash": "Shell",
            "zsh": "Shell"
        ]
        
        func scanDirectory(_ dirPath: String) {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { return }
            
            for item in items {
                let fullPath = (dirPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
                
                if isDir.boolValue {
                    // 跳过特殊目录
                    let skipDirs = [".git", "node_modules", ".build", "vendor", "__pycache__", ".venv"]
                    if !skipDirs.contains(item) {
                        scanDirectory(fullPath)
                    }
                } else {
                    let ext = (item as NSString).pathExtension.lowercased()
                    if let language = languageMap[ext] {
                        languages.insert(language)
                    }
                }
            }
        }
        
        scanDirectory(path)
        
        return Array(languages).sorted()
    }
    
    // MARK: - 框架检测
    
    private static func detectFrameworks(from contents: [String], path: String) -> [String] {
        var frameworks: Set<String> = []
        
        // 检查配置文件
        if contents.contains("package.json") {
            if let packageContent = readFile(at: "\(path)/package.json") {
                if packageContent.contains("react") { frameworks.insert("React") }
                if packageContent.contains("vue") { frameworks.insert("Vue.js") }
                if packageContent.contains("angular") { frameworks.insert("Angular") }
                if packageContent.contains("next") { frameworks.insert("Next.js") }
                if packageContent.contains("nuxt") { frameworks.insert("Nuxt.js") }
                if packageContent.contains("express") { frameworks.insert("Express.js") }
                if packageContent.contains("fastify") { frameworks.insert("Fastify") }
                if packageContent.contains("nestjs") { frameworks.insert("NestJS") }
            }
        }
        
        if contents.contains("requirements.txt") || contents.contains("pyproject.toml") {
            let reqFile = contents.contains("requirements.txt") ? "requirements.txt" : "pyproject.toml"
            if let reqContent = readFile(at: "\(path)/\(reqFile)") {
                if reqContent.contains("django") { frameworks.insert("Django") }
                if reqContent.contains("flask") { frameworks.insert("Flask") }
                if reqContent.contains("fastapi") { frameworks.insert("FastAPI") }
                if reqContent.contains("torch") { frameworks.insert("PyTorch") }
                if reqContent.contains("tensorflow") { frameworks.insert("TensorFlow") }
                if reqContent.contains("pandas") { frameworks.insert("Pandas") }
            }
        }
        
        if contents.contains("Package.swift") {
            if let packageContent = readFile(at: "\(path)/Package.swift") {
                if packageContent.contains("SwiftUI") { frameworks.insert("SwiftUI") }
                if packageContent.contains("UIKit") { frameworks.insert("UIKit") }
                if packageContent.contains("Vapor") { frameworks.insert("Vapor") }
                if packageContent.contains("SwiftNIO") { frameworks.insert("SwiftNIO") }
            }
        }
        
        return Array(frameworks).sorted()
    }
    
    // MARK: - 构建系统检测
    
    private static func detectBuildSystems(from contents: [String]) -> [String] {
        var buildSystems: [String] = []
        
        let buildSystemMap: [String: String] = [
            "package.json": "npm/yarn",
            "Package.swift": "Swift Package Manager",
            "Cargo.toml": "Cargo",
            "go.mod": "Go Modules",
            "requirements.txt": "pip",
            "pyproject.toml": "Poetry/pip",
            "Gemfile": "Bundler",
            "composer.json": "Composer",
            "pom.xml": "Maven",
            "build.gradle": "Gradle",
            "Makefile": "Make",
            "CMakeLists.txt": "CMake",
            "Dockerfile": "Docker",
            "docker-compose.yml": "Docker Compose"
        ]
        
        for (file, system) in buildSystemMap {
            if contents.contains(file) {
                buildSystems.append(system)
            }
        }
        
        return buildSystems
    }
    
    // MARK: - 依赖分析
    
    private static func analyzeDependencies(from contents: [String], path: String) -> [Dependency] {
        var dependencies: [Dependency] = []
        
        // npm 依赖
        if contents.contains("package.json") {
            if let packageContent = readFile(at: "\(path)/package.json") {
                dependencies.append(contentsOf: parseNpmDependencies(from: packageContent))
            }
        }
        
        // Swift Package 依赖
        if contents.contains("Package.swift") {
            if let packageContent = readFile(at: "\(path)/Package.swift") {
                dependencies.append(contentsOf: parseSwiftDependencies(from: packageContent))
            }
        }
        
        // Python 依赖
        if contents.contains("requirements.txt") {
            if let reqContent = readFile(at: "\(path)/requirements.txt") {
                dependencies.append(contentsOf: parsePipDependencies(from: reqContent))
            }
        }
        
        return dependencies
    }
    
    private static func parseNpmDependencies(from content: String) -> [Dependency] {
        var dependencies: [Dependency] = []
        
        // 简化解析：查找依赖名称
        let lines = content.components(separatedBy: .newlines)
        var inDependencies = false
        var inDevDependencies = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("\"dependencies\"") {
                inDependencies = true
                inDevDependencies = false
                continue
            }
            
            if trimmed.contains("\"devDependencies\"") {
                inDependencies = false
                inDevDependencies = true
                continue
            }
            
            if trimmed.hasPrefix("}") {
                inDependencies = false
                inDevDependencies = false
                continue
            }
            
            if (inDependencies || inDevDependencies) && trimmed.contains(":") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    var name = parts[0].trimmingCharacters(in: .whitespaces)
                    name = name.replacingOccurrences(of: "\"", with: "")
                    
                    var version = parts[1].trimmingCharacters(in: .whitespaces)
                    version = version.replacingOccurrences(of: "\"", with: "")
                    version = version.replacingOccurrences(of: ",", with: "")
                    
                    let type: Dependency.DependencyType = inDevDependencies ? .dev : .direct
                    dependencies.append(Dependency(name: name, version: version, type: type))
                }
            }
        }
        
        return dependencies
    }
    
    private static func parseSwiftDependencies(from content: String) -> [Dependency] {
        var dependencies: [Dependency] = []
        
        // 查找 .package(url: ...) 模式
        let pattern = "\\.package\\(url:\\s*\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            
            for match in matches {
                if let urlRange = Range(match.range(at: 1), in: content) {
                    let url = String(content[urlRange])
                    let name = (url as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
                    dependencies.append(Dependency(name: name, version: nil, type: .direct))
                }
            }
        }
        
        return dependencies
    }
    
    private static func parsePipDependencies(from content: String) -> [Dependency] {
        var dependencies: [Dependency] = []
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") && !trimmed.isEmpty {
                let parts = trimmed.components(separatedBy: "==")
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let version = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                dependencies.append(Dependency(name: name, version: version, type: .direct))
            }
        }
        
        return dependencies
    }
    
    // MARK: - 目录结构分析
    
    private static func analyzeStructure(at path: String, contents: [String]) -> ProjectStructure {
        var directories: [DirectoryInfo] = []
        var keyFiles: [String] = []
        var totalFiles = 0
        var totalLines = 0
        
        // 定义关键目录的用途
        let directoryPurposes: [String: String] = [
            "src": "源代码",
            "lib": "库代码",
            "app": "应用代码",
            "Sources": "Swift 源代码",
            "Tests": "测试代码",
            "test": "测试代码",
            "tests": "测试代码",
            "__tests__": "测试代码",
            "spec": "测试规范",
            "docs": "文档",
            "doc": "文档",
            "public": "静态资源",
            "static": "静态资源",
            "assets": "资源文件",
            "images": "图片资源",
            "config": "配置文件",
            "scripts": "脚本文件",
            "bin": "可执行文件",
            "cmd": "命令行入口",
            "internal": "内部包",
            "pkg": "包",
            "api": "API 定义",
            "models": "数据模型",
            "views": "视图",
            "controllers": "控制器",
            "services": "服务层",
            "utils": "工具函数",
            "helpers": "辅助函数",
            "middleware": "中间件",
            "routes": "路由",
            "components": "组件",
            "pages": "页面",
            "modules": "模块",
            "features": "功能模块"
        ]
        
        // 识别关键文件
        let keyFileNames = [
            "README.md", "README", "readme.md",
            "LICENSE", "LICENSE.md",
            "CHANGELOG.md", "CHANGELOG",
            "CONTRIBUTING.md",
            "Makefile", "makefile",
            "Dockerfile", "docker-compose.yml",
            ".gitignore", ".env.example",
            "package.json", "Package.swift", "Cargo.toml", "go.mod",
            "requirements.txt", "pyproject.toml",
            "tsconfig.json", "webpack.config.js", "vite.config.ts"
        ]
        
        for item in contents {
            if keyFileNames.contains(item) {
                keyFiles.append(item)
            }
            
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            
            if isDir.boolValue {
                let purpose = directoryPurposes[item] ?? "项目目录"
                let subContents = (try? FileManager.default.contentsOfDirectory(atPath: fullPath)) ?? []
                let subDirs = subContents.filter { subItem in
                    var subIsDir: ObjCBool = false
                    let subPath = (fullPath as NSString).appendingPathComponent(subItem)
                    FileManager.default.fileExists(atPath: subPath, isDirectory: &subIsDir)
                    return subIsDir.boolValue
                }
                
                directories.append(DirectoryInfo(
                    path: item,
                    purpose: purpose,
                    fileCount: subContents.count - subDirs.count,
                    subdirectories: subDirs
                ))
            } else {
                totalFiles += 1
                // 简单估算行数
                if let content = readFile(at: fullPath) {
                    totalLines += content.components(separatedBy: .newlines).count
                }
            }
        }
        
        return ProjectStructure(
            rootPath: path,
            directories: directories,
            keyFiles: keyFiles,
            totalFiles: totalFiles,
            totalLines: totalLines
        )
    }
    
    // MARK: - 入口点查找
    
    private static func findEntryPoints(in contents: [String], path: String) -> [String] {
        var entryPoints: [String] = []
        
        let entryPointPatterns = [
            "main.swift",
            "main.go",
            "main.rs",
            "main.py",
            "app.py",
            "index.js",
            "index.ts",
            "server.js",
            "server.ts",
            "Program.cs",
            "Main.java"
        ]
        
        for pattern in entryPointPatterns {
            if contents.contains(pattern) {
                entryPoints.append(pattern)
            }
        }
        
        return entryPoints
    }
    
    // MARK: - 测试文件查找
    
    private static func findTestFiles(in contents: [String], path: String) -> [String] {
        var testFiles: [String] = []
        
        let testPatterns = ["test", "spec", "Test", "Spec", "_test", "_spec"]
        
        func scanForTests(_ dirPath: String, relativePath: String = "") {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { return }
            
            for item in items {
                let fullPath = (dirPath as NSString).appendingPathComponent(item)
                let relPath = relativePath.isEmpty ? item : "\(relativePath)/\(item)"
                
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
                
                if isDir.boolValue {
                    let skipDirs = [".git", "node_modules", ".build", "vendor"]
                    if !skipDirs.contains(item) {
                        scanForTests(fullPath, relativePath: relPath)
                    }
                } else {
                    for pattern in testPatterns {
                        if item.contains(pattern) {
                            testFiles.append(relPath)
                            break
                        }
                    }
                }
            }
        }
        
        scanForTests(path)
        
        return testFiles
    }
    
    // MARK: - 配置文件查找
    
    private static func findConfigFiles(in contents: [String]) -> [String] {
        let configPatterns = [
            ".env", ".env.example", ".env.local",
            ".gitignore", ".gitattributes",
            ".eslintrc", ".eslintrc.js", ".eslintrc.json",
            ".prettierrc", ".prettierrc.js", ".prettierrc.json",
            "tsconfig.json", "jsconfig.json",
            "webpack.config.js", "vite.config.ts", "vite.config.js",
            "babel.config.js", ".babelrc",
            "jest.config.js", "vitest.config.ts",
            ".editorconfig",
            "biome.json", "deno.json"
        ]
        
        return contents.filter { configPatterns.contains($0) }
    }
    
    // MARK: - 文档生成
    
    /// 生成项目概览文档
    static func generateProjectOverview(_ info: ProjectInfo) -> String {
        var doc = "# \(info.name) 项目概览\n\n"
        
        // 项目类型
        doc += "## 项目类型\n"
        doc += "\(info.type.description)\n\n"
        
        // 技术栈
        doc += "## 技术栈\n"
        if !info.languages.isEmpty {
            doc += "**语言**: \(info.languages.joined(separator: ", "))\n"
        }
        if !info.frameworks.isEmpty {
            doc += "**框架**: \(info.frameworks.joined(separator: ", "))\n"
        }
        if !info.buildSystems.isEmpty {
            doc += "**构建系统**: \(info.buildSystems.joined(separator: ", "))\n"
        }
        doc += "\n"
        
        // 项目结构
        doc += "## 项目结构\n"
        doc += "- 总文件数: \(info.structure.totalFiles)\n"
        doc += "- 总代码行数: \(info.structure.totalLines)\n\n"
        
        if !info.structure.directories.isEmpty {
            doc += "### 目录说明\n"
            for dir in info.structure.directories.sorted(by: { $0.fileCount > $1.fileCount }) {
                doc += "- **\(dir.path)/**: \(dir.purpose) (\(dir.fileCount) 个文件)\n"
            }
            doc += "\n"
        }
        
        // 入口点
        if !info.entryPoints.isEmpty {
            doc += "## 入口点\n"
            for entry in info.entryPoints {
                doc += "- \(entry)\n"
            }
            doc += "\n"
        }
        
        // 依赖
        if !info.dependencies.isEmpty {
            doc += "## 依赖 (\(info.dependencies.count) 个)\n"
            let directDeps = info.dependencies.filter { $0.type == .direct }
            let devDeps = info.dependencies.filter { $0.type == .dev }
            
            if !directDeps.isEmpty {
                doc += "### 生产依赖\n"
                for dep in directDeps.prefix(10) {
                    doc += "- \(dep.name)"
                    if let version = dep.version {
                        doc += " (\(version))"
                    }
                    doc += "\n"
                }
                if directDeps.count > 10 {
                    doc += "- ... 还有 \(directDeps.count - 10) 个\n"
                }
            }
            
            if !devDeps.isEmpty {
                doc += "### 开发依赖\n"
                for dep in devDeps.prefix(5) {
                    doc += "- \(dep.name)"
                    if let version = dep.version {
                        doc += " (\(version))"
                    }
                    doc += "\n"
                }
            }
            doc += "\n"
        }
        
        // 关键文件
        if !info.structure.keyFiles.isEmpty {
            doc += "## 关键文件\n"
            for file in info.structure.keyFiles {
                doc += "- \(file)\n"
            }
            doc += "\n"
        }
        
        // 测试
        if !info.testFiles.isEmpty {
            doc += "## 测试\n"
            doc += "发现 \(info.testFiles.count) 个测试文件\n"
            for test in info.testFiles.prefix(5) {
                doc += "- \(test)\n"
            }
            doc += "\n"
        }
        
        return doc
    }
    
    // MARK: - 辅助方法
    
    private static func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
