import Foundation

enum FileReferenceParser {
    private static let marker = "@file:"

    static func fileReferences(in text: String) -> [String] {
        var seen = Set<String>()
        var references: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(marker) else { continue }

            let path = String(trimmed.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !seen.contains(path) else { continue }

            seen.insert(path)
            references.append(path)
        }

        return references
    }

    static func appendingReference(to text: String, path: String) -> String {
        var cleaned = removingDanglingAt(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let target = "\(marker)\(path)"
        let remainingLines = text.components(separatedBy: .newlines).filter { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines) != target
        }
        return remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removingReferencesOutsideWorkingDirectory(from text: String, workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return removingAllReferences(from: text)
        }

        let remainingLines = text.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(marker) else { return true }

            let path = String(trimmed.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
}
