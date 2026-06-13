import Foundation

/// Provides context-aware intelligence based on file types and project structure
class ContextAwareness {
    
    // MARK: - File Type Detection
    
    enum FileType {
        case swift
        case javascript
        case typescript
        case python
        case rust
        case go
        case java
        case kotlin
        case c
        case cpp
        case ruby
        case php
        case html
        case css
        case json
        case yaml
        case markdown
        case shell
        case dockerfile
        case unknown
        
        var displayName: String {
            switch self {
            case .swift: return "Swift"
            case .javascript: return "JavaScript"
            case .typescript: return "TypeScript"
            case .python: return "Python"
            case .rust: return "Rust"
            case .go: return "Go"
            case .java: return "Java"
            case .kotlin: return "Kotlin"
            case .c: return "C"
            case .cpp: return "C++"
            case .ruby: return "Ruby"
            case .php: return "PHP"
            case .html: return "HTML"
            case .css: return "CSS"
            case .json: return "JSON"
            case .yaml: return "YAML"
            case .markdown: return "Markdown"
            case .shell: return "Shell"
            case .dockerfile: return "Dockerfile"
            case .unknown: return "Unknown"
            }
        }
    }
    
    // MARK: - Project Type Detection
    
    enum ProjectType {
        case iosApp
        case macosApp
        case webFrontend
        case webBackend
        case cliTool
        case library
        case dataScience
        case devops
        case unknown
        
        var displayName: String {
            switch self {
            case .iosApp: return "iOS App"
            case .macosApp: return "macOS App"
            case .webFrontend: return "Web Frontend"
            case .webBackend: return "Web Backend"
            case .cliTool: return "CLI Tool"
            case .library: return "Library"
            case .dataScience: return "Data Science"
            case .devops: return "DevOps"
            case .unknown: return "Unknown"
            }
        }
    }
    
    // MARK: - Context Information
    
    struct FileContext {
        let fileType: FileType
        let framework: String?
        let testFramework: String?
        let buildSystem: String?
        let commonPatterns: [String]
        let suggestedTools: [String]
    }
    
    struct ProjectContext {
        let projectType: ProjectType
        let primaryLanguage: FileType
        let frameworks: [String]
        let buildSystems: [String]
        let testFrameworks: [String]
        let directoryStructure: [String: String] // key directories and their purposes
    }
    
    // MARK: - File Type Detection
    
    static func detectFileType(from filename: String) -> FileType {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return .swift
        case "js", "mjs", "cjs":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "py", "pyw":
            return .python
        case "rs":
            return .rust
        case "go":
            return .go
        case "java":
            return .java
        case "kt", "kts":
            return .kotlin
        case "c", "h":
            return .c
        case "cpp", "cc", "cxx", "hpp":
            return .cpp
        case "rb":
            return .ruby
        case "php":
            return .php
        case "html", "htm":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "md", "markdown":
            return .markdown
        case "sh", "bash", "zsh":
            return .shell
        case "dockerfile":
            return .dockerfile
        default:
            // Check filename patterns
            let lowerFilename = filename.lowercased()
            if lowerFilename == "dockerfile" || lowerFilename.hasPrefix("dockerfile.") {
                return .dockerfile
            }
            return .unknown
        }
    }
    
    /// Detect file type based on file content
    static func detectFileTypeFromContent(_ content: String, filename: String) -> FileType {
        // First try by extension
        let extType = detectFileType(from: filename)
        if extType != .unknown {
            return extType
        }
        
        // Analyze content for clues
        let lines = content.components(separatedBy: .newlines)
        let firstLines = lines.prefix(20).joined(separator: "\n").lowercased()
        
        // Check for shebang lines
        if firstLines.hasPrefix("#!/") {
            if firstLines.contains("python") || firstLines.contains("python3") {
                return .python
            }
            if firstLines.contains("node") || firstLines.contains("nodejs") {
                return .javascript
            }
            if firstLines.contains("ruby") {
                return .ruby
            }
            if firstLines.contains("bash") || firstLines.contains("sh") {
                return .shell
            }
        }
        
        // Check for Swift imports
        if content.contains("import SwiftUI") || content.contains("import UIKit") || 
           content.contains("import Foundation") || content.contains("import Swift") {
            return .swift
        }
        
        // Check for JavaScript/TypeScript patterns
        if content.contains("function ") || content.contains("const ") || 
           content.contains("let ") || content.contains("var ") ||
           content.contains("import ") || content.contains("export ") {
            if content.contains(": ") || content.contains("interface ") || 
               content.contains("type ") || content.contains("enum ") {
                return .typescript
            }
            return .javascript
        }
        
        // Check for Python patterns
        if content.contains("def ") || content.contains("class ") || 
           content.contains("import ") || content.contains("from ") {
            if content.contains("def __init__") || content.contains("self.") ||
               content.contains("print(") || content.contains("if __name__") {
                return .python
            }
        }
        
        // Check for Rust patterns
        if content.contains("fn ") || content.contains("struct ") || 
           content.contains("impl ") || content.contains("use ") {
            if content.contains("pub ") || content.contains("mod ") ||
               content.contains("match ") || content.contains("->") {
                return .rust
            }
        }
        
        // Check for Go patterns
        if content.contains("package ") || content.contains("func ") || 
           content.contains("import ") || content.contains("type ") {
            if content.contains("func main()") || content.contains("func ") ||
               content.contains("package main") {
                return .go
            }
        }
        
        // Check for HTML
        if content.contains("<html") || content.contains("<!DOCTYPE") || 
           content.contains("<head") || content.contains("<body") {
            return .html
        }
        
        // Check for CSS
        if content.contains("{") && content.contains("}") && 
           (content.contains("color:") || content.contains("background:") || 
            content.contains("font-size:") || content.contains("margin:")) {
            return .css
        }
        
        // Check for JSON
        if content.hasPrefix("{") || content.hasPrefix("[") {
            if content.contains("\"") && content.contains(":") {
                return .json
            }
        }
        
        // Check for YAML
        if content.contains("---") || content.contains("version:") || 
           content.contains("name:") || content.contains("dependencies:") {
            return .yaml
        }
        
        // Check for Markdown
        if content.contains("# ") || content.contains("## ") || 
           content.contains("```") || content.contains("- ") {
            return .markdown
        }
        
        // Check for Dockerfile
        if content.contains("FROM ") || content.contains("RUN ") || 
           content.contains("COPY ") || content.contains("CMD ") {
            return .dockerfile
        }
        
        return .unknown
    }
    
    // MARK: - Project Type Detection
    
    static func detectProjectType(from directoryContents: [String]) -> ProjectType {
        let files = directoryContents.map { $0.lowercased() }
        
        // iOS/macOS App indicators
        if files.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            if files.contains(where: { $0.contains("ios") || $0.contains("iphone") }) {
                return .iosApp
            }
            return .macosApp
        }
        
        // Swift Package (could be library or CLI)
        if files.contains("package.swift") {
            if files.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                return .macosApp
            }
            // Check for CLI indicators
            if files.contains("sources") && files.contains("main.swift") {
                return .cliTool
            }
            return .library
        }
        
        // Web Frontend indicators
        if files.contains("package.json") {
            if files.contains("vite.config.js") || files.contains("vite.config.ts") ||
               files.contains("next.config.js") || files.contains("next.config.ts") ||
               files.contains("nuxt.config.js") || files.contains("nuxt.config.ts") ||
               files.contains("angular.json") || files.contains("vue.config.js") {
                return .webFrontend
            }
            // Check for React/Vue/Angular patterns
            if files.contains("src") && files.contains("public") {
                return .webFrontend
            }
        }
        
        // Web Backend indicators
        if files.contains("requirements.txt") || files.contains("pyproject.toml") ||
           files.contains("pipfile") {
            if files.contains("manage.py") { // Django
                return .webBackend
            }
            // Check for Flask/FastAPI patterns
            if files.contains("app.py") || files.contains("main.py") || 
               files.contains("api") || files.contains("routes") {
                return .webBackend
            }
        }
        
        if files.contains("go.mod") {
            // Check for web backend patterns
            if files.contains("main.go") && (files.contains("routes") || 
               files.contains("controllers") || files.contains("handlers")) {
                return .webBackend
            }
            return .cliTool
        }
        
        if files.contains("cargo.toml") {
            // Check for web backend patterns
            if files.contains("src") && files.contains("api") {
                return .webBackend
            }
            return .library
        }
        
        // CLI Tool indicators
        if files.contains("main.go") || files.contains("main.rs") ||
           files.contains("cli.py") || files.contains("cli.js") {
            return .cliTool
        }
        
        // Data Science indicators
        if files.contains(where: { $0.hasSuffix(".ipynb") }) ||
           files.contains("jupyter") || files.contains("notebook") ||
           files.contains("requirements.txt") && files.contains("data") {
            return .dataScience
        }
        
        // DevOps indicators
        if files.contains("dockerfile") || files.contains("docker-compose.yml") ||
           files.contains("kubernetes") || files.contains("k8s") ||
           files.contains("terraform") || files.contains(".github") {
            return .devops
        }
        
        // Check for common patterns
        if files.contains("src") && files.contains("test") {
            return .library
        }
        
        if files.contains("bin") || files.contains("cmd") {
            return .cliTool
        }
        
        return .unknown
    }
    
    // MARK: - Context Generation
    
    static func generateFileContext(for filename: String) -> FileContext {
        let fileType = detectFileType(from: filename)
        
        var framework: String? = nil
        var testFramework: String? = nil
        var buildSystem: String? = nil
        var commonPatterns: [String] = []
        var suggestedTools: [String] = ["read_file", "edit_file"]
        
        switch fileType {
        case .swift:
            framework = "SwiftUI/UIKit"
            testFramework = "XCTest"
            buildSystem = "Swift Package Manager"
            commonPatterns = [
                "Use guard let for early returns",
                "Prefer let over var",
                "Use trailing closures",
                "Follow Swift API Design Guidelines"
            ]
            suggestedTools = ["read_file", "edit_file", "search_files", "execute_command"]
            
        case .javascript, .typescript:
            framework = "React/Vue/Angular"
            testFramework = "Jest/Mocha/Vitest"
            buildSystem = "npm/yarn/pnpm"
            commonPatterns = [
                "Use const by default",
                "Prefer arrow functions",
                "Use async/await over callbacks",
                "Follow ESLint rules"
            ]
            suggestedTools = ["read_file", "edit_file", "search_files", "execute_command"]
            
        case .python:
            framework = "Django/Flask/FastAPI"
            testFramework = "pytest/unittest"
            buildSystem = "pip/poetry/conda"
            commonPatterns = [
                "Follow PEP 8",
                "Use type hints",
                "Prefer list comprehensions",
                "Use virtual environments"
            ]
            suggestedTools = ["read_file", "edit_file", "search_files", "execute_command"]
            
        case .rust:
            framework = "Actix/Axum/Rocket"
            testFramework = "Built-in test framework"
            buildSystem = "Cargo"
            commonPatterns = [
                "Use Result for error handling",
                "Prefer iterators over loops",
                "Use ownership system correctly",
                "Follow Rust naming conventions"
            ]
            suggestedTools = ["read_file", "edit_file", "search_files", "execute_command"]
            
        case .go:
            framework = "Gin/Echo/Fiber"
            testFramework = "Built-in testing package"
            buildSystem = "Go modules"
            commonPatterns = [
                "Handle errors explicitly",
                "Use goroutines for concurrency",
                "Follow Go naming conventions",
                "Keep interfaces small"
            ]
            suggestedTools = ["read_file", "edit_file", "search_files", "execute_command"]
            
        case .json:
            suggestedTools = ["read_file", "write_file"]
            commonPatterns = [
                "Validate JSON structure",
                "Use proper indentation"
            ]
            
        case .yaml:
            suggestedTools = ["read_file", "write_file"]
            commonPatterns = [
                "Be careful with indentation",
                "Use proper YAML syntax"
            ]
            
        case .markdown:
            suggestedTools = ["read_file", "write_file"]
            commonPatterns = [
                "Use consistent heading levels",
                "Include code examples"
            ]
            
        default:
            suggestedTools = ["read_file", "edit_file"]
        }
        
        return FileContext(
            fileType: fileType,
            framework: framework,
            testFramework: testFramework,
            buildSystem: buildSystem,
            commonPatterns: commonPatterns,
            suggestedTools: suggestedTools
        )
    }
    
    static func generateProjectContext(from directoryContents: [String], projectPath: String) -> ProjectContext {
        let projectType = detectProjectType(from: directoryContents)
        
        // Detect primary language
        var languageCounts: [FileType: Int] = [:]
        for file in directoryContents {
            let fileType = detectFileType(from: file)
            if fileType != .unknown {
                languageCounts[fileType, default: 0] += 1
            }
        }
        
        let primaryLanguage = languageCounts.max(by: { $0.value < $1.value })?.key ?? .unknown
        
        // Detect frameworks and build systems
        var frameworks: [String] = []
        var buildSystems: [String] = []
        var testFrameworks: [String] = []
        
        let lowerContents = directoryContents.map { $0.lowercased() }
        
        // Framework detection
        if lowerContents.contains("package.json") {
            frameworks.append("Node.js")
            if lowerContents.contains("react") || lowerContents.contains("next.config.js") {
                frameworks.append("React/Next.js")
            }
            if lowerContents.contains("vue") || lowerContents.contains("nuxt.config.js") {
                frameworks.append("Vue/Nuxt.js")
            }
        }
        
        if lowerContents.contains("requirements.txt") || lowerContents.contains("pyproject.toml") {
            frameworks.append("Python")
            if lowerContents.contains("django") {
                frameworks.append("Django")
            }
            if lowerContents.contains("flask") {
                frameworks.append("Flask")
            }
        }
        
        if lowerContents.contains("cargo.toml") {
            frameworks.append("Rust")
        }
        
        if lowerContents.contains("go.mod") {
            frameworks.append("Go")
        }
        
        // Build system detection
        if lowerContents.contains("package.json") {
            buildSystems.append("npm/yarn")
        }
        if lowerContents.contains("cargo.toml") {
            buildSystems.append("Cargo")
        }
        if lowerContents.contains("go.mod") {
            buildSystems.append("Go modules")
        }
        if lowerContents.contains("makefile") {
            buildSystems.append("Make")
        }
        if lowerContents.contains("cmakelists.txt") {
            buildSystems.append("CMake")
        }
        
        // Test framework detection
        if lowerContents.contains("jest.config.js") || lowerContents.contains("jest.config.ts") {
            testFrameworks.append("Jest")
        }
        if lowerContents.contains("pytest.ini") || lowerContents.contains("conftest.py") {
            testFrameworks.append("pytest")
        }
        if lowerContents.contains("tests") || lowerContents.contains("test") {
            testFrameworks.append("Built-in tests")
        }
        
        // Directory structure analysis
        var directoryStructure: [String: String] = [:]
        
        for dir in ["src", "lib", "app", "components", "pages", "views", "controllers", 
                    "models", "services", "utils", "helpers", "tests", "test", "spec",
                    "docs", "documentation", "scripts", "config", "configuration"] {
            if lowerContents.contains(dir) {
                directoryStructure[dir] = "Standard \(dir) directory"
            }
        }
        
        return ProjectContext(
            projectType: projectType,
            primaryLanguage: primaryLanguage,
            frameworks: frameworks,
            buildSystems: buildSystems,
            testFrameworks: testFrameworks,
            directoryStructure: directoryStructure
        )
    }
    
    // MARK: - Context Injection

    static func generateContextPrompt(for fileContext: FileContext, taskType: ToolRecommender.TaskType? = nil) -> String {
        var prompt = "\n## File Context Guidance\n"

        switch fileContext.fileType {
        case .swift:
            prompt += "- This is a Swift file. Use guard-let for early returns. Prefer trailing closures.\n"
            prompt += "- Follow Swift API Design Guidelines. Use `let` over `var` where possible.\n"
            prompt += "- For SwiftUI views, ensure @MainActor compliance when accessing @Published properties.\n"
        case .javascript, .typescript:
            prompt += "- Use const by default. Prefer arrow functions. Use async/await over callbacks.\n"
            prompt += "- Follow ESLint rules if configured. Use strict equality (===).\n"
        case .python:
            prompt += "- Follow PEP 8. Use type hints. Prefer list comprehensions.\n"
            prompt += "- Use virtual environments. Handle exceptions explicitly.\n"
        case .rust:
            prompt += "- Use Result for error handling. Prefer iterators. Respect ownership rules.\n"
            prompt += "- Run `cargo clippy` after modifications to catch common mistakes.\n"
        case .go:
            prompt += "- Handle errors explicitly (no ignored errors). Follow Go naming conventions.\n"
            prompt += "- Keep interfaces small. Use goroutines for concurrent operations.\n"
        case .java, .kotlin:
            prompt += "- Follow standard Java/Kotlin conventions. Use null-safety features in Kotlin.\n"
        default:
            prompt += "- File type: \(fileContext.fileType.displayName)\n"
        }

        // Add task-specific guidance
        if let taskType = taskType {
            switch taskType {
            case .codeModification:
                prompt += "- When modifying: read the file first, understand context, then make targeted edits.\n"
                prompt += "- Prefer edit_file over write_file for changes to existing files.\n"
            case .debugging:
                prompt += "- When debugging: search for error messages, read surrounding code, check recent changes.\n"
            case .testing:
                prompt += "- When testing: identify the test framework, run relevant tests, check for regressions.\n"
            case .codeSearch:
                prompt += "- When searching: use search_files for content patterns, find_files for file names.\n"
            default:
                break
            }
        }

        return prompt
    }

    static func generateContextPrompt(for projectContext: ProjectContext) -> String {
        var prompt = "\n## Project Context Guidance\n"

        switch projectContext.projectType {
        case .macosApp:
            prompt += "- This is a macOS app. Build with: xcodebuild or swift build.\n"
            prompt += "- Ensure @MainActor compliance for UI-related code.\n"
            prompt += "- Test with: xcodebuild test or swift test.\n"
        case .iosApp:
            prompt += "- This is an iOS app. Build with: xcodebuild -scheme <scheme> -destination 'platform=iOS Simulator,...'.\n"
            prompt += "- Ensure @MainActor compliance for UI code.\n"
        case .webFrontend:
            prompt += "- This is a web frontend project. Common commands: npm run dev, npm run build, npm test.\n"
            prompt += "- Check for linting: npm run lint. Check formatting: npm run format.\n"
        case .webBackend:
            prompt += "- This is a web backend project.\n"
            if projectContext.primaryLanguage == .python {
                prompt += "- Run with: python manage.py runserver (Django) or uvicorn main:app (FastAPI).\n"
            }
        case .cliTool:
            prompt += "- This is a CLI tool. Build with the project's build system.\n"
        case .library:
            prompt += "- This is a library. Build with: swift build / cargo build / npm run build.\n"
            prompt += "- Test with: swift test / cargo test / npm test.\n"
        default:
            prompt += "- Project type: \(projectContext.projectType.displayName)\n"
        }

        if !projectContext.buildSystems.isEmpty {
            prompt += "- Build systems: \(projectContext.buildSystems.joined(separator: ", "))\n"
        }
        if !projectContext.testFrameworks.isEmpty {
            prompt += "- Test frameworks: \(projectContext.testFrameworks.joined(separator: ", "))\n"
        }

        return prompt
    }
    
    // MARK: - Smart Suggestions
    
    static func suggestAction(for task: String, fileContext: FileContext?, projectContext: ProjectContext?) -> String {
        let taskLower = task.lowercased()
        var suggestions: [String] = []
        
        // File-specific suggestions
        if let fileContext = fileContext {
            if taskLower.contains("test") && fileContext.testFramework != nil {
                suggestions.append("Consider running tests with: \(fileContext.testFramework!)")
            }
            
            if taskLower.contains("build") && fileContext.buildSystem != nil {
                suggestions.append("Build with: \(fileContext.buildSystem!)")
            }
            
            if taskLower.contains("lint") || taskLower.contains("format") {
                switch fileContext.fileType {
                case .swift:
                    suggestions.append("Use SwiftLint for code style")
                case .javascript, .typescript:
                    suggestions.append("Use ESLint and Prettier")
                case .python:
                    suggestions.append("Use Black and Flake8")
                case .rust:
                    suggestions.append("Use rustfmt and clippy")
                default:
                    break
                }
            }
        }
        
        // Project-specific suggestions
        if let projectContext = projectContext {
            if taskLower.contains("deploy") || taskLower.contains("ci/cd") {
                if projectContext.projectType == .devops {
                    suggestions.append("Check CI/CD configuration in .github/workflows")
                }
            }
            
            if taskLower.contains("documentation") || taskLower.contains("docs") {
                suggestions.append("Documentation should be in docs/ directory")
            }
        }
        
        if suggestions.isEmpty {
            return ""
        }
        
        return "\n[Suggestions]\n" + suggestions.map { "- \($0)" }.joined(separator: "\n")
    }
}
