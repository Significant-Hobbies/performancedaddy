import Foundation
import XCTest
@testable import PerformanceCore

final class RootCauseAnalysisTests: XCTestCase {
    func testEveryCaptureIncludingEmptyGetsAnInvestigation() {
        let report = DiagnosticEngine().analyze(capture([]))
        XCTAssertEqual(report.rootCauseAnalysis.assessments.count, 5)
        XCTAssertTrue(report.rootCauseAnalysis.assessments.allSatisfy { $0.status == .insufficient })
        XCTAssertFalse(report.rootCauseAnalysis.nextCheck.isEmpty)
        XCTAssertTrue(report.rootCauseAnalysis.conclusion.contains("not established"))
    }

    func testQuietCaptureHasCoverageAndTargetedNextStepNotAllClear() {
        let report = DiagnosticEngine().analyze(DiagnosticFixtures.settledCapture())
        XCTAssertEqual(report.rootCauseAnalysis.assessments.first { $0.id == "cpu" }?.status, .notObserved)
        XCTAssertEqual(report.rootCauseAnalysis.assessments.first { $0.id == "paging" }?.status, .insufficient)
        XCTAssertTrue(report.rootCauseAnalysis.nextCheck.contains("terminal startup"))
        XCTAssertTrue(report.rootCauseAnalysis.limitations.contains("Network latency"))
    }

    func testIndependentThermalEvidenceSurvivesUnavailableCPU() {
        let result = RootCauseAnalysis.analyze(capture([
            sample(0, cpu: nil, thermal: .critical), sample(1, cpu: nil, thermal: .serious),
        ]))
        XCTAssertEqual(result.assessments.first?.id, "thermal")
        XCTAssertEqual(result.assessments.first?.status, .observed)
        XCTAssertEqual(result.assessments.first { $0.id == "cpu" }?.status, .insufficient)
        XCTAssertTrue(result.conclusion.contains("Thermal pressure"))
        XCTAssertEqual(result.headline, "Thermal pressure needs investigation.")
    }

    func testMixedSignalsAndSubthresholdContributorsRemainVisible() {
        let result = RootCauseAnalysis.analyze(capture([
            sample(0, cpu: 3, headroom: 0.02, thermal: .serious),
            sample(1, cpu: 3, headroom: 0.03, thermal: .serious),
        ]))
        XCTAssertEqual(Set(result.assessments.filter { $0.status == .observed }.map(\.id)), ["cpu", "thermal", "memory"])
        XCTAssertTrue(result.contributors.first?.contains("tiny_worker: 0.10") == true)
        XCTAssertTrue(result.limitations.contains("lower bounds"))
    }

    func testInvalidDuplicateAndOutOfWindowEvidenceCannotBecomeRepeatedSignal() {
        let item = sample(0, cpu: 3)
        let result = RootCauseAnalysis.analyze(capture([item, item, sample(50, cpu: .nan)]))
        XCTAssertEqual(result.assessments.first { $0.id == "cpu" }?.status, .insufficient)
        XCTAssertTrue(result.coverage.contains("2 invalid"))
        let invalid = RootCauseAnalysis.analyze(capture([sample(0, cpu: .infinity, headroom: .nan), sample(1, cpu: -1, headroom: -1)]))
        XCTAssertEqual(invalid.assessments.first { $0.id == "cpu" }?.status, .insufficient)
        XCTAssertEqual(invalid.assessments.first { $0.id == "memory" }?.status, .insufficient)
    }

    func testOneLowMemorySpikeDoesNotBecomeSustainedSignal() {
        let result = RootCauseAnalysis.analyze(capture([sample(0, headroom: 0.01), sample(1), sample(2)]))
        XCTAssertEqual(result.assessments.first { $0.id == "memory" }?.status, .notObserved)
        XCTAssertTrue(result.assessments.first { $0.id == "memory" }!.evidence.contains("1/3"))
    }

    func testCPUWithoutProcessRowsDoesNotInventNamedContributors() {
        let samples = (0..<2).map { index in
            SystemSample(timestamp: Date(timeIntervalSince1970: Double(index)), usedCPUCores: 2,
                         memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: nil,
                         thermal: .nominal, processes: [])
        }
        let result = RootCauseAnalysis.analyze(capture(samples))
        XCTAssertTrue(result.contributors.isEmpty)
        XCTAssertTrue(result.conclusion.contains("no positive readable process rows"))
        XCTAssertEqual(result.headline, "CPU work is the strongest recorded signal.")
        XCTAssertTrue(result.nextCheck.contains("inspection may be restricted"))
    }

    func testSelectedPIDScopeQualifiesSystemWideCPUHeadline() {
        let date = Date(timeIntervalSince1970: 0)
        let scope = DiagnosticProcessScope(
            coverage: .selectedSameUserPIDs,
            selectedPIDCount: 1,
            readableProcessSamples: 2,
            unavailableProcessSamples: 0,
            statement: "Other processes are unobserved.")
        let samples = (0..<2).map { index in
            SystemSample(timestamp: date.addingTimeInterval(Double(index)), usedCPUCores: 2,
                         memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: nil,
                         thermal: .nominal, processes: [
                            .init(id: 42, parentID: 1, name: "task_worker", cpuCores: 0.001, residentBytes: 100),
                         ])
        }
        let selectedCapture = DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(1),
                                                samples: samples, processScope: scope)
        let selectedResult = RootCauseAnalysis.analyze(selectedCapture)
        XCTAssertEqual(selectedResult.headline,
                       "System-wide CPU activity is the strongest recorded signal; it is not attributed to the selected task process.")
        XCTAssertTrue(selectedResult.hasSelectedPIDScope)

        let legacyResult = RootCauseAnalysis.analyze(capture(samples))
        XCTAssertEqual(legacyResult.headline, "CPU work is the strongest recorded signal.")
        XCTAssertFalse(legacyResult.hasSelectedPIDScope)
    }

    private func capture(_ samples: [SystemSample]) -> DiagnosticCapture {
        .init(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 10), samples: samples)
    }
    private func sample(_ t: Double, cpu: Double? = 0.2, headroom: Double? = 0.5, thermal: ThermalCondition = .nominal) -> SystemSample {
        .init(timestamp: Date(timeIntervalSince1970: t), usedCPUCores: cpu, memoryHeadroomRatio: headroom,
              swapUsedBytes: 8_000_000_000, diskFreeBytes: 100_000_000_000, thermal: thermal,
              processes: [.init(id: 42, parentID: 1, name: "tiny_worker", cpuCores: 0.1, residentBytes: 100)])
    }
}
