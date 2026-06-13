import Foundation

class ListDirectoryTool: Tool {
    let name = "list_directory"
    let description = "List directory contents with detailed information. Read-only, no confirmation needed. Shows file permissions, size, modification date, and name. Use this to understand the structure of a directory."

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "Absolute path of the directory to list. Defaults to the working directory if not specified.")
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        let dirPath = (arguments["path"] as? String) ?? ToolRegistry.shared.workingDirectory ?? "."

        // 将目录列表操作移到后台线程，避免阻塞主线程/UI
        return try await Task.detached(priority: .userInitiated) {
            let command = "ls -la '\(dirPath)' 2>/dev/null"

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

                if process.terminationStatus != 0 {
                    return ToolResult.error(toolCallId: "list_directory", error: "Directory not found or cannot be accessed: \(dirPath)")
                }

                return ToolResult.success(toolCallId: "list_directory", output: "Directory: \(dirPath)\n\n\(output)")
            } catch {
                return ToolResult.error(toolCallId: "list_directory", error: "Failed to list directory: \(error.localizedDescription)")
            }
        }.value
    }
}
