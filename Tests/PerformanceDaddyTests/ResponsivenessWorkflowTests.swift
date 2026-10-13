import AppKit
import XCTest
@testable import PerformanceCore
@testable import PerformanceDaddy

@MainActor final class ResponsivenessWorkflowTests: XCTestCase {
    func testOwnedMainQueueStallIsMeasuredWithoutFloodingOrSurvivingReset() async throws {
        let heartbeat = MainQueueHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        heartbeat.requestHeartbeat()
        heartbeat.requestHeartbeat()
        heartbeat.requestHeartbeat()
        // Stall only this test process, never another app or the user's workloads.
        usleep(650_000)
        try await Task.sleep(for: .milliseconds(100))
        let evidence = heartbeat.drain(appProbe: nil)
        XCTAssertGreaterThan(evidence.heartbeatMaximumMilliseconds ?? 0, 100)
        XCTAssertEqual(evidence.heartbeatCount, 1)
        heartbeat.stop()
        let reset = heartbeat.drain(appProbe: nil)
        XCTAssertEqual(reset.heartbeatCount, 0)
        XCTAssertNil(reset.heartbeatMaximumMilliseconds)
        heartbeat.recordLocalEvent(timestamp: .nan)
        heartbeat.recordLocalEvent(timestamp: ProcessInfo.processInfo.systemUptime + 1)
        XCTAssertEqual(heartbeat.drain(appProbe: nil).localEventCount, 0)
    }

    func testFollowUpHistoryRestoresRelationshipAndReportedOutcome() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("follow-up-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiagnosticHistoryStore(fileURL: folder.appendingPathComponent("history.json"))
        let date = Date()
        let before = DiagnosticFixtures.settledCapture()
        let followUp = FollowUpEvidence(baseline: .init(before), task: "Switch apps", change: .paused,
            changeDetail: "Build", sameTaskConfirmed: true)
        let after = DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(15), samples: [], followUp: followUp)
        let model = DiagnosisViewModel(historyStore: store)
        model.accept(DiagnosticEngine().analyze(after))
        model.reportSymptomOutcome(.worse)
        await model.waitForHistoryPersistence()
        let reopened = DiagnosisViewModel(historyStore: store)
        await reopened.loadHistory()
        reopened.review(try XCTUnwrap(reopened.recentReports.first))
        XCTAssertEqual(reopened.report?.capture.followUp?.outcome, .worse)
        XCTAssertEqual(reopened.report?.capture.followUp?.change, .paused)
        XCTAssertEqual(reopened.baselineReport?.capture.startedAt, before.startedAt)
        XCTAssertNotNil(reopened.comparison)
        for i in 0..<12 {
            let time = date.addingTimeInterval(Double(i + 1) * 100)
            model.accept(DiagnosticEngine().analyze(.init(startedAt: time, endedAt: time, samples: [])))
        }
        await model.waitForHistoryPersistence()
        // The retained after-capture carries its own flat baseline, independently of the history ring.
        XCTAssertEqual(reopened.report?.capture.followUp?.baseline.capture, FollowUpBaseline(before).capture)
    }

    func testFollowUpPreparationDoesNotPretendToPerformAnActionAndCancellationRestoresReport() async throws {
        let date = Date()
        let samples = (0..<4).map { i in
            SystemSample(timestamp: date.addingTimeInterval(Double(i)), usedCPUCores: 0.1,
                memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: 100_000_000_000, thermal: .nominal, processes: [])
        }
        let original = DiagnosticEngine().analyze(.init(startedAt: date, endedAt: date.addingTimeInterval(3), samples: samples))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("follow-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = DiagnosisViewModel(historyStore: DiagnosticHistoryStore(fileURL: folder.appendingPathComponent("history.json")))
        model.accept(original)
        model.performRecommendedAction()
        XCTAssertTrue(model.preparingFollowUp)
        XCTAssertFalse(model.isRecording)
        model.recordFollowUp(task: "Switch apps", change: .none, detail: "", sameTaskConfirmed: false)
        XCTAssertFalse(model.isRecording)
        model.recordFollowUp(task: "Switch apps", change: .none, detail: "", sameTaskConfirmed: true)
        XCTAssertTrue(model.isRecording)
        model.cancelRecording()
        for _ in 0..<100 where model.isRecording { await Task.yield() }
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.report?.capture, original.capture)
        XCTAssertEqual(model.recentReports.count, 1)
        await model.waitForHistoryPersistence()
    }

    func testDisabledAppProbeNeverRequestsAccess() async {
        let reader = AppResponseReader()
        let result = await reader.sample(target: nil, enabled: false)
        XCTAssertEqual(result?.status, .disabled)
        XCTAssertNil(result?.milliseconds)
    }

    func testNativeAppServiceTransportWithExistingAccessOnly() async throws {
        guard ProcessInfo.processInfo.environment["PERFORMANCEDADDY_AX_TEST"] == "1" else {
            throw XCTSkip("Opt-in native AX qualification; never requests permission.")
        }
        guard AppProbePermission.available else { throw XCTSkip("Existing Accessibility access is unavailable.") }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.significanthobbies.performancedaddy" && $0.bundleURL?.path == "/Applications/PerformanceDaddy.app"
        }) else { throw XCTSkip("The installed PerformanceDaddy window is not running.") }
        let snapshot = await WorkloadSampler().sample(includePorts: false)
        let process = try XCTUnwrap(snapshot.processes.first { $0.id.pid == app.processIdentifier })
        let reader = AppResponseReader()
        let response = await reader.sample(target: .init(identity: process.id, name: "PerformanceDaddy",
            bundleID: app.bundleIdentifier, version: nil), enabled: true)
        XCTAssertEqual(response?.status, .replied)
        XCTAssertNotNil(response?.milliseconds)
        XCTAssertEqual(ProcessPresence.inspect(process.id), .observed)
    }
}
