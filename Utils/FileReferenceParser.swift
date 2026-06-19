import Foundation

enum FileReferenceParser {
    private static let marker = "@file:"

    private struct ReferenceEntry {
        let rawPath: String
        let normalizedPath: String
    }

    static func fileReferences(in text: String) -> [String] {
        var seen = Set<String>()
        var references: [String] = []

        for line in text.components(separatedBy: .newlines) {
            for entry in referenceEntries(in: line) where !seen.contains(entry.normalizedPath) {
                seen.insert(entry.normalizedPath)
                references.append(entry.normalizedPath)
            }
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

        let remainingLines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let entries = referenceEntries(in: line)
            guard !entries.isEmpty else { return line }

            let remainingEntries = entries.filter { $0.normalizedPath != target }
            guard remainingEntries.count != entries.count else { return line }
            guard !remainingEntries.isEmpty else { return nil }

            return renderedReferenceLines(for: remainingEntries)
        }
        return remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removingReferencesOutsideWorkingDirectory(from text: String, workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return removingAllReferences(from: text)
        }

        let remainingLines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let entries = referenceEntries(in: line)
            guard !entries.isEmpty else {
                return line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(marker) ? nil : line
            }

            let remainingEntries = entries.filter {
                PathSecurity.isWithinDirectory($0.normalizedPath, workingDirectory: workingDirectory)
            }
            guard !remainingEntries.isEmpty else { return nil }
            guard remainingEntries.count != entries.count else { return line }

            return renderedReferenceLines(for: remainingEntries)
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

    private static func referenceEntries(in line: String) -> [ReferenceEntry] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(marker) else { return [] }

        return rawReferenceSegments(in: trimmed).compactMap { segment in
            let rawPath = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalizedPath = normalizedReferencePath(rawPath) else { return nil }
            return ReferenceEntry(rawPath: rawPath, normalizedPath: normalizedPath)
        }
    }

    private static func rawReferenceSegments(in trimmedLine: String) -> [Substring] {
        var markerRanges: [Range<String.Index>] = []
        var searchStart = trimmedLine.startIndex

        while let range = trimmedLine.range(of: marker, range: searchStart..<trimmedLine.endIndex) {
            if range.lowerBound == trimmedLine.startIndex
                || trimmedLine[trimmedLine.index(before: range.lowerBound)].isWhitespace {
                markerRanges.append(range)
            }
            searchStart = range.upperBound
        }

        return markerRanges.enumerated().map { index, range in
            let segmentStart = range.upperBound
            let segmentEnd = index + 1 < markerRanges.count
                ? markerRanges[index + 1].lowerBound
                : trimmedLine.endIndex
            return trimmedLine[segmentStart..<segmentEnd]
        }
    }

    private static func renderedReferenceLines(for entries: [ReferenceEntry]) -> String {
        entries.map { "\(marker)\($0.rawPath)" }.joined(separator: "\n")
    }

    private static func normalizedReferencePath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath else { return nil }
        return PathSecurity.normalizedPath(expanded)
    }
}
