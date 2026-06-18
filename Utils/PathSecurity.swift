import Foundation

enum PathSecurity {
    static func isAbsolutePath(_ path: String) -> Bool {
        (path as NSString).isAbsolutePath
    }

    static func normalizedPath(_ path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath

        return URL(fileURLWithPath: expandedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func isWithinDirectory(_ path: String, workingDirectory: String?) -> Bool {
        guard let workingDirectory, !workingDirectory.isEmpty else { return false }

        let resolvedPath = normalizedPath(path)
        let resolvedWorkDir = normalizedPath(workingDirectory)

        return resolvedPath == resolvedWorkDir || resolvedPath.hasPrefix(resolvedWorkDir + "/")
    }

    static func relativePath(_ path: String, from workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return path }

        let resolvedPath = normalizedPath(path)
        let resolvedWorkDir = normalizedPath(workingDirectory)

        if resolvedPath == resolvedWorkDir {
            return URL(fileURLWithPath: resolvedPath).lastPathComponent
        }

        guard resolvedPath.hasPrefix(resolvedWorkDir + "/") else {
            return path
        }

        return String(resolvedPath.dropFirst(resolvedWorkDir.count + 1))
    }
}
