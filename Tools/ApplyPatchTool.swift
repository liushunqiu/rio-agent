import Foundation

class ApplyPatchTool: Tool {
    let name = "apply_patch"
    let description = "Apply a multi-file patch using a structured diff format. Supports adding, updating, and deleting files in a single operation. Use this for coordinated changes across multiple files. Work directory operations auto-execute; cross-directory operations require user confirmation."

    let parameters: [String: ToolParameter] = [
        "patch": ToolParameter(type: "string", description: """
            The patch content in the following format:

            *** Add File: <absolute_path>
            <file content>

            *** Update File: <absolute_path>
            <<<<<<< SEARCH
            <exact text to find>
            =======
            <replacement text>
            >>>>>>> REPLACE

            *** Delete File: <absolute_path>

            Multiple blocks can be combined. Each SEARCH/REPLACE block must match exactly one occurrence in the file. Multiple SEARCH/REPLACE blocks per file are supported.
            """, required: true)
    ]

    private var confirmationCallback: ConfirmationCallback?

    func setConfirmationCallback(_ callback: @escaping ConfirmationCallback) {
        self.confirmationCallback = callback
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let patch = arguments["patch"] as? String else {
            throw ToolError.missingParameter("patch")
        }

        // Parse the patch into operations
        let operations: [PatchOperation]
        do {
            operations = try parsePatch(patch)
        } catch {
            return ToolResult.error(toolCallId: name, error: "Patch parse error: \(error.localizedDescription)")
        }

        guard !operations.isEmpty else {
            return ToolResult.error(toolCallId: name, error: "No valid operations found in patch")
        }

        // Check for cross-directory operations and collect confirmation
        let needsConfirmation = operations.contains { op in
            !isWithinWorkingDirectory(op.path)
        }

        if needsConfirmation, let confirm = confirmationCallback {
            let pathList = operations.map { "\($0.action.rawValue): \($0.path)" }.joined(separator: "\n")
            let result = await confirm(
                "Apply Patch Confirmation",
                "About to apply patch with \(operations.count) operation(s):\n\n\(pathList)\n\nContinue?"
            )

            switch result {
            case .approved:
                break
            case .trustedForSession:
                break
            case .denied:
                return ToolResult.cancelled(toolCallId: name, reason: "User cancelled the patch")
            }
        }

        // Apply each operation
        var results: [String] = []
        var hasError = false

        for op in operations {
            let result = try await applyOperation(op)
            results.append(result)
            if result.hasPrefix("ERROR") {
                hasError = true
            }
        }

        let output = results.joined(separator: "\n")
        if hasError {
            return ToolResult.error(toolCallId: name, error: "Patch partially failed:\n\(output)")
        }

        return ToolResult.success(toolCallId: name, output: "Patch applied successfully (\(operations.count) operation(s)):\n\(output)")
    }

    // MARK: - Patch Operations

    private enum PatchAction: String {
        case add = "Add File"
        case update = "Update File"
        case delete = "Delete File"
    }

    private struct PatchOperation {
        let action: PatchAction
        let path: String
        let content: String // For add: file content; for update: raw SEARCH/REPLACE blocks; for delete: empty
    }

    private struct SearchReplaceBlock {
        let searchText: String
        let replaceText: String
    }

    // MARK: - Parser

    private func parsePatch(_ patch: String) throws -> [PatchOperation] {
        var operations: [PatchOperation] = []
        let lines = patch.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Match operation headers
            if line.hasPrefix("*** Add File:") {
                let path = String(line.dropFirst("*** Add File:".count)).trimmingCharacters(in: .whitespaces)
                var contentLines: [String] = []
                i += 1
                while i < lines.count {
                    let currentLine = lines[i]
                    if currentLine.hasPrefix("*** ") && (currentLine.contains("File:") || currentLine.contains("Delete")) {
                        break
                    }
                    contentLines.append(currentLine)
                    i += 1
                }
                operations.append(PatchOperation(action: .add, path: path, content: contentLines.joined(separator: "\n")))

            } else if line.hasPrefix("*** Update File:") {
                let path = String(line.dropFirst("*** Update File:".count)).trimmingCharacters(in: .whitespaces)
                var blockLines: [String] = []
                i += 1
                while i < lines.count {
                    let currentLine = lines[i]
                    if currentLine.hasPrefix("*** ") && (currentLine.contains("File:") || currentLine.contains("Delete")) {
                        break
                    }
                    blockLines.append(currentLine)
                    i += 1
                }
                operations.append(PatchOperation(action: .update, path: path, content: blockLines.joined(separator: "\n")))

            } else if line.hasPrefix("*** Delete File:") {
                let path = String(line.dropFirst("*** Delete File:".count)).trimmingCharacters(in: .whitespaces)
                operations.append(PatchOperation(action: .delete, path: path, content: ""))
                i += 1

            } else {
                i += 1
            }
        }

        return operations
    }

    // MARK: - Apply Operations

    private func applyOperation(_ op: PatchOperation) async throws -> String {
        switch op.action {
        case .add:
            return try await applyAdd(path: op.path, content: op.content)
        case .update:
            return try await applyUpdate(path: op.path, rawBlocks: op.content)
        case .delete:
            return try await applyDelete(path: op.path)
        }
    }

    private func applyAdd(path: String, content: String) async throws -> String {
        // 将文件写入操作移到后台线程，避免阻塞主线程/UI
        return await Task.detached(priority: .userInitiated) {
            // Check file doesn't already exist
            if FileManager.default.fileExists(atPath: path) {
                return "ERROR: File already exists, use Update instead: \(path)"
            }

            // Create parent directories
            let dir = (path as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return "ADDED: \(path)"
            } catch {
                return "ERROR: Failed to create file \(path): \(error.localizedDescription)"
            }
        }.value
    }

    private func applyDelete(path: String) async throws -> String {
        // 将文件删除操作移到后台线程，避免阻塞主线程/UI
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: path) else {
                return "ERROR: File not found: \(path)"
            }

            do {
                try FileManager.default.removeItem(atPath: path)
                return "DELETED: \(path)"
            } catch {
                return "ERROR: Failed to delete \(path): \(error.localizedDescription)"
            }
        }.value
    }

    private func applyUpdate(path: String, rawBlocks: String) async throws -> String {
        // 将文件更新操作移到后台线程，避免阻塞主线程/UI
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: path) else {
                return "ERROR: File not found: \(path)"
            }

            let content: String
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                return "ERROR: Cannot read \(path): \(error.localizedDescription)"
            }

            // Parse SEARCH/REPLACE blocks
            let blocks = self.parseSearchReplaceBlocks(rawBlocks)
            guard !blocks.isEmpty else {
                return "ERROR: No valid SEARCH/REPLACE blocks found for \(path)"
            }

            // Apply each block sequentially
            var currentContent = content
            var appliedCount = 0

            for block in blocks {
                let components = currentContent.components(separatedBy: block.searchText)
                let matchCount = components.count - 1

                if matchCount == 0 {
                    return "ERROR: SEARCH text not found in \(path). Text: \(String(block.searchText.prefix(100)))..."
                }

                if matchCount > 1 {
                    return "ERROR: SEARCH text found \(matchCount) times in \(path), must be unique. Text: \(String(block.searchText.prefix(100)))..."
                }

                currentContent = currentContent.replacingOccurrences(of: block.searchText, with: block.replaceText)
                appliedCount += 1
            }

            // Write back
            do {
                try currentContent.write(toFile: path, atomically: true, encoding: .utf8)
                return "UPDATED: \(path) (\(appliedCount) replacement(s))"
            } catch {
                return "ERROR: Failed to write \(path): \(error.localizedDescription)"
            }
        }.value
    }

    private func parseSearchReplaceBlocks(_ raw: String) -> [SearchReplaceBlock] {
        var blocks: [SearchReplaceBlock] = []
        let lines = raw.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "<<<<<<< SEARCH" {
                var searchLines: [String] = []
                i += 1
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "=======" {
                    searchLines.append(lines[i])
                    i += 1
                }

                if i < lines.count {
                    i += 1 // skip =======
                    var replaceLines: [String] = []
                    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != ">>>>>>> REPLACE" {
                        replaceLines.append(lines[i])
                        i += 1
                    }

                    let searchText = searchLines.joined(separator: "\n")
                    let replaceText = replaceLines.joined(separator: "\n")
                    if !searchText.isEmpty {
                        blocks.append(SearchReplaceBlock(searchText: searchText, replaceText: replaceText))
                    }
                }
            }
            i += 1
        }

        return blocks
    }

    // MARK: - Helpers

    private func isWithinWorkingDirectory(_ path: String) -> Bool {
        guard let workDir = ToolRegistry.shared.workingDirectory else { return false }
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let resolvedWorkDir = URL(fileURLWithPath: workDir).resolvingSymlinksInPath().path
        return resolvedPath.hasPrefix(resolvedWorkDir)
    }
}
