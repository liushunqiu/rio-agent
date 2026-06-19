import XCTest

final class AgentMemoryPersistenceSourceTests: XCTestCase {
    func testAgentMemoryCanUseInjectedStorageAndMarkdownPath() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentMemory.swift"))

        XCTAssertTrue(
            source.contains("private let userDefaults: UserDefaults")
                && source.contains("private let memoryKey: String")
                && source.contains("private let customMarkdownURL: URL?"),
            "AgentMemory should keep both structured memory storage and MEMORY.md path injectable."
        )
        XCTAssertTrue(
            source.contains("init(\n        userDefaults: UserDefaults = .standard,\n        memoryKey: String = \"agent_long_term_memory\",\n        markdownURL: URL? = nil\n    )"),
            "The app should preserve default memory persistence while tests can provide isolated storage."
        )
        XCTAssertTrue(
            source.contains("guard let data = userDefaults.data(forKey: memoryKey) else {")
                && source.contains("userDefaults.set(data, forKey: memoryKey)"),
            "Long-term memory should consistently use the injected UserDefaults store."
        )
        XCTAssertTrue(
            source.contains("if let customMarkdownURL {\n            return customMarkdownURL.path\n        }"),
            "MEMORY.md should resolve to the injected file path when tests or previews provide one."
        )
    }

    func testAgentEngineAndMemoryTestsUseIsolatedMemoryFactories() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engineSource = try String(contentsOf: repoRoot.appendingPathComponent("Agent/AgentEngine.swift"))
        let supportSource = try String(contentsOf: repoRoot.appendingPathComponent("Tests/AgentMemoryTestSupport.swift"))
        let engineTests = try String(contentsOf: repoRoot.appendingPathComponent("Tests/AgentEngineRegressionTests.swift"))
        let memoryTests = try String(contentsOf: repoRoot.appendingPathComponent("Tests/AgentMemoryMarkdownTests.swift"))
        let toolTests = try String(contentsOf: repoRoot.appendingPathComponent("Tests/ToolExecutorTests.swift"))

        XCTAssertTrue(
            engineSource.contains("let memory: AgentMemory")
                && engineSource.contains("private let userDefaults: UserDefaults")
                && engineSource.contains("private let configurationKey: String")
                && engineSource.contains("private let multiAgentConfigKey: String")
                && engineSource.contains("memory: AgentMemory? = nil")
                && engineSource.contains("self.memory = memory ?? AgentMemory()"),
            "AgentEngine should accept injected memory and configuration storage so tests do not create real user files or settings."
        )
        XCTAssertTrue(
            engineSource.contains("userDefaults: UserDefaults = .standard")
                && engineSource.contains("configurationKey: String = \"ai_configuration\"")
                && engineSource.contains("multiAgentConfigKey: String = \"multi_agent_configuration\""),
            "The app should preserve the existing runtime configuration defaults while tests can provide isolated keys."
        )
        XCTAssertTrue(
            engineSource.contains("userDefaults.set(data, forKey: configurationKey)")
                && engineSource.contains("guard let data = userDefaults.data(forKey: configurationKey) else")
                && engineSource.contains("userDefaults.set(data, forKey: multiAgentConfigKey)")
                && engineSource.contains("guard let data = userDefaults.data(forKey: multiAgentConfigKey) else"),
            "AgentEngine configuration persistence should consistently use the injected UserDefaults store."
        )
        XCTAssertTrue(
            supportSource.contains("func makeIsolatedAgentMemory(testCase: XCTestCase? = nil) -> AgentMemory")
                && supportSource.contains("AgentMemory(\n        userDefaults: defaults,")
                && supportSource.contains("markdownURL: markdownURL"),
            "Tests should share a helper that creates isolated UserDefaults and MEMORY.md storage."
        )
        XCTAssertTrue(
            supportSource.contains("userDefaults: defaults")
                && supportSource.contains("configurationKey: \"ai_configuration_\\(UUID().uuidString)\"")
                && supportSource.contains("multiAgentConfigKey: \"multi_agent_configuration_\\(UUID().uuidString)\""),
            "AgentEngine tests should isolate runtime configuration persistence from real app settings."
        )
        XCTAssertTrue(
            engineTests.contains("makeIsolatedAgentEngine(testCase: self)")
                && memoryTests.contains("makeIsolatedAgentMemory(testCase: self)")
                && toolTests.contains("makeIsolatedAgentMemory(testCase: self)"),
            "Memory-touching tests should avoid direct AgentMemory or AgentEngine construction."
        )
    }
}
