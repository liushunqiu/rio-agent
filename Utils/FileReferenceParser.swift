import Foundation

enum FileReferenceParser {
    private static let marker = "@file:"

    static func fileReferences(in text: String) -> [String] {
        var seen = Set<String>()
        var references: [String] = []

        for line in text.components(separatedBy: .newlines) {
            guard let path = referencePath(in: line) else { continue }
            guard !path.isEmpty, !seen.contains(path) else { continue }

            seen.insert(path)
            references.append(path)
        }

        return references
    }

    static func appendingReference(to text: String, path: String) -> String {
        var cleaned = removingDanglingAt(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = normalizedReferencePath(path) else { return cleaned }
        let reference = "\(marker)\(path)"

        if fileReferences(in: cleaned).contains(path) {
            return cleaned
        }

        if !cleaned.isEmpty {
            cleaned += "\n"
        }
        cleaned += reference
        return cleaned
    }

    static func removingReference(from text: String, path: String) -> String {
        guard let target = normalizedReferencePath(path) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let remainingLines = text.components(separatedBy: .newlines).filter { line in
            referencePath(in: line) != target
        }
        return remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removingReferencesOutsideWorkingDirectory(from text: String, workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return removingAllReferences(from: text)
        }

        let remainingLines = text.components(separatedBy: .newlines).filter { line in
            guard let path = referencePath(in: line) else {
                return !line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(marker)
            }
            return PathSecurity.isWithinDirectory(path, workingDirectory: workingDirectory)
        }

        return remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingAllReferences(from text: String) -> String {
        let remainingLines = text.components(separatedBy: .newlines).filter { line in
            !line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(marker)
        }
        return remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingDanglingAt(from text: String) -> String {
        guard text.hasSuffix("@") else { return text }
        return String(text.dropLast())
    }

    private static func referencePath(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(marker) else { return nil }
        return normalizedReferencePath(String(trimmed.dropFirst(marker.count)))
    }

    private static func normalizedReferencePath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath else { return nil }
        return PathSecurity.normalizedPath(expanded)
    }
}
