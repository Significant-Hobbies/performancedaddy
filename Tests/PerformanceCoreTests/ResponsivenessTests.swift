import XCTest
@testable import PerformanceCore

final class ResponsivenessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private func capture(latency: Double = 120, status: AppResponseProbe.Status = .replied,
                         bundle: String = "example.app", version: String = "1", cpu: Double = 0.2,
                         pressure: String = "Normal", count: Int = 7, offset: Double = 0) -> DiagnosticCapture {
        let date = start.addingTimeInterval(offset)
        var builder = SnapshotEvidenceBuilder()
        let samples = (0..<count).map { i in
            let time = date.addingTimeInterval(Double(i) * 5)
            let process = LiveProcess(id: .init(pid: 100, started: 50), parent: 1, uid: 501,
                name: "idle-large", executable: "/tmp/fixture", directory: "", cpu: cpu * 100, memory: 8_000_000_000, footprint: 7_000_000_000)
            let base = SystemSample(timestamp: time, usedCPUCores: cpu, memoryHeadroomRatio: 0.5,
                swapUsedBytes: 0, diskFreeBytes: 100_000_000_000, thermal: .nominal, processes: [],
                power: PowerEvidence(lowPowerMode: false, cpuSpeedLimitPercent: nil, schedulerLimitPercent: nil))
            let rich = builder.sample(LiveSnapshot(date: time, processes: [process], system: base, pressure: pressure,
                compressed: nil, unavailableProcesses: 1, portsDate: .distantPast, scanSeconds: 0.01))
            return rich.withResponsiveness(.init(windowStartedAt: time.addingTimeInterval(-5), windowEndedAt: time,
                heartbeatCount: 5, heartbeatMaximumMilliseconds: 2,
                appProbe: .init(date: time, app: "Fixture App", bundleID: bundle, version: version, status: status, milliseconds: latency)))
        }
        return .init(startedAt: date, endedAt: date.addingTimeInterval(30), samples: samples)
    }
    private func followUp(_ before: DiagnosticCapture, task: String = "Switch apps", confirmed: Bool = true) -> FollowUpEvidence {
        .init(baseline: .init(before), task: task, change: .paused, changeDetail: "Fixture build", sameTaskConfirmed: confirmed)
    }

    func testLatencyComparisonIsScopedAndNeverTurnsMissingResponsesIntoZero() {
        let before = capture(), after = capture(latency: 20, offset: 100)
        let comparison = followUp(before).compareResponsiveness(after)
        XCTAssertEqual(comparison.outcome, .improved)
        XCTAssertTrue(comparison.detail.contains("does not measure pixels"))
        XCTAssertEqual(followUp(before).compareResponsiveness(capture(latency: 0, status: .didNotReply, offset: 100)).outcome, .inconclusive)
        XCTAssertNil(ResponsivenessSummary.analyze(capture(status: .didNotReply)).p95Milliseconds)
        XCTAssertEqual(followUp(before).compareResponsiveness(capture(status: .permissionMissing, offset: 100)).outcome, .inconclusive)
    }

    func testDifferentTaskTargetVersionDurationAndSparseEvidenceRejectComparison() {
        let before = capture()
        XCTAssertEqual(followUp(before, confirmed: false).compareResponsiveness(capture(latency: 0)).outcome, .inconclusive)
        XCTAssertEqual(followUp(before, task: "").compareResponsiveness(capture(latency: 0)).outcome, .inconclusive)
        XCTAssertEqual(followUp(before).compareResponsiveness(capture(latency: 0, bundle: "other.app")).outcome, .inconclusive)
        XCTAssertEqual(followUp(before).compareResponsiveness(capture(latency: 0, version: "2")).outcome, .inconclusive)
        XCTAssertEqual(followUp(before).compareResponsiveness(capture(latency: 0, count: 2)).outcome, .inconclusive)
        let after = capture(latency: 0)
        let long = DiagnosticCapture(startedAt: after.startedAt, endedAt: after.endedAt.addingTimeInterval(120), samples: after.samples)
        XCTAssertEqual(followUp(before).compareResponsiveness(long).outcome, .inconclusive)
    }

    func testPostMarkerBaselineStripsPrehistoryAndFollowUpChain() throws {
        let old = capture(cpu: 8)
        let new = capture(cpu: 0.1, offset: 120)
        let marked = DiagnosticCapture(startedAt: old.startedAt, endedAt: new.endedAt, samples: old.samples + new.samples,
            marker: .init(date: new.startedAt, symptom: "Typing lag", foreground: nil), followUp: followUp(old))
        let baseline = FollowUpBaseline(marked)
        XCTAssertEqual(baseline.capture.duration, 30)
        XCTAssertEqual(baseline.samples.count, 7)
        XCTAssertNil(baseline.capture.followUp)
        XCTAssertEqual(DiagnosticEngine().compare(before: DiagnosticEngine().analyze(baseline.capture), after: DiagnosticEngine().analyze(new)).outcome, .unchanged)
    }

    func testExplanationUsesIncidentTimeAndIdleMemoryOwnerWithoutInventingCause() {
        let quiet = capture(latency: 2)
        let earlier = capture(cpu: 10, offset: -120)
        let marked = DiagnosticCapture(startedAt: earlier.startedAt, endedAt: quiet.endedAt, samples: earlier.samples + quiet.samples,
            marker: .init(date: quiet.startedAt.addingTimeInterval(5), symptom: "Typing lag", foreground: nil))
        XCTAssertTrue(IncidentExplanation.analyze(marked).observed.contains("No captured resource pressure"))
        let memory = IncidentExplanation.analyze(capture(latency: 2, cpu: 0, pressure: "Critical"))
        XCTAssertTrue(memory.candidate.contains("idle-large"))
        XCTAssertTrue(memory.candidate.contains("not a confirmed cause"))
        XCTAssertNotNil(memory.reviewSearch)
        let response = IncidentExplanation.analyze(capture())
        XCTAssertTrue(response.observed.contains("accessibility service"))
        XCTAssertNil(response.reviewSearch)
    }

    func testDuplicateProbesAndOldCapturesDoNotManufactureEvidence() throws {
        let original = capture(count: 1)
        let duplicate = DiagnosticCapture(startedAt: original.startedAt, endedAt: original.endedAt,
            samples: Array(repeating: original.samples[0], count: 10))
        XCTAssertEqual(ResponsivenessSummary.analyze(duplicate).probeCount, 1)
        XCTAssertEqual(ResponsivenessSummary.analyze(duplicate).monitorCount, 5)
        let invalid = AppResponseProbe(date: start, app: "App", bundleID: nil, status: .replied, milliseconds: .nan)
        XCTAssertNil(invalid.milliseconds)
        let data = Data("{\"startedAt\":0,\"endedAt\":1,\"samples\":[],\"isFixture\":false}".utf8)
        let old = try JSONDecoder().decode(DiagnosticCapture.self, from: data)
        XCTAssertNil(old.followUp)
        let encoded = try JSONEncoder().encode(original.withFollowUp(followUp(original).reporting(.worse)))
        let reopened = try JSONDecoder().decode(DiagnosticCapture.self, from: encoded)
        XCTAssertEqual(reopened.followUp?.outcome, .worse)
        XCTAssertEqual(reopened.samples.first?.responsiveness?.appProbe?.version, "1")
    }

    func testMixedAppsDoNotBlameTheLastAppOrPoolItsLatency() {
        let a = capture(count: 1), b = capture(bundle: "other.app", count: 1, offset: 5)
        let mixed = DiagnosticCapture(startedAt: a.startedAt, endedAt: b.endedAt, samples: a.samples + b.samples)
        let summary = ResponsivenessSummary.analyze(mixed)
        XCTAssertTrue(summary.details.contains("Multiple app services"))
        XCTAssertNil(summary.p95Milliseconds)
        XCTAssertFalse(IncidentExplanation.analyze(mixed).observed.contains("had 2 replies"))
        XCTAssertTrue(IncidentExplanation.analyze(mixed).observed.contains("No captured resource pressure"))
    }

    func testGlobalProbeBudgetRejectsBurstInvalidAndBackwardsTimes() {
        var budget = AppProbeCadence()
        XCTAssertTrue(budget.take(at: 0))
        XCTAssertFalse(budget.take(at: 2)) // A different target still shares this same budget.
        XCTAssertFalse(budget.take(at: 4))
        XCTAssertTrue(budget.take(at: 5))
        XCTAssertFalse(budget.take(at: .nan))
        XCTAssertFalse(budget.take(at: 4))
        XCTAssertTrue(budget.take(at: 10))
    }
}
