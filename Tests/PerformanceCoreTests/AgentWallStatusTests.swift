import XCTest
@testable import PerformanceCore

final class AgentWallStatusTests: XCTestCase {
    func testTerminalStatesRemainVisibleWhileTheSessionProcessLives() {
        XCTAssertEqual(AgentWallActivity.resolve(event: "Stop", age: 3_600), .stopped)
        XCTAssertEqual(AgentWallActivity.resolve(event: "Interrupt", age: 3_600), .stopped)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PermissionRequest", age: 3_600), .waiting)
        XCTAssertEqual(AgentWallActivity.resolve(event: "StopFailure", age: 3_600), .failed)
        XCTAssertEqual(AgentWallActivity.resolve(event: "RateLimit", age: 3_600), .rateLimited)
        XCTAssertEqual(AgentWallActivity.resolve(event: "Elicitation", age: 3_600), .waiting)
    }

    func testWorkEvidenceExpiresWithoutAnotherHook() {
        XCTAssertEqual(AgentWallActivity.resolve(event: "PreToolUse", age: 299), .working)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PreToolUse", age: 301), .unavailable)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PostCompaction", age: 3), .working)
        XCTAssertEqual(AgentWallActivity.resolve(event: "PostToolUseFailure", age: 301), .unavailable)
    }

    func testWorkspaceKeyMatchesNormalizedPathsWithoutExposingThePath() {
        let key = AgentWorkspaceKey.make("/tmp/project/../project")
        XCTAssertEqual(key, AgentWorkspaceKey.make("/tmp/project"))
        XCTAssertEqual(key?.count, 64)
        XCTAssertFalse(key?.contains("project") ?? true)
        XCTAssertNil(AgentWorkspaceKey.make("project"))
    }
}
