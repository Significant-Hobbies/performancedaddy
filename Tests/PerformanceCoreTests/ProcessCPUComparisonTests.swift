import XCTest
@testable import PerformanceCore

final class ProcessCPUComparisonTests: XCTestCase {
    private typealias Point = (Double, UInt64?, Double?)
    private let boot = UUID()
    private func capture(_ points: [Point], bootOverride: UUID? = nil, scanDuration: Double = 0) -> DiagnosticCapture {
        let pid: Int32 = 49
        var trace = SelectedCPUTrace(selectedPIDs: [pid], bootSession: bootOverride ?? boot)
        trace.samples = points.map { time, start, cpu in
            .init(uptime: time, rows: start.map { [.init(identity: .init(pid: pid, started: $0), cpuCores: cpu)] } ?? [])
        }
        let samples = points.map { point in
            SystemSample(timestamp: Date(timeIntervalSince1970: point.0), usedCPUCores: 88, memoryHeadroomRatio: nil,
                         swapUsedBytes: nil, diskFreeBytes: nil, thermal: .nominal, processes: [], incident: .init(logicalCPUs: 8, pressure: "Normal", foreground: nil, workloads: [], readableProcesses: 1, unavailableProcesses: 0, scanSeconds: scanDuration, hardware: nil, newlyObservedProcesses: 0, noLongerObservedProcesses: 0))
        }
        return DiagnosticCapture(startedAt: samples.first!.timestamp, endedAt: samples.last!.timestamp, samples: samples,
                                 processScope: .init(coverage: .selectedSameUserPIDs, selectedPIDCount: 1, readableProcessSamples: 0, unavailableProcessSamples: 0, statement: ""), selectedCPUTrace: trace)
    }
    private var baseline: DiagnosticCapture { capture([(1, 10, nil), (3, 10, 1), (5, 10, 1)]) }

    func testTimeWeightedChangeUsesOnlySameIdentity() throws {
        let item = try ProcessCPUComparison(before: baseline, after: capture([(7, 10, nil), (9, 10, 0), (10, 10, 0.6)]), pid: 49)
        XCTAssertEqual(item.status, .compared)
        XCTAssertEqual(try XCTUnwrap(item.changeInMeanCPUCores), -0.8, accuracy: 0.00001)
    }
    func testSlowReadsAreDistinctFromMissingPollsAndShortWindows() throws {
        let slow = capture([(7, 10, nil), (12, 10, 0), (17, 10, 0)], scanDuration: 3)
        XCTAssertEqual(try ProcessCPUComparison(before: baseline, after: slow, pid: 49).status, .compared)
        let short = capture([(7, 10, nil), (9, 10, 0)])
        XCTAssertEqual(try ProcessCPUComparison(before: baseline, after: short, pid: 49).status, .insufficientObservations)
        let gap = capture([(0, 10, nil), (6, 10, 1), (8, 10, 1)])
        let after = capture([(11, 10, nil), (13, 10, 0), (15, 10, 0)])
        XCTAssertEqual(try ProcessCPUComparison(before: gap, after: after, pid: 49).status, .incompleteIntervals)
        let foreign = capture([(11, 10, nil), (13, 10, 0), (15, 10, 0)], bootOverride: UUID())
        XCTAssertThrowsError(try ProcessCPUComparison(before: baseline, after: foreign, pid: 49)) {
            XCTAssertEqual($0 as? ProcessCPUComparison.Failure, .differentBoot)
        }
    }
    func testDifferentProcessAbsentAndGappedReadsWithholdDelta() throws {
        for (points, status): ([Point], ProcessCPUComparison.Status) in [
            ([(7, 11, nil), (9, 11, 0), (11, 11, 0)], .pidReused),
            ([(7, nil, nil), (9, nil, nil)], .targetUnobserved),
            ([(7, 10, nil), (15, 10, 0), (17, 10, 0)], .incompleteIntervals),
            ([(7, 10, nil), (9, nil, nil), (11, 10, 0)], .incompleteIntervals)] {
            let item = try ProcessCPUComparison(before: baseline, after: capture(points), pid: 49)
            XCTAssertEqual(item.status, status)
            XCTAssertNil(item.changeInMeanCPUCores)
        }
        XCTAssertThrowsError(try ProcessCPUComparison(before: baseline, after: baseline, pid: 49))
        XCTAssertThrowsError(try ProcessCPUComparison(before: baseline, after: baseline, pid: 200))
        let legacy = DiagnosticCapture(startedAt: .now, endedAt: .now, samples: [])
        XCTAssertThrowsError(try ProcessCPUComparison(before: legacy, after: baseline, pid: 49))
    }
}
