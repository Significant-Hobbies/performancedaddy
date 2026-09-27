import XCTest
@testable import PerformanceCore

final class AgentWallStatusTests: XCTestCase {
    func testTerminalStatesRemainVisibleWhileTheSessionProcessLives() {
        XCTAssertEqual(AgentWallActivity.resolve(event: "Stop", age: 3_600), .stopped)
        XCTAssertEqual(AgentWallActivity.resolve(event: "Interrupt", age: 3_600), .stopped)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PermissionRequest", age: 3_600), .waiting)
        XCTAssertEqual(AgentWallActivity.resolve(event: "StopFailure", age: 3_600), .failed)
    }

    func testWorkEvidenceExpiresWithoutAnotherHook() {
        XCTAssertEqual(AgentWallActivity.resolve(event: "PreToolUse", age: 299), .working)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PreToolUse", age: 301), .unavailable)
    }
}
