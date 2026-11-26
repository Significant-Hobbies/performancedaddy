import PerformanceWorkspaceKit
import XCTest

@MainActor
final class PerformanceWorkspaceTests: XCTestCase {
    func testPublicHostRoutesAndCommands() {
        let ids = Set(PerformanceRoute.allCases.map(\.id))
        XCTAssertEqual(ids, ["diagnose", "processes", "ports", "agents", "memory", "thermals",
                             "access", "configuration", "alerts", "follow-up", "traces", "culprits"])
        XCTAssertFalse(PerformanceWorkspaceCommands.handle(arguments: ["--host-command"]))
        XCTAssertTrue(PerformanceWorkspaceCommands.handle(arguments: ["--agent-hook", "unsupported"]))
    }

    func testHostCanConstructEverySurfaceOnOneSession() {
        let session = PerformanceWorkspaceSession()
        XCTAssertNil(session.activeWorkDescription)
        XCTAssertFalse(session.notificationCategories.isEmpty)
        for route in PerformanceRoute.allCases {
            _ = PerformanceWorkspaceView(session: session, route: route, onNavigate: { _ in }).body
        }
        _ = PerformanceActivityOverview(session: session)
        _ = PerformanceCulpritOverview(session: session)
        _ = PerformanceWorkspaceMenu(session: session, onNavigate: { _ in })
        _ = PerformanceAgentWall(session: session)
        _ = PerformanceAgentStatusIndicator(session: session)
    }
}
