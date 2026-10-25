import Foundation
import XCTest
@testable import PerformanceCore

final class FanInvestigationTests: XCTestCase {
    func testFanComparisonMeasuresRPMWithoutCPUAttribution() {
        let text = FanInvestigation.compareFanSpeeds(before: fanCapture(rpm: 5_000), after: fanCapture(rpm: 2_000))
        XCTAssertTrue(text.contains("Fan 1: average 5000 → 2000 RPM"), text)
        XCTAssertTrue(text.contains("cause of any change remain unproven"))
        XCTAssertTrue(FanInvestigation.compareFanSpeeds(before: fanCapture(rpm: 5_000), after: fanCapture(rpm: nil)).contains("unavailable"))
        XCTAssertTrue(FanInvestigation.compareFanSpeeds(before: fanCapture(rpm: 5_000), after: fanCapture(rpm: 2_000, name: "Fan 2")).contains("unavailable in one recording"))
    }

    func testFanComparisonRejectsSparseCoverageAndDuplicateSamples() {
        let before = fanCapture(rpm: 5_000)
        let single = DiagnosticCapture(startedAt: before.startedAt, endedAt: before.endedAt,
                                      samples: Array(repeating: before.samples[0], count: 12))
        XCTAssertTrue(FanInvestigation.compareFanSpeeds(before: before, after: single).contains("unavailable"))
    }

    private func fanCapture(rpm: Double?, name: String = "Fan 1") -> DiagnosticCapture {
        let samples = (0..<12).map { index in
            let hardware = HardwareEvidence(fans: [.init(name: name, rpm: rpm, maximumRPM: 6_000)],
                cpuSensorMaximumCelsius: nil, gpuSensorMaximumCelsius: nil, cpuSensorCount: 0, gpuSensorCount: 0,
                gpuUtilizationPercent: nil, source: "Test")
            let incident = IncidentSampleEvidence(logicalCPUs: 8, pressure: "Normal", foreground: nil,
                workloads: [], readableProcesses: 0, unavailableProcesses: 0, scanSeconds: 0, hardware: hardware,
                newlyObservedProcesses: 0, noLongerObservedProcesses: 0)
            return SystemSample(timestamp: Date(timeIntervalSince1970: Double(index)), usedCPUCores: nil,
                memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil, thermal: .nominal, processes: [], incident: incident)
        }
        return capture(samples)
    }

    func testSustainedCPUIdentifiesRecordedContributorWithoutProvingFanCause() {
        let result = FanInvestigation.analyze(capture((0..<12).map { sample($0, cpu: 3) }))
        XCTAssertTrue(result.sustainedCPU)
        XCTAssertEqual(result.contributors.first?.name, "compiler")
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.cpuTrend, .steady)
        XCTAssertTrue(result.limitations.contains("Fan RPM"))
        XCTAssertTrue(result.explanation.contains("not whole-machine saturation"))
    }

    func testNominalThermalsAndQuietCPUDoNotMeanQuietFan() {
        let result = FanInvestigation.analyze(capture((0..<12).map { sample($0, cpu: 0.1) }))
        XCTAssertFalse(result.sustainedCPU)
        XCTAssertTrue(result.explanation.contains("does not prove a quiet fan"))
        XCTAssertEqual(result.confidence, .low)
    }

    func testThermalPressureSurvivesUnavailableCPU() {
        let result = FanInvestigation.analyze(capture((0..<12).map { sample($0, cpu: nil, thermal: .critical) }))
        XCTAssertEqual(result.peakThermal, .critical)
        XCTAssertNil(result.averageCPUCores)
        XCTAssertTrue(result.headline.contains("source is unresolved"))
        XCTAssertEqual(result.cpuTrend, .unavailable)
    }

    func testDuplicatesInvalidSamplesSpikesAndLongGapsCannotClaimSustainedWork() {
        let duplicate = sample(0, cpu: 3)
        for samples in [[duplicate, duplicate], [sample(0, cpu: 3), sample(20, cpu: 3)],
                        (0..<12).map { sample($0, cpu: $0 == 0 ? 8 : 0.1) },
                        (0..<12).map { sample($0, cpu: $0 < 6 ? 3 : .nan) }] {
            XCTAssertFalse(FanInvestigation.analyze(capture(samples)).sustainedCPU)
        }
        let invalid = FanInvestigation.analyze(capture([sample(-1, cpu: 3), sample(100, cpu: 3)]))
        XCTAssertEqual(invalid.sampleCount, 0)
    }

    func testSettlingCPUDoesNotClaimFanImprovement() {
        let result = FanInvestigation.analyze(capture((0..<12).reversed().map { sample($0, cpu: $0 < 6 ? 3 : 0.1) }))
        XCTAssertEqual(result.cpuTrend, .settling)
        XCTAssertTrue(result.nextCheck.contains("Fan speed was not measured"))
    }

    func testPowerConstraintsAreNotInventedThermalPressure() {
        let samples = (0..<12).map { index in
            SystemSample(timestamp: Date(timeIntervalSince1970: Double(index)), usedCPUCores: 0.1,
                         memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil,
                         thermal: .nominal, processes: [],
                         power: .init(lowPowerMode: true, cpuSpeedLimitPercent: 50, schedulerLimitPercent: nil))
        }
        let result = FanInvestigation.analyze(capture(samples))
        XCTAssertEqual(result.constrainedPowerSampleCount, 12)
        XCTAssertEqual(result.powerLimitSampleCount, 12)
        XCTAssertEqual(result.peakThermal, .nominal)
        XCTAssertTrue(result.limitations.contains("not clock measurements"))
    }

    func testUnavailablePowerIsNotAnUnconstrainedReading() {
        let result = FanInvestigation.analyze(capture((0..<12).map { sample($0, cpu: 0.1) }))
        XCTAssertEqual(result.powerLimitSampleCount, 0)
        XCTAssertEqual(result.constrainedPowerSampleCount, 0)
    }

    func testShortCoveredBurstInsideLongCaptureCannotExplainWholeWindow() {
        let result = FanInvestigation.analyze(.init(startedAt: Date(timeIntervalSince1970: 0),
                                                   endedAt: Date(timeIntervalSince1970: 120),
                                                   samples: (0..<12).map { sample($0, cpu: 3) }))
        XCTAssertFalse(result.sustainedCPU)
        XCTAssertEqual(result.cpuTrend, .unavailable)
    }

    private func capture(_ samples: [SystemSample]) -> DiagnosticCapture {
        .init(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 12), samples: samples)
    }
    private func sample(_ t: Int, cpu: Double?, thermal: ThermalCondition = .nominal) -> SystemSample {
        .init(timestamp: Date(timeIntervalSince1970: Double(t)), usedCPUCores: cpu,
              memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil, thermal: thermal,
              processes: [.init(id: 42, parentID: 1, name: "compiler", cpuCores: 2, residentBytes: 100)])
    }
}
