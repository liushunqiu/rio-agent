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
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            process.arguments = [
                searchPath,
                "-name", pattern,
                "-not", "-path", "*/.git/*",
                "-not", "-path", "*/.build/*",
                "-not", "-path", "*/node_modules/*"
            ]
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
                let limitedFiles = Array(files.prefix(500))
                var result = "Found \(limitedFiles.count) file(s) matching '\(pattern)':\n\n"
                result += limitedFiles.joined(separator: "\n")
                if files.count > limitedFiles.count {
                    result += "\n\n... (\(files.count - limitedFiles.count) more files truncated)"
                }
                return ToolResult.success(toolCallId: "find_files", output: result)
            } catch {
                return ToolResult.error(toolCallId: "find_files", error: "Failed to find files: \(error.localizedDescription)")
            }
        }.value
    }
}
