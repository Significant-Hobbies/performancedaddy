import Foundation
import XCTest
@testable import PerformanceCore

final class AttributionTests: XCTestCase {
    private func process(_ pid: Int32, _ parent: Int32 = 1, start: UInt64 = 1,
                         name: String = "node", path: String = "/usr/local/bin/node", cpu: Double? = 100) -> LiveProcess {
        LiveProcess(id: .init(pid: pid, started: start), parent: parent, uid: 501,
                    name: name, executable: path, directory: "", cpu: cpu, memory: 0)
    }
    func testIdleAppParentAndNestedHelpersShareBundleWithoutDoubleCounting() {
        let rows = [process(10, name: "Browser", path: "/Applications/Browser.app/Contents/MacOS/Browser", cpu: 0),
                    process(11, 10, path: "/Applications/Browser.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper", cpu: 200)]
        let grouped = RecordedWorkload.group(rows + [rows[1]])
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].name, "Browser & helpers")
        XCTAssertEqual(grouped[0].cpuCores, 2)
        XCTAssertEqual(grouped[0].processCount, 2)
        XCTAssertFalse(grouped[0].id.contains("/Applications"))
    }
    func testSameNamedSiblingsAndAgentLaunchesStayDistinct() {
        let rows = [process(10, name: "Terminal", path: "/Applications/Terminal.app/Contents/MacOS/Terminal", cpu: 0),
                    process(11, 10, name: "codex", path: "/usr/local/bin/codex", cpu: 0),
                    process(12, 10, name: "codex", path: "/usr/local/bin/codex", cpu: 0),
                    process(13, 11, cpu: 200), process(14, 12, cpu: 100), process(15), process(16)]
        let grouped = RecordedWorkload.group(rows)
        XCTAssertEqual(grouped.filter { $0.name.hasPrefix("Codex") }.count, 2)
        XCTAssertEqual(grouped.filter { $0.name.hasPrefix("node") }.count, 2)
        XCTAssertEqual(grouped.first?.cpuCores, 2)
    }
    func testReusedParentCannotInventOwnership() {
        let grouped = RecordedWorkload.group([process(10, start: 20, name: "codex", path: "/bin/codex", cpu: 0),
                                              process(11, 10, start: 10)])
        XCTAssertEqual(grouped.first?.name, "node · PID 11")
    }
    func testTerminalAncestryIsLabeledLaunchContext() {
        let grouped = RecordedWorkload.group([process(10, name: "Warp", path: "/Applications/Warp.app/Contents/MacOS/Warp", cpu: 0), process(11, 10)])
        XCTAssertEqual(grouped.first?.name, "Warp-launched work")
        XCTAssertTrue(grouped.first?.association.contains("does not identify") == true)
    }
    private func capture(workloadCPU: Double, systemCPU: Double = 4, thermal: ThermalCondition = .fair) -> DiagnosticCapture {
        let samples = (0..<12).map { i in
            SystemSample(timestamp: Date(timeIntervalSince1970: Double(i)), usedCPUCores: systemCPU,
                         memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil, thermal: thermal,
                         processes: [], workloads: [.init(id: "app:test", name: "Browser & helpers", association: "App path", cpuCores: workloadCPU, processCount: 3)])
        }
        return .init(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 12), samples: samples)
    }
    func testMaterialContributorLeadsAndThermalLinkRemainsAssociation() {
        let result = FanInvestigation.analyze(capture(workloadCPU: 3))
        XCTAssertTrue(result.headline.contains("Browser"))
        XCTAssertTrue(result.explanation.contains("75%"))
        XCTAssertEqual(result.confidence, .medium)
        XCTAssertTrue(result.evidenceLinks[1].contains("does not prove"))
        XCTAssertTrue(result.evidenceLinks[2].contains("unresolved"))
    }
    func testTinyNamedContributorCannotExplainLargeSystemLoad() {
        let result = FanInvestigation.analyze(capture(workloadCPU: 0.1, systemCPU: 8))
        XCTAssertEqual(result.confidence, .low)
        XCTAssertFalse(result.headline.contains("Browser"))
        XCTAssertTrue(result.workloadCoverage.contains("unattributed"))
    }
    func testFollowupNamesTargetAndRequiresEqualDuration() {
        let before = capture(workloadCPU: 3)
        let after = capture(workloadCPU: 0.1, systemCPU: 0.3, thermal: .nominal)
        let text = FanInvestigation.compareWorkload(before: before, after: after)
        XCTAssertTrue(text.contains("Browser"))
        XCTAssertTrue(text.contains("declined together"))
        XCTAssertTrue(text.contains("Fan improvement remains unmeasured"))
        let short = DiagnosticCapture(startedAt: after.startedAt, endedAt: after.startedAt.addingTimeInterval(3), samples: after.samples)
        XCTAssertTrue(FanInvestigation.compareWorkload(before: before, after: short).contains("equally long"))
    }
    func testOneWorkloadSpikeCannotBeCalledSustainedContributor() {
        let original = capture(workloadCPU: 0, systemCPU: 2)
        let samples = original.samples.enumerated().map { index, sample in
            SystemSample(timestamp: sample.timestamp, usedCPUCores: 2, memoryHeadroomRatio: nil,
                         swapUsedBytes: nil, diskFreeBytes: nil, thermal: .fair, processes: [],
                         workloads: [.init(id: "spike", name: "Burst", association: "App path", cpuCores: index == 0 ? 12 : 0, processCount: 1)])
        }
        let result = FanInvestigation.analyze(.init(startedAt: original.startedAt, endedAt: original.endedAt, samples: samples))
        XCTAssertEqual(result.confidence, .low)
        XCTAssertFalse(result.headline.contains("leading"))
    }
    func testOldCaptureDecodesWithoutWorkloads() throws {
        let data = Data(#"{"timestamp":0,"thermal":"nominal","processes":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(SystemSample.self, from: data).workloads)
    }
    func testNativeFirstReadHasNoInventedCPUOrPathsInStoredWorkloads() throws {
        var sampler = AttributionSampler()
        let reading = sampler.read()
        XCTAssertTrue(reading.processes.isEmpty)
        XCTAssertNil(reading.observerCPU)
        XCTAssertTrue(reading.workloads.isEmpty)
    }
}
