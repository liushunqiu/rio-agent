import Foundation

class ListDirectoryTool: Tool {
    let name = "list_directory"
    let description = "List directory contents with detailed information. Read-only, no confirmation needed. Shows file permissions, size, modification date, and name. Use this to understand the structure of a directory."

    let parameters: [String: ToolParameter] = [
        "path": ToolParameter(type: "string", description: "Absolute path of the directory to list. Defaults to the working directory if not specified.")
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        let dirPath = (arguments["path"] as? String) ?? ToolRegistry.shared.workingDirectory ?? "."

        return await Task.detached(priority: .userInitiated) {
            do {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    return ToolResult.error(toolCallId: "list_directory", error: "Directory not found or cannot be accessed: \(dirPath)")
                }

                let directory = URL(fileURLWithPath: dirPath)
                let entries = try FileSystemToolSupport.sortedDirectoryContents(at: directory)
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

                let output = entries.map { url -> String in
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let kind = values?.isDirectory == true ? "d" : "-"
                    let size = formatter.string(fromByteCount: Int64(values?.fileSize ?? 0))
                    let modified = values?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "unknown"
                    return "\(kind) \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(modified) \(url.lastPathComponent)"
                }.joined(separator: "\n")

                return ToolResult.success(toolCallId: "list_directory", output: "Directory: \(dirPath)\n\n\(output)")
            } catch {
                return ToolResult.error(toolCallId: "list_directory", error: "Failed to list directory: \(error.localizedDescription)")
            }
        }.value
    }
}
