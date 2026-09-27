import XCTest
@testable import PerformanceDaddy

final class AgentHookCommandTests: XCTestCase {
    func testClaudeTaskNotificationDoesNotBecomeLatestRequest() {
        XCTAssertNil(AgentHookCommand.shortTaskLabel("<task-notification>\nA background command completed."))
        XCTAssertEqual(AgentHookCommand.shortTaskLabel("Read README.md and name three features."),
                       "Read README.md and name three features.")
    }

    func testRateLimitIsAnAttentionStateOnlyForDocumentedClaudeFailure() {
        XCTAssertEqual(AgentHookCommand.statusEvent(provider: "Claude", payload: [
            "hook_event_name": "StopFailure", "error": "rate_limit"
        ]), "RateLimit")
        XCTAssertEqual(AgentHookCommand.statusEvent(provider: "Claude", payload: [
            "hook_event_name": "StopFailure", "error": "server_error"
        ]), "StopFailure")
        XCTAssertNil(AgentHookCommand.statusEvent(provider: "Devin", payload: [
            "hook_event_name": "Notification", "notification_type": "quota_auto_resume_fired"
        ]))
    }
}
