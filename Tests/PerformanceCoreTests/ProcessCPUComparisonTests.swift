import XCTest
@testable import PerformanceCore

final class ProcessCPUComparisonTests: XCTestCase {
    private typealias Point = (Double, UInt64?, Double?)
    private func capture(_ points: [Point]) -> DiagnosticCapture {
        let pid: Int32 = 49
        var trace = SelectedCPUTrace(selectedPIDs: [pid])
        trace.samples = points.map { time, start, cpu in
            .init(uptime: time, rows: start.map { [.init(identity: .init(pid: pid, started: $0), cpuCores: cpu)] } ?? [])
        }
        let samples = points.map { point in
            SystemSample(timestamp: Date(timeIntervalSince1970: point.0), usedCPUCores: 88, memoryHeadroomRatio: nil,
                         swapUsedBytes: nil, diskFreeBytes: nil, thermal: .nominal, processes: [])
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
