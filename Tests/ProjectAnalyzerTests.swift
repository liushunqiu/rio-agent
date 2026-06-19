import XCTest
@testable import RioAgent

final class ProjectAnalyzerTests: XCTestCase {
    func testDetectsSwiftPackageExecutableWithNestedMainSwift() throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write(
            """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Tool", targets: [.executableTarget(name: "Tool")])
            """,
            to: tempDir.appendingPathComponent("Package.swift")
        )
        try write("print(\"hello\")", to: tempDir.appendingPathComponent("Sources/Tool/main.swift"))

        let info = ProjectAnalyzer.analyzeProject(at: tempDir.path)

        guard case .cliTool = info.type else {
            return XCTFail("Expected nested Sources/.../main.swift to classify the package as a CLI tool.")
        }
        XCTAssertTrue(info.languages.contains("Swift"))
        XCTAssertTrue(info.buildSystems.contains("Swift Package Manager"))
    }

    func testParsesCompactPackageJSONDependencySections() throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write(
            #"{"dependencies":{"react":"18.2.0"},"devDependencies":{"vitest":"^1.0.0"},"peerDependencies":{"typescript":">=5"}}"#,
            to: tempDir.appendingPathComponent("package.json")
        )

        let info = ProjectAnalyzer.analyzeProject(at: tempDir.path)

        XCTAssertTrue(info.dependencies.contains { $0.name == "react" && $0.version == "18.2.0" && $0.type == .direct })
        XCTAssertTrue(info.dependencies.contains { $0.name == "vitest" && $0.version == "^1.0.0" && $0.type == .dev })
        XCTAssertTrue(info.dependencies.contains { $0.name == "typescript" && $0.version == ">=5" && $0.type == .peer })
    }

    func testProjectAnalysisSkipsGeneratedAndDependencyDirectories() throws {
        let tempDir = try makeTemporaryWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try write("let app = true", to: tempDir.appendingPathComponent("Sources/App/App.swift"))
        try write("func testApp() {}", to: tempDir.appendingPathComponent("Tests/AppTests.swift"))
        try write("print('generated')", to: tempDir.appendingPathComponent("dist/generated_test.py"))
        try write("console.log('dependency')", to: tempDir.appendingPathComponent("node_modules/pkg/pkg_test.js"))

        let info = ProjectAnalyzer.analyzeProject(at: tempDir.path)

        XCTAssertTrue(info.languages.contains("Swift"))
        XCTAssertFalse(info.languages.contains("Python"))
        XCTAssertFalse(info.testFiles.contains { $0.contains("dist/") || $0.contains("node_modules/") })
        XCTAssertTrue(info.testFiles.contains("Tests/AppTests.swift"))
    }

    private func makeTemporaryWorkingDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-project-analyzer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
