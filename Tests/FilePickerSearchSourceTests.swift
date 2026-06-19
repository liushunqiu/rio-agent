import XCTest

final class FilePickerSearchSourceTests: XCTestCase {
    func testFilePickerSearchUsesDisplayedRelativePathsAndRankedResults() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("displayRelativePath(for: filePath).lowercased()"))
        XCTAssertFalse(source.contains("let relativePath = filePath.lowercased()"))
        XCTAssertTrue(source.contains("fileName.hasPrefix(query)"))
        XCTAssertTrue(source.contains("fileName.contains(query)"))
        XCTAssertTrue(source.contains("relativePath.hasPrefix(query)"))
        XCTAssertTrue(source.contains("relativePath.contains(query)"))
    }

    func testFilePickerWhitespaceSearchBehavesLikeEmptySearch() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("private var trimmedSearchText: String")
                && source.contains("searchText.trimmingCharacters(in: .whitespacesAndNewlines)"),
            "File picker search state should normalize whitespace before deciding whether a search is active."
        )
        XCTAssertTrue(
            source.contains("private var isSearching: Bool {\n        !trimmedSearchText.isEmpty\n    }"),
            "Whitespace-only search text should behave like the empty-search state."
        )
        XCTAssertTrue(
            source.contains("if !isSearching && !recentFiles.isEmpty"),
            "Recent files should remain visible for whitespace-only search input."
        )
        XCTAssertTrue(
            source.contains("guard isSearching else { return files }")
                && source.contains("let query = trimmedSearchText.lowercased()"),
            "Filtering should use the normalized search text."
        )
    }

    func testFilePickerLoadedFilesSortByDisplayedRelativePath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("PathSecurity.relativePath($0, from: workingDirectory)"))
        XCTAssertTrue(source.contains("localizedStandardCompare(PathSecurity.relativePath($1, from: workingDirectory))"))
        XCTAssertFalse(source.contains("files = filePaths.sorted()"))
    }

    func testFilePickerRowsExposeFullPathsWhenLabelsAreTruncated() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("helpText: workingDirectory"),
            "The file picker workspace summary should expose the full selected directory."
        )
        XCTAssertTrue(
            source.contains(".help(helpText ?? value)"),
            "Picker summary pills should keep line-limited values discoverable."
        )
        XCTAssertTrue(
            source.contains(".help(filePath)"),
            "File picker rows should expose the absolute file path when file names or relative paths are truncated."
        )
        XCTAssertTrue(
            source.contains(".truncationMode(.middle)"),
            "Long file paths should preserve both leading and trailing context in narrow rows."
        )
    }

    func testFilePickerReturnKeyDefaultsToFirstVisibleResult() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("guard !filteredFiles.isEmpty else { return .ignored }"),
            "Return should stay inert only when the filtered list is genuinely empty."
        )
        XCTAssertTrue(
            source.contains("let idx = min(selectedFileIndex ?? 0, filteredFiles.count - 1)"),
            "When nothing is explicitly highlighted, return should select the first visible result instead of forcing an extra arrow-key step."
        )
    }

    func testFilePickerIgnoresStaleDirectoryLoads() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("@State private var activeLoadRequestID: UUID?"),
            "File picker loads should track the latest directory enumeration request."
        )
        XCTAssertTrue(
            source.contains("let requestID = UUID()")
                && source.contains("activeLoadRequestID = requestID"),
            "Each file picker load should publish a fresh request id before starting background enumeration."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: workingDirectory) { _, _ in\n            loadFiles()\n        }"),
            "Changing the working directory while the picker is open should trigger a fresh load."
        )
        XCTAssertTrue(
            source.contains("guard activeLoadRequestID == requestID, self.workingDirectory == workingDirectory else { return }"),
            "Background file enumeration should not overwrite UI state after a newer load or directory change."
        )
        XCTAssertTrue(
            source.contains("files = []")
                && source.contains("selectedFileIndex = nil")
                && source.contains("isLoading = true"),
            "Starting a new picker load should clear stale results and keyboard selection immediately."
        )
    }

    func testRecentFilesAreScopedByWorkspaceWithLegacyFallback() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/NewChatPage.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(
            source.contains("private let legacyRecentFilesKey = \"recent_files_picker\""),
            "The old recent-file key should remain available as a migration fallback."
        )
        XCTAssertTrue(
            source.contains("private var recentFilesKey: String")
                && source.contains("Data(PathSecurity.normalizedPath(workingDirectory).utf8)")
                && source.contains("return \"\\(legacyRecentFilesKey).\\(workspaceKey)\""),
            "Recent file storage should use a stable key derived from the current workspace."
        )
        XCTAssertTrue(
            source.contains("private var storedRecentFiles: [String]")
                && source.contains("guard scopedFiles.isEmpty, recentFilesKey != legacyRecentFilesKey else")
                && source.contains("UserDefaults.standard.stringArray(forKey: legacyRecentFilesKey)"),
            "Empty workspace-scoped history should fall back to legacy global recents for migration."
        )
        XCTAssertTrue(
            source.contains("private func migrateLegacyRecentFilesIfNeeded()")
                && source.contains("PathSecurity.isWithinDirectory(normalizedPath, workingDirectory: workingDirectory)")
                && source.contains("UserDefaults.standard.set(migratedFiles, forKey: recentFilesKey)")
                && source.contains("migrateLegacyRecentFilesIfNeeded()"),
            "Opening a workspace should migrate valid legacy recents into the workspace-scoped key instead of relying on global fallback forever."
        )
        XCTAssertTrue(
            source.contains("var saved = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []"),
            "Recording a recent file should write into the workspace-scoped key."
        )
    }
}
