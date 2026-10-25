import Foundation
@testable import PerformanceCore
@testable import PerformanceDaddy
import XCTest

@MainActor
final class LoadAlertCenterTests: XCTestCase {
    func testAlertQuitStopsOnlyTheCapturedIdentity() async throws {
        let child = try sleeper()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        let model = LiveViewModel()
        await model.refresh()
        let observed = try XCTUnwrap(model.snapshot?.processes.first { $0.id.pid == child.processIdentifier })

        // A reused PID with a different start time must not be signalled.
        let impostor = LiveProcess(id: .init(pid: observed.id.pid, started: observed.id.started &+ 1), parent: observed.parent,
                                   uid: observed.uid, name: observed.name, executable: observed.executable,
                                   directory: observed.directory, cpu: 100, memory: observed.memory)
        let stale = try XCTUnwrap(LoadContributors.group([impostor]).first)
        let refused = await model.quitFromLoadAlert(stale)
        XCTAssertTrue(refused.contains("not stopped"), refused)
        XCTAssertTrue(child.isRunning)

        // Grouped alone: under an agent-run test, the full snapshot correctly
        // attributes this child to the agent session.
        let current = try XCTUnwrap(LoadContributors.group([observed]).first)
        let message = await model.quitFromLoadAlert(current)
        XCTAssertTrue(message.contains("Stop requested"), message)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM, "Alerts never force-stop")
        XCTAssertTrue(model.lifecycle.events.contains { $0.text.contains("Stop signal sent") })
        XCTAssertFalse(model.performingAction)
    }

    func testProtectedContributorIsNotQuit() async {
        let model = LiveViewModel()
        let system = LiveProcess(id: .init(pid: 300, started: 1), parent: 1, uid: getuid(), name: "WindowServer",
                                 executable: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
                                 directory: "/", cpu: 400, memory: 1)
        let contributor = LoadContributors.group([system])[0]
        let message = await model.quitFromLoadAlert(contributor)
        XCTAssertTrue(message.contains("protected"), message)
        XCTAssertTrue(model.lifecycle.events.isEmpty)
    }

    func testEachRefreshReachesTheSampleObserver() async {
        let model = LiveViewModel()
        var dates: [Date] = []
        model.sampleObserver = { dates.append($0.date) }
        await model.refresh(background: true)
        await model.refresh(background: true)
        XCTAssertEqual(dates.count, 2)
    }

    func testSettingsPersistAndStartDisabled() throws {
        let suite = "LoadAlertCenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LoadAlertCenter(defaults: defaults)
        XCTAssertFalse(first.enabled)
        XCTAssertEqual(first.policy, LoadAlertPolicy(cooldown: 900))
        first.cpuPercent = 90
        first.cooldownMinutes = 30
        first.watchdogPolicy.processCPUPercent = 250
        first.watchdogPolicy.limits["app:example"] = .init(name: "Example", cpuPercent: 300, memoryGB: 8)
        let second = LoadAlertCenter(defaults: defaults)
        XCTAssertEqual(second.policy.cpuFraction, 0.9, accuracy: 0.0001)
        XCTAssertEqual(second.policy.cooldown, 1_800)
        XCTAssertEqual(second.watchdogPolicy.processCPUPercent, 250)
        XCTAssertEqual(second.watchdogPolicy.limits["app:example"]?.memoryGB, 8)
    }

    func testRecentFindingsWorkWithoutNotificationPermissionAndRespectSnooze() throws {
        let suite = "LoadAlertCenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "loadAlerts.enabled")
        let alerts = LoadAlertCenter(defaults: defaults)
        var policy = WatchdogPolicy()
        policy.kinds = [.processCPU]; policy.processSeconds = 60
        alerts.watchdogPolicy = policy
        let now = Date()
        func sample(_ offset: TimeInterval) -> LiveSnapshot {
            let date = now.addingTimeInterval(offset)
            let process = LiveProcess(id: .init(pid: 500, started: 1), parent: 1, uid: getuid(), name: "Example",
                executable: "/Applications/Example.app/Contents/MacOS/Example", directory: "/", cpu: 150, memory: 1)
            return LiveSnapshot(date: date, processes: [process],
                system: .init(timestamp: date, usedCPUCores: 2, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                              diskFreeBytes: nil, thermal: .nominal, processes: []), pressure: "Normal", compressed: nil,
                unavailableProcesses: 0, portsDate: date, scanSeconds: 0.01)
        }
        for time in [0.0, 30, 60] { alerts.observe(sample(time)) }
        XCTAssertEqual(alerts.recent.count, 1)
        XCTAssertEqual(alerts.recent.first?.kind, .processCPU)
        XCTAssertEqual(alerts.authorization, .notDetermined)
        alerts.clearRecent()
        alerts.snooze(minutes: 15)
        for time in [90.0, 120, 150] { alerts.observe(sample(time)) }
        XCTAssertTrue(alerts.recent.isEmpty)
        alerts.resumeAlerts()
        // Snooze/resume cannot turn pre-snooze observations into fresh evidence.
        alerts.observe(sample(180))
        XCTAssertTrue(alerts.recent.isEmpty)
    }

    func testAlertTextNamesScopeAndProtection() {
        let date = Date(timeIntervalSince1970: 1_000)
        let app = LiveProcess(id: .init(pid: 10, started: 1), parent: 1, uid: getuid(), name: "Example",
                              executable: "/Applications/Example.app/Contents/MacOS/Example", directory: "/", cpu: 500, memory: 1)
        let leader = LoadContributors.group([app])[0]
        let alert = LoadAlert(kind: .cpu, since: date, date: date.addingTimeInterval(150), usedCores: 7.2, coreCount: 8,
                              pressure: "Normal", contributor: leader)
        let text = LoadAlertCenter.content(for: alert, actionable: true)
        XCTAssertEqual(text.title, "Sustained CPU load")
        XCTAssertEqual(text.body, "7.2 of 8 cores busy for 2 minutes. Example and its helpers used about 5.0 cores.")
        XCTAssertTrue(LoadAlertCenter.content(for: alert, actionable: false).body.contains("can't be quit"))
        let diffuse = LoadAlert(kind: .memory, since: date, date: date.addingTimeInterval(60), usedCores: nil, coreCount: 8,
                                pressure: "Warning", contributor: nil)
        XCTAssertEqual(LoadAlertCenter.content(for: diffuse, actionable: false).title, "Memory pressure: Warning")
    }

    private func sleeper() throws -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        return child
    }
}
