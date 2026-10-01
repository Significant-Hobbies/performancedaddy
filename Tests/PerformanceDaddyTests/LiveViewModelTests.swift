import Foundation
@testable import PerformanceCore
@testable import PerformanceDaddy
import XCTest

@MainActor
final class LiveViewModelTests: XCTestCase {
    func testLiveRefreshCadenceHasLowOverheadFloorAndBoundedBackoff() {
        XCTAssertEqual(LiveViewModel.refreshInterval(after: nil), 10)
        XCTAssertEqual(LiveViewModel.refreshInterval(after: .nan), 10)
        XCTAssertEqual(LiveViewModel.refreshInterval(after: 0.1), 10)
        XCTAssertEqual(LiveViewModel.refreshInterval(after: 0.6), 12)
        XCTAssertEqual(LiveViewModel.refreshInterval(after: 10), 15)
    }

    func testInvalidMemoryAndTimingEvidenceDoesNotTrapOrInventNumbers() {
        let model = LiveViewModel()
        let own = process(ProcessInfo.processInfo.processIdentifier, name: "PerformanceDaddy", cpu: 1)
        for invalid in [Double.nan, .infinity, -.infinity, -1, 2] {
            model.snapshot = snapshot([own], headroom: invalid, scanSeconds: .nan)
            XCTAssertEqual(model.usedMemory, "—")
            XCTAssertTrue(model.observerSummary.contains("scan unavailable"))
        }
        model.snapshot = snapshot([own], headroom: 1)
        XCTAssertEqual(model.usedMemory, LiveViewModel.bytes(0))
    }

    func testOversizedFamilyMemoryDoesNotOverflow() {
        func member(_ pid: Int32, parent: Int32) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: 10), parent: parent, uid: getuid(), name: "codex", executable: "/opt/bin/codex", directory: "", cpu: 1, memory: UInt64.max, hasControllingTerminal: true)
        }
        let model = LiveViewModel()
        model.snapshot = snapshot([member(10, parent: 1), member(11, parent: 10)])
        XCTAssertEqual(model.rows(for: .agents).count, 1)
        XCTAssertEqual(model.rows(for: .agents).first?.memory, UInt64.max)
    }

    func testRepeatedSnapshotReplacementAndFilteringKeepsRowsCurrent() {
        let model = LiveViewModel()
        model.includeSystem = true
        for cycle in 0..<200 {
            let pid = Int32(1_000 + cycle)
            model.snapshot = snapshot([process(pid, name: "codex", cpu: Double(cycle))])
            model.search = "nothing-matches-👾"
            XCTAssertTrue(model.rows(for: .workloads).isEmpty)
            model.search = "codex"
            for page in [LivePage.workloads, .agents, .memory] {
                XCTAssertEqual(model.rows(for: page).map(\.id.pid), [pid])
            }
            XCTAssertTrue(model.rows(for: .ports).isEmpty)
        }
    }
    func testCatalogRolesAreSearchableAndAppContextIsVisible() {
        let service = LiveProcess(id: .init(pid: 900, started: 10), parent: 1, uid: getuid(), name: "coreaudiod", executable: "/usr/sbin/coreaudiod", directory: "/", cpu: 0, memory: 0)
        let app = LiveProcess(id: .init(pid: 901, started: 10), parent: 1, uid: getuid(), name: "helper", executable: "/Applications/Example.app/Contents/MacOS/helper", directory: "/", cpu: 0, memory: 0)
        let model = LiveViewModel()
        model.snapshot = snapshot([service, app])
        model.search = "audio"
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [900])
        XCTAssertTrue(model.processSubtitle(service).contains("Audio"))
        XCTAssertTrue(model.processSubtitle(app).contains("Example"))
        let helper = LiveProcess(id: .init(pid: 902, started: 20), parent: 901, uid: getuid(), name: "worker", executable: "/opt/bin/worker", directory: "/", cpu: 0, memory: 0)
        model.snapshot = snapshot([service, app, helper])
        model.search = "Example.app"
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [901, 902])
    }
    func testReviewedOwnedChildStopReachesLifecycleJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("performancedaddy-stop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        let child = Process()
        child.executableURL = executable
        child.arguments = ["30"]
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = LiveViewModel()
        await model.refresh()
        let observed = try XCTUnwrap(model.snapshot?.processes.first { $0.id.pid == child.processIdentifier })
        model.prepare([observed])
        XCTAssertEqual(model.review?.targets.count, 1)
        await model.confirmStop(force: false)
        XCTAssertEqual(model.outcomes.count, 1)
        XCTAssertTrue(model.outcomes[0].signalSent)
        XCTAssertNotNil(model.outcomes[0].signalDate)
        XCTAssertTrue(model.lifecycle.events.contains { $0.text.contains("signal sent") })
        XCTAssertTrue(model.lifecycle.events.contains { $0.text.contains("Exit confirmed") })
        XCTAssertTrue(model.outcomeText(model.outcomes[0]).contains("Exit confirmed"))
        XCTAssertFalse(model.lifecycle.events.contains { $0.text.contains("Matching executable") })
    }

    func testMissingSampleDoesNotConfirmExit() {
        let model = LiveViewModel()
        let target = process(999, name: "worker", cpu: 1)
        let result = StopResult(process: target, message: "Stop signal sent; checking exit", signalSent: true)
        model.snapshot = snapshot([])
        XCTAssertTrue(model.outcomeText(result).contains("exit not confirmed"))
        model.snapshot = snapshot([target])
        XCTAssertTrue(model.outcomeText(result).contains("still observed"))
    }

    func testPauseResumeStartsFreshRateWindow() async throws {
        let model = LiveViewModel()
        await model.refresh()
        try await Task.sleep(for: .milliseconds(150))
        await model.refresh()
        XCTAssertNotNil(model.snapshot?.system.memory?.rateIntervalSeconds)
        model.paused = true
        model.paused = false
        await model.refresh()
        XCTAssertNotNil(model.snapshot?.system.memory)
        XCTAssertNil(model.snapshot?.system.memory?.rateIntervalSeconds)
        XCTAssertNil(model.snapshot?.system.memory?.swapInBytesPerSecond)
        XCTAssertNil(model.snapshot?.system.usedCPUCores)
    }

    func testWakeStartsFreshRateWindow() async throws {
        let model = LiveViewModel()
        await model.refresh()
        try await Task.sleep(for: .milliseconds(150))
        await model.refresh()
        XCTAssertNotNil(model.snapshot?.system.memory?.rateIntervalSeconds)
        model.handleSystemWake()
        await model.refresh()
        XCTAssertNil(model.snapshot?.system.memory?.rateIntervalSeconds)
        XCTAssertNil(model.snapshot?.system.memory?.swapOutBytesPerSecond)
        XCTAssertNil(model.snapshot?.system.usedCPUCores)
    }

    func testCachedRowsInvalidateOnSearchSortAndSnapshot() {
        let model = LiveViewModel()
        model.includeSystem = true
        model.snapshot = snapshot([process(10, name: "devin", cpu: 2), process(11, name: "codex", cpu: 8)])
        XCTAssertEqual(model.agentCount, 2)
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [11, 10])
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [11, 10])
        model.search = "Devin"
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [10])
        model.search = ""
        model.sortOrder = [KeyPathComparator(\LiveProcess.sortCPU)]
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [10, 11])
        model.snapshot = snapshot([process(12, name: "claude", cpu: 1)])
        XCTAssertEqual(model.agentCount, 1)
        XCTAssertEqual(model.rows(for: .workloads).map(\.id.pid), [12])
        XCTAssertEqual(model.rows(for: .agents).map(\.id.pid), [12])
    }

    func testNestedCodexUnderDevinIsAWorkloadNotAnAdditionalSessionEvenWhenIdle() throws {
        let model = LiveViewModel()
        let host = LiveProcess(id: .init(pid: 40, started: 10), parent: 1, uid: getuid(),
                               name: "Devin", executable: "/Applications/Devin.app/Contents/MacOS/Devin",
                               directory: "", cpu: 0, memory: 1_000)
        let shell = process(41, parent: 40, name: "zsh", cpu: 0)
        let embedded = process(42, parent: 41, name: "codex", cpu: 0)
        let idle = (50..<56).map { process(Int32($0), name: "codex", cpu: 0) }
        model.snapshot = snapshot([host, shell, embedded] + idle)
        XCTAssertEqual(model.agentCount, 6)
        XCTAssertEqual(model.agentWallTiles.count, 6)
        XCTAssertEqual(model.rows(for: .agents).count, 6)
        XCTAssertTrue(model.agentWallTiles.allSatisfy { $0.activity == .unavailable })
        XCTAssertTrue(model.rows(for: .workloads).contains { $0.id == embedded.id })
        // Activity on the nested worker does not promote it into a user session.
        model.recordAgentSignal(try XCTUnwrap(AgentWallSignal(userInfo: [
            "pid": NSNumber(value: embedded.id.pid), "started": NSNumber(value: embedded.id.started),
            "provider": "Codex", "event": "PreToolUse",
            "timestamp": NSNumber(value: Date().timeIntervalSince1970 - 1)
        ])))
        XCTAssertEqual(model.agentCount, 6)
        XCTAssertEqual(model.agentWallTiles.count, 6)
    }

    func testDifferentProviderNestedUnderInteractiveAgentIsNotAnotherSession() {
        let model = LiveViewModel()
        let parent = process(40, name: "codex", cpu: 0)
        let nested = process(41, parent: 40, name: "claude", cpu: 0)
        let sibling = process(42, name: "claude", cpu: 0)
        model.snapshot = snapshot([parent, nested, sibling])
        XCTAssertEqual(Set(model.agentWallTiles.map(\.id.pid)), [40, 42])
        XCTAssertEqual(Set(model.rows(for: .agents).map(\.id.pid)), [40, 42])
        XCTAssertEqual(model.agentCount, 2)
    }

    func testConfirmedGoneAgentDisappearsFromCountCachedTableAndWall() async {
        let model = LiveViewModel()
        let gone = process(Int32.max, name: "codex", cpu: 0)
        model.snapshot = snapshot([gone])
        XCTAssertEqual(model.rows(for: .agents).count, 1) // populate table cache
        XCTAssertEqual(model.agentCount, 1)
        await model.checkAgentPresence()
        XCTAssertEqual(model.agentCount, 0)
        XCTAssertTrue(model.rows(for: .agents).isEmpty)
        XCTAssertTrue(model.agentWallTiles.isEmpty)
        XCTAssertEqual(model.rows(for: .workloads).count, 1) // snapshot unchanged
    }

    func testSessionEndRemovesSessionButTurnStopRetainsIdleSession() throws {
        let model = LiveViewModel()
        let root = process(10, name: "codex", cpu: 0)
        model.snapshot = snapshot([root])
        let base = Date().timeIntervalSince1970 - 1
        func send(_ event: String, offset: Double) throws {
            model.recordAgentSignal(try XCTUnwrap(AgentWallSignal(userInfo: [
                "pid": NSNumber(value: root.id.pid), "started": NSNumber(value: root.id.started),
                "provider": "Codex", "event": event, "timestamp": NSNumber(value: base + offset)
            ])))
        }
        try send("UserPromptSubmit", offset: 0)
        XCTAssertEqual(AgentMenuSummary(activities: model.agentWallTiles.map(\.activity)).working, 1)
        try send("Stop", offset: 0.1)
        XCTAssertEqual(model.agentCount, 1)
        XCTAssertEqual(model.agentWallTiles.first?.activity, .stopped)
        XCTAssertEqual(AgentMenuSummary(activities: model.agentWallTiles.map(\.activity)).working, 0)
        _ = model.rows(for: .agents)
        try send("SessionEnd", offset: 0.2)
        XCTAssertEqual(model.agentCount, 0)
        XCTAssertTrue(model.rows(for: .agents).isEmpty)
        XCTAssertTrue(model.agentWallTiles.isEmpty)
        try send("SessionStart", offset: 0.3)
        XCTAssertEqual(model.agentCount, 1)
        XCTAssertEqual(model.agentWallTiles.first?.activity, .unavailable)
    }

    func testEndedFailedSessionIsNotCountedAsLive() throws {
        let model = LiveViewModel()
        let root = process(10, name: "claude", cpu: 0)
        model.snapshot = snapshot([root])
        for (offset, event) in ["StopFailure", "SessionEnd"].enumerated() {
            model.recordAgentSignal(try XCTUnwrap(AgentWallSignal(userInfo: [
                "pid": NSNumber(value: root.id.pid), "started": NSNumber(value: root.id.started),
                "provider": "Claude", "event": event,
                "timestamp": NSNumber(value: Date().timeIntervalSince1970 - 1 + Double(offset) * 0.1)
            ])))
        }
        XCTAssertEqual(model.agentCount, 0)
        XCTAssertTrue(model.agentWallTiles.isEmpty)
    }

    func testCountDoesNotIncludeAnotherUsersAgent() {
        let other = LiveProcess(id: .init(pid: 10, started: 10), parent: 1, uid: getuid() + 1,
                                name: "codex", executable: "/bin/codex", directory: "",
                                cpu: 1, memory: 0, hasControllingTerminal: true)
        let model = LiveViewModel()
        model.snapshot = snapshot([other])
        XCTAssertEqual(model.agentCount, 0)
        XCTAssertTrue(model.agentWallTiles.isEmpty)
    }

    func testVersionedClaudeProcessAppearsInAgentSessions() {
        let executable = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions/2.1.280").path
        let claude = LiveProcess(id: .init(pid: 12, started: 10), parent: 1, uid: getuid(),
                                 name: "2.1.280", executable: executable, directory: "/tmp",
                                 cpu: 1, memory: 1_024, hasControllingTerminal: true)
        let model = LiveViewModel()
        model.snapshot = snapshot([claude])
        XCTAssertEqual(model.agentCount, 1)
        XCTAssertEqual(model.rows(for: .agents).map(\.id.pid), [12])
        XCTAssertEqual(model.rows(for: .agents).first?.agent, "Claude")
    }

    func testWallOmitsUninstrumentedDetachedHostsButKeepsTerminalAgents() {
        let model = LiveViewModel()
        let daemon = LiveProcess(id: .init(pid: 12, started: 10), parent: 1, uid: getuid(),
                                 name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                                 cpu: 0, memory: 1_024)
        let interactive = LiveProcess(id: .init(pid: 13, started: 10), parent: 1, uid: getuid(),
                                      name: "devin", executable: "/opt/bin/devin", directory: "/tmp",
                                      cpu: 0, memory: 1_024, hasControllingTerminal: true)
        model.snapshot = snapshot([daemon, interactive])
        XCTAssertEqual(Set(model.rows(for: .workloads).map(\.id.pid)), [12, 13])
        XCTAssertEqual(model.rows(for: .agents).map(\.id.pid), [13])
        XCTAssertEqual(model.agentWallTiles.map(\.id.pid), [13])
    }

    func testInstrumentedCodexHostDoesNotCreateAFifthSession() throws {
        let model = LiveViewModel()
        func codex(_ pid: Int32, parent: Int32, terminal: Bool) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: 10), parent: parent, uid: getuid(),
                        name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                        cpu: 0, memory: 1_024, hasControllingTerminal: terminal)
        }
        let host = codex(40, parent: 1, terminal: false)
        let terminals = [codex(41, parent: 40, terminal: true),
                         codex(42, parent: 1, terminal: true),
                         codex(43, parent: 1, terminal: true)]
        let devin = LiveProcess(id: .init(pid: 44, started: 10), parent: 1, uid: getuid(),
                                name: "devin", executable: "/opt/bin/devin", directory: "/tmp",
                                cpu: 0, memory: 1_024, hasControllingTerminal: true)
        model.snapshot = snapshot([host] + terminals + [devin])
        let signal = try XCTUnwrap(AgentWallSignal(userInfo: [
            "pid": NSNumber(value: host.id.pid), "started": NSNumber(value: host.id.started),
            "provider": "Codex", "event": "PostToolUse",
            "timestamp": NSNumber(value: Date().timeIntervalSince1970)
        ]))
        model.recordAgentSignal(signal)
        XCTAssertEqual(model.agentCount, 4)
        XCTAssertEqual(Set(model.agentWallTiles.map(\.id.pid)), [41, 42, 43, 44])
        XCTAssertEqual(model.agentWallTiles.first { $0.id.pid == 41 }?.activity, .unavailable)
        XCTAssertEqual(model.agentWallTiles.first { $0.id.pid == 41 }?.evidenceSummary,
                       "Shared Codex server; link this session")
    }

    func testExplicitCodexLinksKeepSharedHostSessionsSeparate() throws {
        let model = LiveViewModel()
        func codex(_ pid: Int32, started: UInt64 = 10, terminal: Bool) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: started), parent: 1, uid: getuid(),
                        name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                        cpu: 0, memory: 1_024, hasControllingTerminal: terminal)
        }
        let host = codex(40, terminal: false)
        let first = codex(41, terminal: true)
        let second = codex(42, terminal: true)
        model.snapshot = snapshot([host, first, second])
        let firstID = "019d0000-0000-7000-8000-000000000001"
        let secondID = "019d0000-0000-7000-8000-000000000002"
        func signal(_ session: String, _ event: String, task: String? = nil) throws -> AgentWallSignal {
            var payload: [String: Any] = [
                "pid": NSNumber(value: host.id.pid), "started": NSNumber(value: host.id.started),
                "provider": "Codex", "event": event,
                "sessionKey": try XCTUnwrap(AgentSessionKey.make(session)),
                "timestamp": NSNumber(value: Date().timeIntervalSince1970)
            ]
            if let task { payload["taskLabel"] = task }
            return try XCTUnwrap(AgentWallSignal(userInfo: payload))
        }
        model.recordAgentSignal(try signal(firstID, "UserPromptSubmit", task: "First task"))
        model.recordAgentSignal(try signal(secondID, "UserPromptSubmit", task: "Second task"))
        model.recordAgentSignal(try signal(firstID, "Stop"))
        XCTAssertEqual(model.agentWallTiles.count, 2)
        XCTAssertEqual(model.agentWallTiles.first { $0.id == first.id }?.activity, .unavailable)
        XCTAssertNotNil(model.linkCodexSession("not-a-session", to: first.id))
        XCTAssertNil(model.linkCodexSession(firstID, to: first.id))
        XCTAssertNil(model.linkCodexSession(secondID, to: second.id))
        XCTAssertNotNil(model.linkCodexSession(firstID, to: second.id))
        let firstTile = try XCTUnwrap(model.agentWallTiles.first { $0.id == first.id })
        let secondTile = try XCTUnwrap(model.agentWallTiles.first { $0.id == second.id })
        XCTAssertEqual(firstTile.activity, .stopped)
        XCTAssertEqual(firstTile.taskLabel, "First task")
        XCTAssertEqual(secondTile.activity, .working)
        XCTAssertEqual(secondTile.taskLabel, "Second task")

        let reused = codex(41, started: 11, terminal: true)
        model.snapshot = snapshot([host, reused, second])
        XCTAssertFalse(try XCTUnwrap(model.agentWallTiles.first { $0.id == reused.id }).isSessionLinked)
        XCTAssertEqual(model.agentWallTiles.count, 2)
    }

    func testTerminalCodexBelowSharedHostRemainsSeparate() {
        let model = LiveViewModel()
        let host = LiveProcess(id: .init(pid: 40, started: 10), parent: 1, uid: getuid(),
                               name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                               cpu: 1, memory: 10_000)
        let worker = LiveProcess(id: .init(pid: 41, started: 11), parent: 40, uid: getuid(),
                                 name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                                 cpu: 1, memory: 2_000)
        let terminal = LiveProcess(id: .init(pid: 42, started: 12), parent: 41, uid: getuid(),
                                   name: "codex", executable: "/opt/bin/codex", directory: "/tmp",
                                   cpu: 1, memory: 1_000, hasControllingTerminal: true)
        model.snapshot = snapshot([host, worker, terminal])
        XCTAssertEqual(model.rows(for: .agents).map(\.id.pid), [42])
        XCTAssertEqual(model.agentWallTiles.map(\.id.pid), [42])
        XCTAssertEqual(model.agentWallTiles.first?.process.memory, 1_000)
    }

    func testSharedCodexHookStaysWithItsHostEvenInTheSameWorkspace() throws {
        func codex(_ pid: Int32, parent: Int32 = 1, terminal: Bool, directory: String) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: 10), parent: parent, uid: getuid(),
                        name: "codex", executable: "/opt/bin/codex", directory: directory,
                        cpu: 0, memory: 1_024, hasControllingTerminal: terminal)
        }
        let host = codex(40, terminal: false, directory: "/tmp/one")
        let target = codex(41, parent: 40, terminal: true, directory: "/tmp/one")
        let signal = try XCTUnwrap(AgentWallSignal(userInfo: [
            "pid": NSNumber(value: host.id.pid), "started": NSNumber(value: host.id.started),
            "provider": "Codex", "event": "UserPromptSubmit",
            "timestamp": NSNumber(value: Date().timeIntervalSince1970)
        ]))
        let index = WorkloadIndex([host, target])
        XCTAssertEqual(LiveViewModel.directAgentSignal(
            for: host, index: index, signals: [host.id: signal]), signal)
        XCTAssertNil(LiveViewModel.directAgentSignal(
            for: target, index: index, signals: [host.id: signal]))
        XCTAssertNil(LiveViewModel.directAgentSignal(
            for: host, index: index, signals: [target.id: signal]))
    }

    func testFamilyAggregationAndReviewDoNotDuplicateTargets() {
        let model = LiveViewModel()
        model.includeSystem = true
        let root = process(20, name: "devin", cpu: 1)
        let helper = process(21, parent: 20, name: "devin", cpu: 2)
        let child = process(22, parent: 21, name: "node", cpu: 4)
        model.snapshot = snapshot([root, helper, child])
        let rows = model.rows(for: .agents)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.cpu, 7)
        XCTAssertEqual(rows.first?.memory, 3_072)
        model.prepareFamilies([root, helper])
        XCTAssertEqual(Set(model.review?.targets.map(\.id.pid) ?? []), [20, 21, 22])
        XCTAssertEqual(model.review?.targets.count, 3)
        XCTAssertFalse(model.performingAction)
    }

    func testReusedByteFormatterPreservesExistingOutput() {
        for bytes: UInt64 in [0, 1, 1023, 1024, 1_048_576, 48_000_000_000, UInt64.max] {
            XCTAssertEqual(LiveViewModel.bytes(bytes),
                ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory))
        }
    }

    func testGroupingPartitionsRowsIntoExpectedSections() {
        let model = LiveViewModel()
        model.includeSystem = true
        let agent = process(10, name: "codex", cpu: 1)
        let app = LiveProcess(id: .init(pid: 11, started: 10), parent: 1, uid: getuid(), name: "helper",
                              executable: "/Applications/Example.app/Contents/MacOS/helper", directory: "/", cpu: 0, memory: 1)
        let helper = LiveProcess(id: .init(pid: 12, started: 20), parent: 11, uid: getuid(), name: "worker",
                                 executable: "/opt/bin/worker", directory: "/", cpu: 0, memory: 1)
        let service = LiveProcess(id: .init(pid: 13, started: 10), parent: 1, uid: 0, name: "coreaudiod",
                                  executable: "/usr/sbin/coreaudiod", directory: "/", cpu: 0, memory: 1)
        let other = process(14, name: "daemon", cpu: 0)
        model.snapshot = snapshot([agent, app, helper, service, other])

        model.grouping = .kind
        let kind = model.groupedRows(for: .workloads)
        XCTAssertEqual(kind.map(\.title), ["Agents", "Apps", "System services", "Other"])
        XCTAssertEqual(kind.first { $0.title == "Apps" }?.rows.map(\.id.pid), [11, 12])
        XCTAssertEqual(Set(kind.flatMap(\.rows).map(\.id.pid)), [10, 11, 12, 13, 14])

        model.grouping = .app
        let byApp = model.groupedRows(for: .workloads)
        XCTAssertEqual(byApp.map(\.title), ["No app context", "Example"])
        XCTAssertEqual(byApp[0].rows.map(\.id.pid), [10, 13, 14])
        XCTAssertEqual(byApp[1].rows.map(\.id.pid), [11, 12])

        model.grouping = .category
        let byCategory = model.groupedRows(for: .workloads)
        XCTAssertEqual(byCategory.map(\.title), ["Agent tools", "Applications", "Audio", "Other processes"])
        XCTAssertEqual(byCategory.first { $0.title == "Audio" }?.rows.map(\.id.pid), [13])
        XCTAssertEqual(byCategory.first { $0.title == "Applications" }?.rows.map(\.id.pid), [11, 12])

        model.grouping = .none
        XCTAssertEqual(model.groupedRows(for: .workloads).flatMap(\.rows).map(\.id.pid),
                       model.rows(for: .workloads).map(\.id.pid))
    }

    func testTopContributorsRankMeasuredEvidence() {
        func member(_ pid: Int32, memory: UInt64, ports: Int = 0) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: 10), parent: 1, uid: getuid(), name: "p\(pid)",
                        executable: "/opt/bin/p\(pid)", directory: "/", cpu: 0, memory: memory,
                        ports: (0..<ports).map {
                            ListeningPort(port: UInt16(5000 + $0), transport: "TCP", address: "127.0.0.1", loopback: true)
                        })
        }
        let model = LiveViewModel()
        model.snapshot = snapshot([member(1, memory: 100), member(2, memory: 900),
                                   member(3, memory: 500, ports: 3), member(4, memory: 500, ports: 1)])
        XCTAssertEqual(model.topContributors(for: .ram).map(\.id.pid), [2, 3, 4, 1])
        XCTAssertEqual(model.topContributors(for: .swap).map(\.id.pid), [2, 3, 4, 1])
        XCTAssertEqual(model.topContributors(for: .sockets).map(\.id.pid), [3, 4])
        XCTAssertEqual(model.topContributors(for: .ram, limit: 2).map(\.id.pid), [2, 3])
    }

    private func process(_ pid: Int32, parent: Int32 = 1, name: String, cpu: Double) -> LiveProcess {
        LiveProcess(id: .init(pid: pid, started: 10), parent: parent, uid: getuid(), name: name,
                    executable: "/opt/bin/\(name)", directory: "/tmp", cpu: cpu, memory: 1_024,
                    hasControllingTerminal: AgentIdentity.label(executable: "/opt/bin/\(name)", processName: name) != nil)
    }

    private func snapshot(_ processes: [LiveProcess], headroom: Double = 0.5, scanSeconds: Double = 0.01) -> LiveSnapshot {
        let date = Date(timeIntervalSince1970: 1_000)
        return LiveSnapshot(date: date, processes: processes,
            system: .init(timestamp: date, usedCPUCores: 1, memoryHeadroomRatio: headroom,
                          swapUsedBytes: 0, diskFreeBytes: nil, thermal: .nominal, processes: []),
            pressure: "Normal", compressed: nil, unavailableProcesses: 0, portsDate: date, scanSeconds: scanSeconds)
    }
}
