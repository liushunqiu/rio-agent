import XCTest
@testable import RioAgent

/// Tests that verify the fix for Router skip decision incorrectly disabling tools
/// when the model needs them.
///
/// Bug: When Router decides to skip (no tools needed), but the model attempts
/// to use tools anyway (outputting text-based tool calls), the TextToolCallSafetyNet
/// should override the Router decision and enable tools for subsequent iterations.
@MainActor
final class RouterSkipToolEnablementTests: XCTestCase {

    func testTextToolCallSafetyNetOverridesRouterSkipDecision() {
        // GIVEN: An AgentEngine with Router decision set to .skip
        let engine = makeIsolatedAgentEngine(testCase: self)

        // Set Router decision to skip
        engine.currentRouterDecision = RoutingDecision.skip(reason: "simple question")

        // WHEN: TextToolCallSafetyNet detects a text-based tool call attempt
        engine.overrideRouterSkipIfNeeded()

        // THEN: The Router decision should be overridden to process
        if case .routeToTarget(let target, _, _, _) = engine.currentRouterDecision {
            XCTAssertEqual(target, "process", "Router skip should be overridden to process")
        } else {
            XCTFail("Expected routeToTarget decision after override, got \(String(describing: engine.currentRouterDecision))")
        }
    }

    func testOverrideOnlyAffectsSkipDecisions() {
        // GIVEN: An AgentEngine with Router decision already set to process
        let engine = makeIsolatedAgentEngine(testCase: self)

        engine.currentRouterDecision = RoutingDecision.routeToTarget(
            target: "search",
            params: [:],
            confidence: 0.9,
            reasoning: "user needs search"
        )

        // WHEN: overrideRouterSkipIfNeeded is called
        engine.overrideRouterSkipIfNeeded()

        // THEN: The decision should remain unchanged
        if case .routeToTarget(let target, _, let confidence, _) = engine.currentRouterDecision {
            XCTAssertEqual(target, "search", "Non-skip decisions should not be modified")
            XCTAssertEqual(confidence, 0.9, accuracy: 0.01)
        } else {
            XCTFail("Expected original routeToTarget decision, got \(String(describing: engine.currentRouterDecision))")
        }
    }

    func testOverrideHandlesNilRouterDecision() {
        // GIVEN: An AgentEngine with no Router decision
        let engine = makeIsolatedAgentEngine(testCase: self)

        XCTAssertNil(engine.currentRouterDecision)

        // WHEN: overrideRouterSkipIfNeeded is called
        engine.overrideRouterSkipIfNeeded()

        // THEN: The decision should remain nil (no-op)
        XCTAssertNil(engine.currentRouterDecision, "Nil Router decision should remain nil")
    }
}
