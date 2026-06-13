import Foundation

class FindFilesTool: Tool {
    let name = "find_files"
    let description = "Find files by name pattern (like glob). Read-only, no confirmation needed. Returns matching file paths. Use this to locate files when you know part of the filename or want to find all files of a certain type."

    let parameters: [String: ToolParameter] = [
        "pattern": ToolParameter(type: "string", description: "File name pattern to match. Supports wildcards (e.g. '*.swift', '**/*.py', 'README*', '**/test_*.js').", required: true),
        "path": ToolParameter(type: "string", description: "Directory to search in (absolute path). Defaults to the working directory if not specified.")
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let pattern = arguments["pattern"] as? String else {
            throw ToolError.missingParameter("pattern")
        }

        let searchPath = (arguments["path"] as? String) ?? ToolRegistry.shared.workingDirectory ?? "."

        // 将文件搜索操作移到后台线程，避免阻塞主线程/UI
        return try await Task.detached(priority: .userInitiated) {
            // Build find command
            // Convert glob-like pattern to find -name syntax
            let escapedPattern = pattern.replacingOccurrences(of: "'", with: "'\\''")
            let command = "find '\(searchPath)' -name '\(escapedPattern)' -not -path '*/.git/*' -not -path '*/.build/*' -not -path '*/node_modules/*' 2>/dev/null | head -500"

            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()

                // Read pipe data BEFORE waitUntilExit to prevent deadlock
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ToolResult.success(toolCallId: "find_files", output: "No files found matching pattern: \(pattern)")
                }

                let files = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                let header = "Found \(files.count) file(s) matching '\(pattern)':\n\n"
                return ToolResult.success(toolCallId: "find_files", output: header + files.joined(separator: "\n"))
            } catch {
                return ToolResult.error(toolCallId: "find_files", error: "Failed to find files: \(error.localizedDescription)")
            }
        }.value
    }
}
