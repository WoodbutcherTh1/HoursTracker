import XCTest
@testable import HoursTracker

/// The router is the assistant's consent gate and its failover chain. Both have to hold:
/// nothing is sent when the user hasn't opted in, and a failing provider must hand off to
/// the next rather than surface its error.
final class AssistantLLMRouterTests: XCTestCase {

    // MARK: - Consent gate

    func testNotConfiguredWhenCloudDisabledEvenWithKeys() {
        let router = AssistantLLMRouter.default(
            geminiKey: "gem-key",
            secondaryKey: "sec-key",
            cloudEnabled: false
        )
        XCTAssertFalse(router.isConfigured, "a saved key must not enable the assistant while the cloud toggle is off")
    }

    func testNotConfiguredWhenCloudEnabledButNoKeys() {
        let router = AssistantLLMRouter.default(
            geminiKey: nil,
            secondaryKey: "   ",
            cloudEnabled: true
        )
        XCTAssertFalse(router.isConfigured)
    }

    func testConfiguredWhenCloudEnabledAndAKeyIsPresent() {
        let router = AssistantLLMRouter.default(
            geminiKey: "gem-key",
            secondaryKey: nil,
            cloudEnabled: true
        )
        XCTAssertTrue(router.isConfigured)
    }

    func testPlanThrowsMissingAPIKeyWhenNothingToTry() async {
        let router = AssistantLLMRouter(providers: [])
        do {
            _ = try await router.plan(question: "how many hours in July?", context: .current())
            XCTFail("expected a throw")
        } catch let error as ScannerLLMError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Failover chain

    func testFallsThroughRateLimitedProviderToTheNext() async throws {
        let expected = AssistantPlan(action: .summarizeHours, filters: AssistantFilters(month: "2026-07"))
        let router = AssistantLLMRouter(providers: [
            StubAssistantLLMProvider(name: "First", outcome: .failure(.rateLimited)),
            StubAssistantLLMProvider(name: "Second", outcome: .success(expected))
        ])

        let plan = try await router.plan(question: "hours in July", context: .current())
        XCTAssertEqual(plan, expected)
    }

    func testThrowsLastErrorWhenEveryProviderFails() async {
        let router = AssistantLLMRouter(providers: [
            StubAssistantLLMProvider(name: "First", outcome: .failure(.rateLimited)),
            StubAssistantLLMProvider(name: "Second", outcome: .failure(.quotaExceeded))
        ])

        do {
            _ = try await router.plan(question: "hours", context: .current())
            XCTFail("expected a throw")
        } catch let error as ScannerLLMError {
            XCTAssertEqual(error, .quotaExceeded, "the last provider's error should be the one surfaced")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private struct StubAssistantLLMProvider: AssistantLLMProviding {
    let name: String
    let outcome: Result<AssistantPlan, ScannerLLMError>

    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan {
        try outcome.get()
    }
}
