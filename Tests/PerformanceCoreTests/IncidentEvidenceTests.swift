import XCTest
@testable import PerformanceCore
import NativeInspection

final class IncidentEvidenceTests: XCTestCase {
    func testIORatesRequireSameInstanceCountersAndFreshInterval() {
        var tracker = ProcessIORateTracker()
        let id = ProcessIdentity(pid: 10, started: 100)
        func row(_ id: ProcessIdentity, _ read: UInt64?) -> LiveProcess {
            LiveProcess(id: id, parent: 1, uid: 501, name: "fixture", executable: "/tmp/fixture", directory: "", cpu: nil, memory: 100, diskReadBytes: read, diskWrittenBytes: 10)
        }
        XCTAssertNil(tracker.update([row(id, 100)], at: 1)[id]?.read)
        XCTAssertEqual(tracker.update([row(id, 300)], at: 3)[id]?.read, 100)
        XCTAssertNil(tracker.update([row(id, nil)], at: 4)[id]?.read)
        XCTAssertNil(tracker.update([row(id, 500)], at: 5)[id]?.read)
        XCTAssertNil(tracker.update([row(id, 20)], at: 6)[id]?.read)
        XCTAssertNil(tracker.update([row(id, 100)], at: 100)[id]?.read)
        let reused = ProcessIdentity(pid: 10, started: 200)
        XCTAssertNil(tracker.update([row(reused, 300)], at: 101)[reused]?.read)
    }

    func testColdCPUStillRetainsFootprintPressureAndDistinctAgentFamilies() throws {
        let date = Date()
        let a = LiveProcess(id: .init(pid: 20, started: 100), parent: 1, uid: 501, name: "claude", executable: "/tmp/claude", directory: "/home/project-A", cpu: nil, memory: 100, footprint: 80)
        let b = LiveProcess(id: .init(pid: 21, started: 100), parent: 1, uid: 501, name: "claude", executable: "/tmp/claude", directory: "/home/project-B", cpu: 10, memory: 200, footprint: 160)
        let child = LiveProcess(id: .init(pid: 22, started: 101), parent: 20, uid: 501, name: "go", executable: "/tmp/go", directory: "", cpu: 200, memory: 300, footprint: 240)
        var builder = SnapshotEvidenceBuilder()
        let base = sample(date)
        let live = LiveSnapshot(date: date, processes: [a,b,child], system: base, pressure: "Warning", compressed: nil, unavailableProcesses: 2, portsDate: .distantPast, scanSeconds: 0.01)
        let result = builder.sample(live, monotonicTime: 1)
        let evidence = try XCTUnwrap(result.incident)
        XCTAssertEqual(evidence.pressure, "Warning")
        XCTAssertEqual(evidence.workloads.count, 2)
        let family = try XCTUnwrap(evidence.workloads.first { $0.project == "project-A" })
        XCTAssertEqual(family.cpuCores, 2)
        XCTAssertEqual(family.footprintBytes, 320)
        XCTAssertEqual(family.cpuReadableCount, 1)
        XCTAssertEqual(family.processCount, 2)
        XCTAssertEqual(evidence.unavailableProcesses, 2)
    }

    func testMemoryAndIORankingPreservesNonCPUContributor() throws {
        let date = Date(); var builder = SnapshotEvidenceBuilder()
        let hot = (0..<20).map { index in
            LiveProcess(id: .init(pid: Int32(index+10), started: 100), parent: 1, uid: 501, name: "busy", executable: "/tmp/busy", directory: "", cpu: 100, memory: 10)
        }
        let heavy = LiveProcess(id: .init(pid: 200, started: 100), parent: 1, uid: 501, name: "idle-memory", executable: "/tmp/heavy", directory: "", cpu: nil, memory: 1000000000, footprint: 900000000)
        let live = LiveSnapshot(date: date, processes: hot+[heavy], system: sample(date), pressure: "Normal", compressed: nil, unavailableProcesses: 0, portsDate: .distantPast, scanSeconds: 0)
        let result = builder.sample(live)
        let row = try XCTUnwrap(result.incident?.workloads.first { $0.name.contains("idle-memory") })
        XCTAssertNil(row.cpuCores)
        XCTAssertEqual(row.footprintBytes, 900000000)
        XCTAssertLessThanOrEqual(result.incident?.workloads.count ?? 100, 32)
        XCTAssertLessThanOrEqual(result.workloads?.count ?? 100, 32)
    }

    func testRingRejectsDuplicateAndOldSamplesAndPreservesPreMarker() {
        var buffer = IncidentBuffer(maximumAge: 10, maximumCount: 3)
        for i in [0,5,5,4,10,15] { buffer.append(sample(Date(timeIntervalSince1970: Double(i)))) }
        XCTAssertEqual(buffer.samples.map { $0.timestamp.timeIntervalSince1970 }, [5,10,15])
        XCTAssertEqual(buffer.preceding(Date(timeIntervalSince1970: 12), seconds: 4).map { $0.timestamp.timeIntervalSince1970 }, [10])
        buffer.append(sample(Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(buffer.samples.count, 1)
    }

    func testHardwareDecoderRejectsInvalidTypesSizesAndNonfiniteValues() {
        var value: Float = 3250
        let bytes = withUnsafeBytes(of: &value) { Array($0) }
        let type: UInt32 = 0x666c7420
        XCTAssertEqual(bytes.withUnsafeBufferPointer { pd_smc_decode(type, $0.baseAddress, 4) }, 3250)
        XCTAssertTrue(bytes.withUnsafeBufferPointer { pd_smc_decode(type, $0.baseAddress, 2) }.isNaN)
        XCTAssertNil(HardwareEvidence.valid(.nan, minimum: 0, maximum: 100))
        XCTAssertNil(HardwareEvidence.valid(101, minimum: 0, maximum: 100))
        XCTAssertEqual(HardwareEvidence.valid(0, minimum: 0, maximum: 100), 0)
        XCTAssertNil(FanEvidence(name: "Fan", rpm: 1000, maximumRPM: nil).fractionOfMaximum)
        XCTAssertEqual(FanEvidence(name: "Fan", rpm: 3000, maximumRPM: 6000).fractionOfMaximum, 0.5)
    }

    func testOldCaptureDecodesAndRichReportDoesNotCallMarkedIdleHealthy() throws {
        let old = DiagnosticCapture(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 2), samples: [sample(Date(timeIntervalSince1970: 0)),sample(Date(timeIntervalSince1970: 2))])
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(DiagnosticCapture.self, from: data).marker)
        let date = Date(); var builder = SnapshotEvidenceBuilder()
        let samples = (0..<3).map { i in
            let date = date.addingTimeInterval(Double(i))
            return builder.sample(LiveSnapshot(date: date, processes: [], system: sample(date), pressure: "Normal", compressed: nil, unavailableProcesses: 1, portsDate: .distantPast, scanSeconds: 0))
        }
        let report = DiagnosticEngine().analyze(DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(2), samples: samples, marker: .init(date: date, symptom: "Typing lag", foreground: nil)))
        XCTAssertEqual(report.finding.kind, .inconclusive)
        XCTAssertFalse(report.finding.verdict.contains("healthy"))
        XCTAssertTrue(report.rootCauseAnalysis.limitations.contains("UI hangs"))
    }

    func testFallingCPUWithWorseningRealPressureCannotBeImproved() {
        let date = Date()
        func capture(cpu: Double, pressure: String) -> DiagnosticCapture {
            var builder = SnapshotEvidenceBuilder()
            let samples = (0..<3).map { i in
                let time = date.addingTimeInterval(Double(i))
                let base = SystemSample(timestamp: time, usedCPUCores: cpu, memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: 100000000000, thermal: .nominal, processes: [])
                return builder.sample(LiveSnapshot(date: time, processes: [], system: base, pressure: pressure, compressed: nil, unavailableProcesses: 0, portsDate: .distantPast, scanSeconds: 0))
            }
            return DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(2), samples: samples)
        }
        let engine = DiagnosticEngine()
        XCTAssertEqual(engine.compare(before: engine.analyze(capture(cpu: 2, pressure: "Normal")), after: engine.analyze(capture(cpu: 1, pressure: "Critical"))).outcome, .inconclusive)
    }

    func testIdleMemoryOwnerIsVisibleAlongsideCPUFamilies() {
        let date = Date(); var builder = SnapshotEvidenceBuilder()
        let busy = (0..<8).map { i in LiveProcess(id: .init(pid: Int32(i+30), started: 100), parent: 1, uid: 501, name: "busy-\(i)", executable: "/tmp/busy", directory: "", cpu: 100, memory: 10) }
        let heavy = LiveProcess(id: .init(pid: 200, started: 100), parent: 1, uid: 501, name: "idle-memory", executable: "/tmp/heavy", directory: "", cpu: nil, memory: 10000000000, footprint: 9000000000)
        let samples = (0..<3).map { i in
            let time = date.addingTimeInterval(Double(i))
            return builder.sample(LiveSnapshot(date: time, processes: busy+[heavy], system: sample(time), pressure: "Warning", compressed: nil, unavailableProcesses: 0, portsDate: .distantPast, scanSeconds: 0))
        }
        let report = DiagnosticEngine().analyze(DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(2), samples: samples))
        XCTAssertTrue(report.rootCauseAnalysis.contributors.contains { $0.contains("idle-memory") && $0.contains("CPU rate unavailable") && $0.contains("I/O unavailable") })
    }

    private func sample(_ date: Date) -> SystemSample {
        SystemSample(timestamp: date, usedCPUCores: 0.1, memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: 100000000000, thermal: .nominal, processes: [])
    }
}
