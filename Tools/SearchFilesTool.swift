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

        let searchPath: String
        switch FileSystemToolSupport.resolvedScopedPath(from: arguments, toolName: name) {
        case .success(let path):
            searchPath = path
        case .failure(let result):
            return result
        }
        let filePattern = arguments["file_pattern"] as? String

        return await Task.detached(priority: .userInitiated) {
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let root = URL(fileURLWithPath: searchPath)
                let scan = try FileSystemToolSupport.recursiveFileScan(
                    under: root,
                    matching: filePattern
                )
                let files = scan.files
                let warning = FileSystemToolSupport.partialScanWarning(for: scan)

                var matches: [String] = []
                var unreadableFiles: [String] = []
                let maxLines = 200

                for file in files {
                    let content: String
                    do {
                        content = try String(contentsOf: file, encoding: .utf8)
                    } catch {
                        unreadableFiles.append("\(file.path): \(error.localizedDescription)")
                        continue
                    }

                    let lines = content.components(separatedBy: .newlines)
                    for (index, line) in lines.enumerated() {
                        let range = NSRange(line.startIndex..<line.endIndex, in: line)
                        if regex.firstMatch(in: line, range: range) != nil {
                            matches.append("\(file.path):\(index + 1):\(line)")
                            if matches.count >= maxLines {
                                break
                            }
                        }
                    }

                    if matches.count >= maxLines {
                        break
                    }
                }

                var diagnostics = warning
                if !unreadableFiles.isEmpty {
                    diagnostics += "\n\n⚠️ 部分文件无法读取，搜索结果可能不完整："
                    for error in unreadableFiles.prefix(5) {
                        diagnostics += "\n- \(error)"
                    }
                    if unreadableFiles.count > 5 {
                        diagnostics += "\n... 还有 \(unreadableFiles.count - 5) 个文件读取失败"
                    }
                }

                if matches.isEmpty {
                    return ToolResult.success(toolCallId: "search_files", output: "No matches found for pattern: \(pattern)\(diagnostics)")
                }

                var output = matches.joined(separator: "\n")
                if matches.count == maxLines {
                    output += "\n\n... (matches truncated at \(maxLines) lines)"
                }
                output += diagnostics
                return ToolResult.success(toolCallId: "search_files", output: output)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain {
                return ToolResult.error(toolCallId: "search_files", error: "Invalid regex pattern: \(pattern)")
            } catch {
                return ToolResult.error(toolCallId: "search_files", error: "Failed to search files: \(error.localizedDescription)")
            }
        }.value
    }
}
