@testable import PerformanceCore
import Combine
import Darwin
@testable import PerformanceDaddy
import XCTest

final class AgentMenuSummaryTests: XCTestCase {
    @MainActor
    func testDeferredChangesUseLatestStateCoalesceBurstsAndUpdateWhilePaused() async throws {
        let model = LiveViewModel()
        let status = AgentMenuStatus(model: model)
        var values: [AgentMenuSummary] = []
        let subscription = status.$summary.dropFirst().sink { values.append($0) }
        defer { subscription.cancel() }
        let date = Date()
        let agent = LiveProcess(id: .init(pid: 500, started: 10), parent: 1, uid: getuid(), name: "codex",
                                executable: "/opt/bin/codex", directory: "/tmp", cpu: 0, memory: 1,
                                hasControllingTerminal: true)
        model.snapshot = LiveSnapshot(date: date, processes: [agent],
            system: .init(timestamp: date, usedCPUCores: 0, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                          diskFreeBytes: nil, thermal: .nominal, processes: []),
            pressure: "Normal", compressed: nil, unavailableProcesses: 0, portsDate: date, scanSeconds: 0)
        func signal(_ event: String) throws -> AgentWallSignal {
            try XCTUnwrap(AgentWallSignal(userInfo: ["pid": NSNumber(value: agent.id.pid),
                "started": NSNumber(value: agent.id.started), "provider": "Codex", "event": event,
                "timestamp": Date().timeIntervalSince1970]))
        }
        model.recordAgentSignal(try signal("PreToolUse"))
        for index in 0..<20 { model.search = String(index) }
        for _ in 0..<200 where values.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.last?.total, 1)
        XCTAssertEqual(values.last?.working, 1)
        model.paused = true
        for index in 20..<40 { model.search = String(index) }
        model.recordAgentSignal(try signal("Stop"))
        for _ in 0..<200 where values.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.last?.working, 0)
        XCTAssertEqual(values.last?.attention, 1)
        model.recordAgentSignal(try signal("PreToolUse"))
        for index in 40..<70 {
            model.search = String(index)
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(values.last?.working, 1, "Continuous unrelated updates must not starve status changes")
    }

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
