import XCTest
@testable import RioAgent

final class FileReferenceParserTests: XCTestCase {
    func testAppendingReferenceUsesOwnLineAndRemovesDanglingAt() {
        let text = FileReferenceParser.appendingReference(
            to: "请检查这个文件 @",
            path: "/tmp/project/App.swift"
        )

        XCTAssertEqual(text, "请检查这个文件\n@file:\(PathSecurity.normalizedPath("/tmp/project/App.swift"))")
    }

    func testFileReferencesDeduplicateAndIgnoreInlineMentions() {
        let text = """
        请分析
        @file:/tmp/project/App.swift
        这里提到 @file:/tmp/project/Ignored.swift 但不是独立引用
        @file:/tmp/project/App.swift
        @file:/tmp/project/Model.swift
        """

        XCTAssertEqual(
            FileReferenceParser.fileReferences(in: text),
            [
                PathSecurity.normalizedPath("/tmp/project/App.swift"),
                PathSecurity.normalizedPath("/tmp/project/Model.swift")
            ]
        )
    }

    func testFileReferencesNormalizeAbsolutePathsBeforeDeduplication() {
        let text = """
        请分析
        @file:/tmp/project/../project/App.swift
        @file:/tmp/project/App.swift
        @file:~/Documents/../Documents/Notes.md
        """

        XCTAssertEqual(
            FileReferenceParser.fileReferences(in: text),
            [
                PathSecurity.normalizedPath("/tmp/project/App.swift"),
                PathSecurity.normalizedPath("~/Documents/Notes.md")
            ]
        )
    }

    func testFileReferencesIgnoreRelativePaths() {
        let text = """
        请分析
        @file:Sources/App.swift
        @file:./Sources/Model.swift
        @file:/tmp/project/App.swift
        """

        XCTAssertEqual(
            FileReferenceParser.fileReferences(in: text),
            [PathSecurity.normalizedPath("/tmp/project/App.swift")]
        )
    }

    func testRemovingReferenceOnlyRemovesMatchingReferenceLine() {
        let text = """
        请分析
        @file:/tmp/project/App.swift
        @file:/tmp/project/Model.swift
        """

        XCTAssertEqual(
            FileReferenceParser.removingReference(from: text, path: "/tmp/project/App.swift"),
            "请分析\n@file:/tmp/project/Model.swift"
        )
    }

    func testRemovingReferenceRemovesEquivalentNormalizedReferenceLine() {
        let text = """
        请分析
        @file:/tmp/project/../project/App.swift
        @file:/tmp/project/Model.swift
        """

        XCTAssertEqual(
            FileReferenceParser.removingReference(from: text, path: "/tmp/project/App.swift"),
            "请分析\n@file:/tmp/project/Model.swift"
        )
    }

    func testAppendingReferenceNormalizesPathAndSkipsInvalidPaths() {
        XCTAssertEqual(
            FileReferenceParser.appendingReference(
                to: "请检查这个文件 @",
                path: "/tmp/project/../project/App.swift "
            ),
            "请检查这个文件\n@file:\(PathSecurity.normalizedPath("/tmp/project/App.swift"))"
        )

        XCTAssertEqual(
            FileReferenceParser.appendingReference(to: "请检查这个文件 @", path: "Sources/App.swift"),
            "请检查这个文件"
        )
    }

    func testRemovingReferencesOutsideWorkingDirectoryKeepsOnlyMatchingPaths() {
        let text = """
        请分析
        @file:/tmp/project/App.swift
        @file:/tmp/other/Legacy.swift
        @file:/tmp/project/Sources/Model.swift
        """

        XCTAssertEqual(
            FileReferenceParser.removingReferencesOutsideWorkingDirectory(
                from: text,
                workingDirectory: "/tmp/project"
            ),
            "请分析\n@file:/tmp/project/App.swift\n@file:/tmp/project/Sources/Model.swift"
        )
    }

    func testRemovingReferencesOutsideWorkingDirectoryDropsRelativeReferenceLines() {
        let text = """
        请分析
        @file:Sources/App.swift
        @file:/tmp/project/App.swift
        """

        XCTAssertEqual(
            FileReferenceParser.removingReferencesOutsideWorkingDirectory(
                from: text,
                workingDirectory: "/tmp/project"
            ),
            "请分析\n@file:/tmp/project/App.swift"
        )
    }

    func testRemovingReferencesOutsideWorkingDirectoryClearsAllWhenWorkspaceIsMissing() {
        let text = """
        请分析
        @file:/tmp/project/App.swift
        @file:/tmp/project/Model.swift
        """

        XCTAssertEqual(
            FileReferenceParser.removingReferencesOutsideWorkingDirectory(
                from: text,
                workingDirectory: nil
            ),
            "请分析"
        )
    }
}
