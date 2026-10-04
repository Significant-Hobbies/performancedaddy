import Darwin
import Foundation
@testable import PerformanceCore
import XCTest

final class LoadAlertTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let chrome = "/Applications/Google Chrome.app"

    func testSustainedCPUAlertsAndNamesConsistentAppWithHelpers() {
        var tracker = SustainedLoadTracker()
        var alert: LoadAlert?
        for tick in 0...3 { alert = tracker.observe(snapshot(tick * 30, used: 7, browser: 600), coreCount: 8) }
        let found = try? XCTUnwrap(alert)
        XCTAssertEqual(found?.kind, .cpu)
        XCTAssertEqual(found?.duration, 90)
        XCTAssertEqual(found?.contributor?.kind, .app)
        XCTAssertEqual(found?.contributor?.name, "Google Chrome")
        XCTAssertEqual(found?.contributor?.owner.id.pid, 500)
        XCTAssertEqual(found?.contributor?.targets.map(\.id.pid), [500], "An app is quit as one app, not signalled helper by helper")
        XCTAssertEqual(found?.contributor?.cpuCores ?? 0, 6, accuracy: 0.001)
    }

    func testShortSpikeDoesNotAlert() {
        var tracker = SustainedLoadTracker()
        for tick in 0...2 { XCTAssertNil(tracker.observe(snapshot(tick * 30, used: 7, browser: 600), coreCount: 8)) }
        XCTAssertNil(tracker.observe(snapshot(90, used: 1, browser: 50), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(120, used: 7, browser: 600), coreCount: 8), "A quiet reading restarts the window")
    }

    func testUnreadableCPUAndLongGapsRestartTheWindow() {
        var tracker = SustainedLoadTracker()
        XCTAssertNil(tracker.observe(snapshot(0, used: 7, browser: 600), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(30, used: nil, browser: 600), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(60, used: 7, browser: 600), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(90, used: 7, browser: 600), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(200, used: 7, browser: 600), coreCount: 8), "Gap longer than the policy breaks continuity")
        XCTAssertNil(tracker.observe(snapshot(230, used: 7, browser: 600), coreCount: 8))
    }

    func testDiffuseLoadAlertsWithoutNamingAQuitTarget() {
        var tracker = SustainedLoadTracker()
        var alert: LoadAlert?
        for tick in 0...3 { alert = tracker.observe(snapshot(tick * 30, used: 7, browser: 100), coreCount: 8) }
        XCTAssertEqual(alert?.kind, .cpu)
        XCTAssertNil(alert?.contributor, "1 of 7 used cores is below the naming share")
    }

    func testChangingLeaderIsNotNamed() {
        var tracker = SustainedLoadTracker()
        var alert: LoadAlert?
        for tick in 0...3 {
            alert = tracker.observe(snapshot(tick * 30, used: 7, browser: tick.isMultiple(of: 2) ? 600 : 10,
                                             tool: tick.isMultiple(of: 2) ? 10 : 600), coreCount: 8)
        }
        XCTAssertNotNil(alert)
        XCTAssertNil(alert?.contributor)
    }

    func testCooldownSuppressesRepeatAlerts() {
        var tracker = SustainedLoadTracker(policy: LoadAlertPolicy(cooldown: 600))
        var alerts = 0
        for tick in 0...20 where tracker.observe(snapshot(tick * 30, used: 7, browser: 600), coreCount: 8) != nil { alerts += 1 }
        XCTAssertEqual(alerts, 1, "Ten minutes of continuous load produces a single alert")
        var later: LoadAlert?
        for tick in 21...26 { later = tracker.observe(snapshot(tick * 30, used: 7, browser: 600), coreCount: 8) ?? later }
        XCTAssertNotNil(later, "After the cooldown a new full window may alert again")
    }

    func testIgnoredLeaderStaysQuiet() {
        var tracker = SustainedLoadTracker()
        for tick in 0...5 {
            XCTAssertNil(tracker.observe(snapshot(tick * 30, used: 7, browser: 600), coreCount: 8,
                                         ignored: ["app:\(chrome)"]))
        }
    }

    func testMemoryPressureAlertsAfterSustainedWarning() {
        var tracker = SustainedLoadTracker()
        XCTAssertNil(tracker.observe(snapshot(0, used: 1, browser: 10, pressure: "Warning"), coreCount: 8))
        XCTAssertNil(tracker.observe(snapshot(30, used: 1, browser: 10, pressure: "Critical"), coreCount: 8))
        let alert = tracker.observe(snapshot(60, used: 1, browser: 10, pressure: "Warning"), coreCount: 8)
        XCTAssertEqual(alert?.kind, .memory)
        XCTAssertEqual(alert?.contributor?.name, "Google Chrome")
        XCTAssertNil(tracker.observe(snapshot(90, used: 1, browser: 10, pressure: "Unavailable"), coreCount: 8))
    }

    func testAppLaunchedCommandLineWorkIsNotAttributedToTheApp() {
        let terminal = process(700, executable: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", cpu: 1)
        let shell = process(701, parent: 700, executable: "/bin/zsh", cpu: 0)
        let compiler = process(702, parent: 701, executable: "/usr/bin/clang", cpu: 500)
        let worker = process(703, parent: 702, executable: "/usr/bin/ld", cpu: 100)
        let groups = LoadContributors.group([terminal, shell, compiler, worker])
        let leader = groups.max { $0.cpuCores < $1.cpuCores }
        XCTAssertEqual(leader?.kind, .process)
        XCTAssertEqual(leader?.name, "clang")
        XCTAssertEqual(leader?.ignoreKey, "process:/usr/bin/clang")
        XCTAssertEqual(groups.first { $0.kind == .app }?.name, "Terminal")
    }

    func testAgentSessionGroupsDescendantsForReviewedStop() {
        let agent = process(800, executable: "/opt/homebrew/bin/claude", name: "claude", cpu: 10)
        let child = process(801, parent: 800, executable: "/usr/local/bin/node", cpu: 300)
        let group = LoadContributors.group([agent, child]).first { $0.kind == .agent }
        XCTAssertEqual(group?.name, "Claude session")
        XCTAssertEqual(Set(group?.targets.map(\.id.pid) ?? []), [800, 801])
        XCTAssertEqual(group?.cpuCores ?? 0, 3.1, accuracy: 0.001)
    }

    private func snapshot(_ offset: Int, used: Double?, browser: Double, tool: Double = 10,
                          pressure: String = "Normal") -> LiveSnapshot {
        let date = start.addingTimeInterval(TimeInterval(offset))
        let processes = [
            process(500, executable: "\(chrome)/Contents/MacOS/Google Chrome", cpu: browser * 0.2, memory: 4 << 30),
            process(501, parent: 500, executable: "\(chrome)/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", cpu: browser * 0.8, memory: 2 << 30),
            process(600, executable: "/usr/local/bin/tool", cpu: tool, memory: 1 << 30),
        ]
        let system = SystemSample(timestamp: date, usedCPUCores: used, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                                  diskFreeBytes: nil, thermal: .nominal, processes: [])
        return LiveSnapshot(date: date, processes: processes, system: system, pressure: pressure, compressed: 0,
                            unavailableProcesses: 0, portsDate: date, scanSeconds: 0.01)
    }

    private func process(_ pid: Int32, parent: Int32 = 1, executable: String, name: String? = nil,
                         cpu: Double?, memory: UInt64 = 1 << 20) -> LiveProcess {
        LiveProcess(id: ProcessIdentity(pid: pid, started: UInt64(pid)), parent: parent, uid: getuid(),
                    name: name ?? URL(fileURLWithPath: executable).lastPathComponent,
                    executable: executable, directory: "/", cpu: cpu, memory: memory)
    }
}
