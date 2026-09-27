import XCTest
@testable import PerformanceDaddy

final class AgentHookCommandTests: XCTestCase {
    func testClaudeTaskNotificationDoesNotBecomeLatestRequest() {
        XCTAssertNil(AgentHookCommand.shortTaskLabel("<task-notification>\nA background command completed."))
        XCTAssertEqual(AgentHookCommand.shortTaskLabel("Read README.md and name three features."),
                       "Read README.md and name three features.")
    }
}
