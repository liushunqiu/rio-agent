import Foundation

enum PathSecurity {
    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
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
}
