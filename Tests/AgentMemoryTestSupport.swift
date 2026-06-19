import XCTest
@testable import RioAgent

@MainActor
func makeIsolatedAgentMemory(testCase: XCTestCase? = nil) -> AgentMemory {
    let suiteName = "rio-agent-memory-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rio-agent-memory-tests-\(UUID().uuidString)", isDirectory: true)
    let markdownURL = directory.appendingPathComponent("MEMORY.md")

    if let testCase {
        testCase.addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    return AgentMemory(
        userDefaults: defaults,
        memoryKey: "agent_long_term_memory_\(UUID().uuidString)",
        markdownURL: markdownURL
    )
}

@MainActor
func makeIsolatedAgentEngine(
    testCase: XCTestCase? = nil,
    configuration: AIConfiguration = AIConfiguration(),
    multiAgentConfig: MultiAgentConfig = MultiAgentConfig()
) -> AgentEngine {
    let suiteName = "rio-agent-engine-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    if let testCase {
        testCase.addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    return AgentEngine(
        configuration: configuration,
        multiAgentConfig: multiAgentConfig,
        userDefaults: defaults,
        configurationKey: "ai_configuration_\(UUID().uuidString)",
        multiAgentConfigKey: "multi_agent_configuration_\(UUID().uuidString)",
        memory: makeIsolatedAgentMemory(testCase: testCase)
    )
}
