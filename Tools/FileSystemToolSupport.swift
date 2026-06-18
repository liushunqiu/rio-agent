import Darwin
import Foundation

enum FileSystemToolSupport {
    enum ScopedPathResolution {
        case success(String)
        case failure(ToolResult)
    }

    static let skippedDirectoryNames: Set<String> = [
        ".next",
        ".build",
        ".git",
        ".nuxt",
        ".swiftpm",
        ".venv",
        "__pycache__",
        "coverage",
        "DerivedData",
        "dist",
        "node_modules",
        "venv"
    ]

    static func resolvedScopedPath(
        from arguments: [String: Any],
        parameterName: String = "path",
        toolName: String
    ) -> ScopedPathResolution {
        let explicitPath = arguments[parameterName] as? String
        guard let path = explicitPath ?? ToolRegistry.shared.workingDirectory else {
            return .failure(ToolResult.error(
                toolCallId: toolName,
                error: "\(parameterName) is required when no working directory is selected"
            ))
        }

        if explicitPath != nil, !PathSecurity.isAbsolutePath(path) {
            return .failure(ToolResult.error(
                toolCallId: toolName,
                error: "\(parameterName) must be an absolute path. Resolve relative paths from the working directory before calling \(toolName)."
            ))
        }

        return .success(PathSecurity.normalizedPath(path))
    }

    static func shouldSkipDirectory(_ url: URL) -> Bool {
        skippedDirectoryNames.contains(url.lastPathComponent)
    }

    static func sortedDirectoryContents(at directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsPackageDescendants]
        )
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func recursiveFiles(
        under root: URL,
        matching filePattern: String? = nil,
        limit: Int? = nil
    ) throws -> [URL] {
        let rootPath = root.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
            throw ToolError.executionFailed("Path does not exist: \(rootPath)")
        }

        if !isDirectory.boolValue {
            guard filePattern == nil || matchesGlob(root.lastPathComponent, pattern: filePattern!) else {
                return []
            }
            return [root]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            throw ToolError.executionFailed("Unable to enumerate path: \(rootPath)")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values?.isDirectory == true {
                if shouldSkipDirectory(url) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            if let filePattern, !matchesGlob(url.lastPathComponent, pattern: filePattern) {
                continue
            }

            files.append(url)
            if let limit, files.count >= limit {
                break
            }
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func matchesGlob(_ value: String, pattern: String) -> Bool {
        fnmatch(pattern, value, 0) == 0
    }

    static func matchesPathGlob(_ url: URL, root: URL, pattern: String) -> Bool {
        if !pattern.contains("/") {
            return matchesGlob(url.lastPathComponent, pattern: pattern)
        }

        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relativePath: String
        if filePath == rootPath {
            relativePath = url.lastPathComponent
        } else if filePath.hasPrefix(rootPath + "/") {
            relativePath = String(filePath.dropFirst(rootPath.count + 1))
        } else {
            relativePath = filePath
        }

        guard let regex = regex(forGlobPattern: pattern) else {
            return false
        }

        return regex.firstMatch(
            in: relativePath,
            range: NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
        ) != nil
    }

    private static func regex(forGlobPattern pattern: String) -> NSRegularExpression? {
        var regex = "^"
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let char = pattern[index]
            let nextIndex = pattern.index(after: index)

            if char == "*" {
                if nextIndex < pattern.endIndex, pattern[nextIndex] == "*" {
                    let afterGlobstar = pattern.index(after: nextIndex)
                    if afterGlobstar < pattern.endIndex, pattern[afterGlobstar] == "/" {
                        regex += "(?:.*/)?"
                        index = pattern.index(after: afterGlobstar)
                    } else {
                        regex += ".*"
                        index = afterGlobstar
                    }
                } else {
                    regex += "[^/]*"
                    index = nextIndex
                }
            } else if char == "?" {
                regex += "[^/]"
                index = nextIndex
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(char))
                index = nextIndex
            }
        }

        regex += "$"
        return try? NSRegularExpression(pattern: regex)
    }
}
