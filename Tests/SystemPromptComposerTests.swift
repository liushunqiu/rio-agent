import XCTest
@testable import RioAgent

final class SystemPromptComposerTests: XCTestCase {
    func testSingleAgentBuiltInPromptReceivesLayeredSections() {
        let composed = SystemPromptComposer.compose(
            basePrompt: AIConfiguration.defaultSingleAgentSystemPrompt,
            scope: .singleAgent,
            availableTools: ToolRegistry.shared.getAllTools()
        )

        XCTAssertTrue(composed.contains("Evidence policy:"))
        XCTAssertTrue(composed.contains("Available tools"))
        XCTAssertTrue(composed.contains("read_file"))
        XCTAssertTrue(composed.contains("Markdown fenced code blocks"))
    }

    func testCustomPromptRemainsUnchanged() {
        let prompt = "custom prompt"
        let composed = SystemPromptComposer.compose(
            basePrompt: prompt,
            scope: .singleAgent,
            availableTools: ToolRegistry.shared.getAllTools()
        )

        XCTAssertEqual(composed, prompt)
    }

    func testChineseWorkerPromptUsesChineseLayerText() {
        let composed = SystemPromptComposer.compose(
            basePrompt: MultiAgentConfig.defaultCodePrompt,
            scope: .worker(.code),
            availableTools: ToolRegistry.shared.getAllTools()
        )

        XCTAssertTrue(composed.contains("证据规则："))
        XCTAssertTrue(composed.contains("可用工具"))
        XCTAssertTrue(composed.contains("Markdown 代码块"))
    }

    func testRouterPromptReceivesStrictJsonReminder() {
        let composed = SystemPromptComposer.compose(
            basePrompt: RouterConfig.defaultPrompt,
            scope: .router,
            availableTools: []
        )

        XCTAssertTrue(composed.contains("路由输出约定："))
        XCTAssertTrue(composed.contains("只输出严格 JSON"))
    }
}
