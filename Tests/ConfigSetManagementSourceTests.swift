import XCTest

final class ConfigSetManagementSourceTests: XCTestCase {
    func testConfigEditorSaveGuidanceIsSpecificAndDiscoverable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains(".help(canSave ? \"保存模型配置\" : readinessMessage)"),
            "A disabled save button should expose the same readiness reason as the visible status row."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"模型名称\")"),
            "The editor should report a missing model config name explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"API Key\")"),
            "Hosted provider configs should report a missing API Key explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"API 端点\")"),
            "OpenAI-compatible configs should report a missing API endpoint explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.append(\"模型标识\")"),
            "All config types should report a missing model identifier explicitly."
        )
        XCTAssertTrue(
            source.contains("missingFields.joined(separator: \"、\")"),
            "Readiness guidance should list only the fields that are currently missing."
        )
    }

    func testConfigRowsTruncateLongNamesBeforeActionControls() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("Text(configSet.name)\n                    .font(.system(size: 13, weight: .semibold))\n                    .foregroundColor(Theme.textPrimary)\n                    .lineLimit(1)\n                    .truncationMode(.middle)"),
            "Long config names should not push status text or edit/delete controls out of the row."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.name)"),
            "Truncated config names should still expose the full name on hover."
        )
        XCTAssertTrue(
            source.contains("Text(configSet.model)\n                            .font(.system(size: 10, design: .monospaced))\n                            .foregroundColor(Theme.textSecondary)\n                            .lineLimit(1)\n                            .truncationMode(.middle)"),
            "Long model identifiers should not stretch config rows."
        )
        XCTAssertTrue(
            source.contains(".help(configSet.model)"),
            "Truncated model identifiers should remain inspectable."
        )
        XCTAssertTrue(
            source.contains(".help(readinessHint)"),
            "Readiness issues should remain discoverable when the row is compact."
        )
    }

    func testCompatibleConfigAPIKeyStatusIsOptionalNotError() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Views/ConfigSetManagementView.swift"))

        XCTAssertTrue(
            source.contains("private var apiKeyStatusText: String"),
            "The API Key status should be derived from provider-specific readiness rules."
        )
        XCTAssertTrue(
            source.contains("case .openAICompatible:\n            return \"可选\""),
            "OpenAI-compatible configs should not show an empty API Key as a red missing requirement."
        )
        XCTAssertTrue(
            source.contains("case .claude, .openAI:\n            return \"未配置\""),
            "Hosted providers should still clearly require an API Key."
        )
        XCTAssertTrue(
            source.contains("OpenAI Compatible 端点可按服务需要选择是否填写 API Key。"),
            "The optional API Key state should explain why it differs from hosted providers."
        )
    }
}
