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

    func testSessionKeyDoesNotExposeTheSessionID() {
        let key = AgentSessionKey.make("private-session-id")
        XCTAssertEqual(key, AgentSessionKey.make("private-session-id"))
        XCTAssertEqual(key?.count, 64)
        XCTAssertFalse(key?.contains("private-session-id") ?? true)
        XCTAssertNil(AgentSessionKey.make(""))
    }

    func testSharedCodexHostDoesNotCarryAnotherSessionsRequest() throws {
        let now = Date().timeIntervalSince1970
        func signal(session: String, event: String, task: String? = nil) throws -> AgentWallSignal {
            var payload: [String: Any] = [
                "pid": NSNumber(value: 40), "started": NSNumber(value: 10),
                "provider": "Codex", "event": event, "timestamp": NSNumber(value: now),
                "sessionKey": try XCTUnwrap(AgentSessionKey.make(session)),
                "workspace": session
            ]
            payload["taskLabel"] = task
            return try XCTUnwrap(AgentWallSignal(userInfo: payload))
        }
        let first = try signal(session: "one", event: "UserPromptSubmit", task: "First task")
        XCTAssertEqual(try signal(session: "one", event: "PostToolUse")
            .carryingForward(from: first).taskLabel, "First task")
        XCTAssertNil(try signal(session: "two", event: "PostToolUse")
            .carryingForward(from: first).taskLabel)
        XCTAssertEqual(try signal(session: "two", event: "PostToolUse")
            .carryingForward(from: first).workspace, "two")
    }
}
