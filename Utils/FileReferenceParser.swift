import Foundation

extension Character {
    var isNewline: Bool {
        self == "\n" || self == "\r" || self == "\r\n"
    }
}

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
        // 移除末尾的 @ 触发符，并清理用户在 @ 后可能误输入的文字
        var cleaned = removingFilePickerTrigger(from: text)
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

    /// 移除文件选择器触发符（末尾的 @ 或 @ 后跟随的文字）
    /// 例如：
    /// - "@" -> ""
    /// - "hello @" -> "hello"
    /// - "hello @你好" -> "hello"
    /// - "@你好" -> ""
    private static func removingFilePickerTrigger(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last else { return text }

        // 查找最后一行中最后一个触发 @ 的位置（@ 前必须是空格、换行或字符串开头）
        var triggerIndex: String.Index?

        for i in lastLine.indices {
            let char = lastLine[i]
            if char == "@" {
                // 检查 @ 前面是否是合法的触发位置
                if i == lastLine.startIndex {
                    // @ 在行首
                    triggerIndex = i
                } else {
                    let beforeAt = lastLine[lastLine.index(before: i)]
                    if beforeAt.isWhitespace || beforeAt.isNewline {
                        // @ 前面是空格或换行
                        triggerIndex = i
                    }
                }
            }
        }

        guard let triggerIndex else {
            // 没有找到触发符，返回原文本
            return text
        }

        // 移除从触发位置到行尾的所有内容
        let cleanedLastLine = String(lastLine[..<triggerIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if lines.count == 1 {
            return cleanedLastLine
        } else {
            var result = lines.dropLast()
            if !cleanedLastLine.isEmpty {
                result.append(cleanedLastLine)
            }
            return result.joined(separator: "\n")
        }
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
