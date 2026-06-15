import Foundation

class ToolRegistry {
    static let shared = ToolRegistry()

    /// The user-selected working directory for tool execution
    var workingDirectory: String?

    private var tools: [String: Tool] = [:]

    private init() {
        registerDefaultTools()
    }

    private func registerDefaultTools() {
        let shellTool = ShellTool()
        let fileReadTool = FileReadTool()
        let fileWriteTool = FileWriteTool()
        let editFileTool = EditFileTool()
        let applyPatchTool = ApplyPatchTool()
        let searchFilesTool = SearchFilesTool()
        let findFilesTool = FindFilesTool()
        let listDirectoryTool = ListDirectoryTool()

        register(shellTool)
        register(fileReadTool)
        register(fileWriteTool)
        register(editFileTool)
        register(applyPatchTool)
        register(searchFilesTool)
        register(findFilesTool)
        register(listDirectoryTool)
    }

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    func getTool(name: String) -> Tool? {
        return tools[name]
    }

    func getAllTools() -> [Tool] {
        return Array(tools.values)
    }

    func getToolDefinitions() -> [[String: Any]] {
        return tools.values.map { tool in
            var properties: [String: Any] = [:]
            var required: [String] = []

            for (key, param) in tool.parameters {
                properties[key] = [
                    "type": param.type,
                    "description": param.description
                ]
                if param.required {
                    required.append(key)
                }
            }

            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": required
                    ]
                ]
            ]
        }
    }

    func executeTool(name: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let tool = tools[name] else {
            return ToolResult.error(toolCallId: name, error: "未知工具: \(name)")
        }

        return try await tool.execute(arguments: arguments)
    }

    // MARK: - Setup Confirmation Callbacks

    func setupConfirmationCallbacks(callback: @escaping ConfirmationCallback) {
        if let shellTool = tools["execute_command"] as? ShellTool {
            shellTool.setConfirmationCallback(callback)
        }
        if let fileReadTool = tools["read_file"] as? FileReadTool {
            fileReadTool.setConfirmationCallback(callback)
        }
        if let fileWriteTool = tools["write_file"] as? FileWriteTool {
            fileWriteTool.setConfirmationCallback(callback)
        }
        if let editFileTool = tools["edit_file"] as? EditFileTool {
            editFileTool.setConfirmationCallback(callback)
        }
        if let applyPatchTool = tools["apply_patch"] as? ApplyPatchTool {
            applyPatchTool.setConfirmationCallback(callback)
        }
    }

    // MARK: - Trust Management

    func addTrustedCommand(_ command: String) {
        if let shellTool = tools["execute_command"] as? ShellTool {
            shellTool.addTrustedCommand(command)
        }
    }

    func addTrustedPath(_ path: String) {
        if let fileWriteTool = tools["write_file"] as? FileWriteTool {
            fileWriteTool.addTrustedPath(path)
        }
    }
}
