import XCTest
@testable import RioAgent

final class ToolRegistryTests: XCTestCase {
    func testToolDefinitionsAreReturnedInStableSortedOrder() {
        let definitions = ToolRegistry.shared.getToolDefinitions()
        let names = definitions.compactMap { definition -> String? in
            guard let function = definition["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        }

        XCTAssertEqual(names, names.sorted())
    }
}
