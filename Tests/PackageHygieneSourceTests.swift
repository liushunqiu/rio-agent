import XCTest

final class PackageHygieneSourceTests: XCTestCase {
    func testPackageExcludesDoNotReferenceMissingLocalArtifacts() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: repoRoot.appendingPathComponent("Package.swift"))
        let gitignore = try String(contentsOf: repoRoot.appendingPathComponent(".gitignore"))

        XCTAssertFalse(package.contains("\"2.png\""))
        XCTAssertFalse(package.contains("\"j.png\""))
        XCTAssertFalse(package.contains("\"wangxinvpn.vpn\""))
        XCTAssertTrue(
            gitignore.contains("*.vpn"),
            "Future local VPN config files should stay out of git status."
        )
    }

    func testRemovedRootImagesAreNotReferencedBySourceOrDocs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pathsToScan = [
            "App", "Views", "ViewModels", "Agent", "Services",
            "Tools", "Models", "Utils", "Theme",
            "README.md", "AGENT.md", "CLAUDE.md", "project.yml"
        ]
        var combined = ""

        for relativePath in pathsToScan {
            let url = repoRoot.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
                while let fileURL = enumerator?.nextObject() as? URL {
                    guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                        continue
                    }
                    combined += (try? String(contentsOf: fileURL)) ?? ""
                }
            } else {
                combined += try String(contentsOf: url)
            }
        }

        XCTAssertFalse(combined.contains("2.png"))
        XCTAssertFalse(combined.contains("j.png"))
    }
}
