import XCTest
@testable import RioAgent

final class MultiFileCoordinatorTests: XCTestCase {
    func testAnalyzeFileRelationsResetsStateBetweenProjects() throws {
        let firstProject = try makeTemporaryProject()
        let secondProject = try makeTemporaryProject()
        defer {
            try? FileManager.default.removeItem(at: firstProject)
            try? FileManager.default.removeItem(at: secondProject)
        }

        try write("struct CheckoutService {}", to: firstProject.appendingPathComponent("Sources/CheckoutService.swift"))
        try write("final class CheckoutServiceTest {}", to: firstProject.appendingPathComponent("Sources/CheckoutServiceTest.swift"))
        try write("struct InventoryService {}", to: secondProject.appendingPathComponent("Sources/InventoryService.swift"))

        let coordinator = MultiFileCoordinator()
        coordinator.analyzeFileRelations(in: firstProject.path)

        let firstReport = coordinator.generateRelationReport(for: "Sources/CheckoutService.swift")
        XCTAssertTrue(firstReport.contains("CheckoutServiceTest.swift"))

        coordinator.analyzeFileRelations(in: secondProject.path)

        let staleReport = coordinator.generateRelationReport(for: "Sources/CheckoutService.swift")
        XCTAssertTrue(staleReport.contains("未发现文件关系"))
    }

    func testAnalyzeFileRelationsSkipsGeneratedDirectories() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        try write("struct AppFeature {}", to: project.appendingPathComponent("Sources/AppFeature.swift"))
        try write("struct GeneratedFeature {}", to: project.appendingPathComponent("DerivedData/GeneratedFeature.swift"))

        let coordinator = MultiFileCoordinator()
        coordinator.analyzeFileRelations(in: project.path)

        let changes = coordinator.analyzeRenameImpact(
            oldName: "GeneratedFeature",
            newName: "RenamedFeature",
            in: project.path
        )

        XCTAssertTrue(changes.isEmpty)
    }

    private func makeTemporaryProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rio-agent-mfc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
