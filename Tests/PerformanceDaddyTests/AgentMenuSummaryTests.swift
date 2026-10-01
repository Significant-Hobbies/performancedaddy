import PerformanceCore
@testable import PerformanceDaddy
import XCTest

final class AgentMenuSummaryTests: XCTestCase {
    func testDetectedIdleAndUnknownAreNotCountedAsRecentlyWorking() {
        let summary = AgentMenuSummary(activities: [.working, .stopped, .unavailable, .waiting, .failed])
        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.working, 1)
        XCTAssertEqual(summary.attention, 3)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertTrue(summary.accessibilityLabel.contains("1 recently working"))
        XCTAssertTrue(summary.accessibilityLabel.contains("5 detected in total"))
        XCTAssertFalse(summary.accessibilityLabel.contains("5 live"))
    }
    func testExpiredOrMissingHooksDoNotConfirmWorkEvenWithOpenProcesses() {
        let summary = AgentMenuSummary(activities: [
            AgentWallActivity.resolve(event: "PreToolUse", age: 301),
            AgentWallActivity.resolve(event: nil, age: 0),
            AgentWallActivity.resolve(event: "Stop", age: 0)
        ])
        XCTAssertEqual(summary.working, 0)
        XCTAssertEqual(summary.total, 3)
    }
}
