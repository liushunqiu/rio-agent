import Foundation

class SearchFilesTool: Tool {
    let name = "search_files"
    let description = "Search file contents by regex pattern (like grep). Read-only, no confirmation needed. Returns matching lines with file paths and line numbers. Use this to find code patterns, function definitions, variable usages, etc. across the codebase."

    let parameters: [String: ToolParameter] = [
        "pattern": ToolParameter(type: "string", description: "Regular expression pattern to search for. Supports standard grep regex syntax.", required: true),
        "path": ToolParameter(type: "string", description: "Directory to search in (absolute path). Defaults to the working directory if not specified."),
        "file_pattern": ToolParameter(type: "string", description: "File name wildcard to filter which files to search (e.g. '*.swift', '*.py', '*.ts'). Searches all files if not specified.")
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let pattern = arguments["pattern"] as? String else {
            throw ToolError.missingParameter("pattern")
        }

        let searchPath = (arguments["path"] as? String) ?? ToolRegistry.shared.workingDirectory ?? "."
        let filePattern = arguments["file_pattern"] as? String

        // 将搜索操作移到后台线程，避免阻塞主线程/UI
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            var grepArguments = ["-rn"]
            if let filePattern = filePattern {
                grepArguments.append("--include=\(filePattern)")
            }
            grepArguments += ["--", pattern, searchPath]
            process.arguments = grepArguments
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()

                // CRITICAL: Read pipe data BEFORE waitUntilExit to prevent deadlock.
                // If grep output exceeds pipe buffer (~16KB), the child process blocks
                // on write. If we call waitUntilExit() first, we deadlock because the
                // parent waits for child exit while child waits for pipe drain.
                // readDataToEndOfFile() blocks until EOF (when process exits and closes pipe).
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""

                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ToolResult.success(toolCallId: "search_files", output: "No matches found for pattern: \(pattern)")
                }

                // Limit output to prevent token overflow
                let lines = output.components(separatedBy: .newlines)
                let maxLines = 200
                if lines.count > maxLines {
                    let truncated = lines.prefix(maxLines).joined(separator: "\n")
                    return ToolResult.success(toolCallId: "search_files", output: "\(truncated)\n\n... (\(lines.count - maxLines) more matches truncated)")
                }

                return ToolResult.success(toolCallId: "search_files", output: output)
            } catch {
                return ToolResult.error(toolCallId: "search_files", error: "Failed to search files: \(error.localizedDescription)")
            }
        }.value
    }
}
