import Darwin
import Foundation
@testable import PerformanceCore
import XCTest

final class PerformanceWatchdogTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testOneBusyCoreAlertsWithoutWholeMachineSaturation() {
        var detector = watchdog([.processCPU])
        var alerts: [LoadAlert] = []
        for second in stride(from: 0, through: 180, by: 30) {
            alerts += detector.observe(snapshot(second, cpu: 120), coreCount: 16)
        }
        XCTAssertEqual(alerts.map(\.kind), [.processCPU])
        XCTAssertEqual(alerts.first?.contributor?.name, "Example")
        XCTAssertEqual(alerts.first?.duration, 180)
        XCTAssertTrue(alerts.first?.detail?.contains("100% process CPU means one core") == true)
    }

    func testBusyHelpersStillCountWhenParentCPUIsUnavailable() {
        var detector = watchdog([.processCPU])
        var alerts: [LoadAlert] = []
        for second in stride(from: 0, through: 180, by: 30) {
            alerts += detector.observe(snapshot(second, cpu: nil, helperCPU: 120), coreCount: 16)
        }
        XCTAssertEqual(alerts.first?.contributor?.cpuCores, 1.2)
    }

    func testShortSpikesMissingReadingsAndRestartedIdentitiesBreakContinuity() {
        for interruption in ["spike", "missing", "restart", "gap", "duplicate"] {
            var detector = watchdog([.processCPU])
            for second in [0, 30, 60] { XCTAssertTrue(detector.observe(snapshot(second, cpu: 120), coreCount: 16).isEmpty) }
            let interrupted = interruption == "gap" ? 150 : interruption == "duplicate" ? 60 : 90
            XCTAssertTrue(detector.observe(snapshot(interrupted, cpu: interruption == "missing" ? nil : interruption == "spike" ? 0 : 120,
                                                    identity: interruption == "restart" ? 2 : 1), coreCount: 16).isEmpty)
            XCTAssertTrue(detector.observe(snapshot(interrupted + 30, cpu: 120), coreCount: 16).isEmpty, interruption)
        }
    }

    func testCustomLimitsAndMutedWorkloads() {
        var detector = watchdog([])
        detector.policy.limits["app:/Applications/Example.app"] = .init(name: "Example", cpuPercent: 50, memoryGB: 1)
        var alerts: [LoadAlert] = []
        for second in stride(from: 0, through: 180, by: 30) {
            alerts += detector.observe(snapshot(second, cpu: 60, memory: 2 << 30), coreCount: 16)
        }
        XCTAssertEqual(Set(alerts.map(\.kind)), [.processCPU, .largeMemory])
        detector.reset()
        for second in stride(from: 300, through: 600, by: 30) {
            XCTAssertTrue(detector.observe(snapshot(second, cpu: 600, memory: 2 << 30), coreCount: 16,
                                            ignored: ["app:/Applications/Example.app"]).isEmpty)
        }
    }

    func testGrowthRequiresBothAbsoluteAndRelativeIncreaseAndThreeReadings() {
        var detector = watchdog([.memoryGrowth])
        var alerts: [LoadAlert] = []
        for second in stride(from: 0, through: 300, by: 30) {
            alerts += detector.observe(snapshot(second, cpu: 0, memory: (1 << 30) + UInt64(second) * 4_000_000), coreCount: 16)
        }
        XCTAssertEqual(alerts.map(\.kind), [.memoryGrowth])
        XCTAssertTrue(alerts.first?.detail?.contains("not proof of a memory leak") == true)
        detector = watchdog([.memoryGrowth])
        for second in stride(from: 0, through: 600, by: 30) {
            XCTAssertTrue(detector.observe(snapshot(second, cpu: 0, memory: (8 << 30) + UInt64(second) * 1_000_000), coreCount: 16).isEmpty)
        }
    }

    func testGrowthUsesTrailingEvidenceAcrossWindowBoundaries() {
        var detector = watchdog([.memoryGrowth])
        for second in stride(from: 0, through: 300, by: 30) {
            XCTAssertTrue(detector.observe(snapshot(second, cpu: 0, memory: (1 << 30) + UInt64(second) * 1_400_000), coreCount: 16).isEmpty)
        }
        let alerts = detector.observe(snapshot(330, cpu: 0, memory: 2 << 30), coreCount: 16)
        XCTAssertEqual(alerts.map(\.kind), [.memoryGrowth])
        XCTAssertEqual(alerts.first?.duration, 300)
    }

    func testAHelperBecomingReadableCannotLookLikeMemoryGrowth() {
        var detector = watchdog([.memoryGrowth])
        for second in stride(from: 0, through: 300, by: 30) {
            XCTAssertTrue(detector.observe(snapshot(second, cpu: 0), coreCount: 16).isEmpty)
        }
        let sample = snapshot(330, cpu: 0)
        let helper = LiveProcess(id: .init(pid: 501, started: 1), parent: 500, uid: getuid(), name: "Helper",
            executable: "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
            directory: "/", cpu: 0, memory: 1 << 30)
        let returned = LiveSnapshot(date: sample.date, processes: sample.processes + [helper], system: sample.system,
            pressure: sample.pressure, compressed: nil, unavailableProcesses: 0, portsDate: sample.date, scanSeconds: 0.01)
        XCTAssertTrue(detector.observe(returned, coreCount: 16).isEmpty)
    }

    func testThermalAndFanAlertsAreIndependentAndNeverSupplyQuitTargets() {
        var detector = watchdog([.processCPU, .thermal, .fans])
        detector.policy.processSeconds = 60
        detector.policy.fanSeconds = 60
        var alerts: [LoadAlert] = []
        for second in [0, 30, 60] {
            alerts += detector.observe(snapshot(second, cpu: 120, thermal: .serious, rpm: 5_000, maximum: 5_500), coreCount: 16)
        }
        XCTAssertEqual(Set(alerts.map(\.kind)), [.processCPU, .thermal, .fans])
        let fan = alerts.first { $0.kind == .fans }
        XCTAssertNil(fan?.contributor)
        XCTAssertTrue(fan?.detail?.contains("5000 RPM") == true)
        XCTAssertTrue(fan?.detail?.contains("Example") == true)
        XCTAssertTrue(fan?.detail?.contains("does not identify fan-control ownership") == true)
        XCTAssertTrue(detector.observe(snapshot(90, cpu: 120, thermal: .serious, rpm: 5_000, maximum: 5_500), coreCount: 16).isEmpty)
    }

    func testUnreadableFanMaximumAndThermalStateCannotCreateAlerts() {
        var detector = watchdog([.fans, .thermal])
        for second in stride(from: 0, through: 300, by: 30) {
            XCTAssertTrue(detector.observe(snapshot(second, cpu: 0, thermal: .unavailable, rpm: 5_000, maximum: nil), coreCount: 16).isEmpty)
        }
        XCTAssertFalse(detector.needsCloserLook)
    }

    func testSystemMemoryIsNotSuppressedByCPUNotificationCooldown() {
        var detector = watchdog([])
        var alerts: [LoadAlert] = []
        for second in stride(from: 0, through: 180, by: 30) {
            alerts += detector.observe(snapshot(second, cpu: 200, used: 15, pressure: second >= 90 ? "Warning" : "Normal"), coreCount: 16)
        }
        XCTAssertEqual(Set(alerts.map(\.kind)), [.cpu, .memory])
    }

    func testQuietReadingsReleaseFasterSamplingAndResetDropsPendingEvidence() {
        var detector = watchdog([.processCPU])
        _ = detector.observe(snapshot(0, cpu: 120), coreCount: 16)
        XCTAssertTrue(detector.needsCloserLook)
        _ = detector.observe(snapshot(30, cpu: 0), coreCount: 16)
        XCTAssertFalse(detector.needsCloserLook)
        _ = detector.observe(snapshot(60, cpu: 120), coreCount: 16)
        detector.reset()
        XCTAssertFalse(detector.needsCloserLook)
        XCTAssertTrue(detector.observe(snapshot(180, cpu: 120), coreCount: 16).isEmpty)
    }

    func testRuleEvaluationWithThousandProcessesHasBoundedCost() {
        let processes = (0..<1_000).map { offset in
            LiveProcess(id: .init(pid: Int32(offset + 100), started: 1), parent: 1, uid: getuid(), name: "worker\(offset)",
                        executable: "/usr/local/bin/worker\(offset)", directory: "/", cpu: 10, memory: UInt64(offset) * 1_048_576)
        }
        let sample = snapshot(0, cpu: 0)
        let large = LiveSnapshot(date: origin, processes: processes, system: sample.system, pressure: "Normal",
                                 compressed: nil, unavailableProcesses: 0, portsDate: origin, scanSeconds: 0.01)
        measure {
            var detector = PerformanceWatchdog()
            XCTAssertTrue(detector.observe(large, coreCount: 16).isEmpty)
        }
    }

    private func watchdog(_ kinds: Set<LoadAlert.Kind>) -> PerformanceWatchdog {
        var detector = PerformanceWatchdog(); detector.policy.kinds = kinds; return detector
    }

    private func snapshot(_ second: Int, cpu: Double?, memory: UInt64 = 1 << 30, identity: UInt64 = 1,
                          helperCPU: Double? = nil, used: Double = 2, pressure: String = "Normal",
                          thermal: ThermalCondition = .nominal, rpm: Double? = nil, maximum: Double? = nil) -> LiveSnapshot {
        let date = origin.addingTimeInterval(TimeInterval(second))
        var processes = [LiveProcess(id: .init(pid: 500, started: identity), parent: 1, uid: getuid(), name: "Example",
            executable: "/Applications/Example.app/Contents/MacOS/Example", directory: "/", cpu: cpu, memory: memory)]
        if let helperCPU {
            processes.append(.init(id: .init(pid: 501, started: identity), parent: 500, uid: getuid(), name: "Helper",
                executable: "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", directory: "/", cpu: helperCPU, memory: 0))
        }
        let hardware = HardwareEvidence(fans: [FanEvidence(name: "Fan 1", rpm: rpm, maximumRPM: maximum)],
            cpuSensorMaximumCelsius: nil, gpuSensorMaximumCelsius: nil, cpuSensorCount: 0, gpuSensorCount: 0,
            gpuUtilizationPercent: nil, source: "Test")
        return LiveSnapshot(date: date, processes: processes,
            system: .init(timestamp: date, usedCPUCores: used, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                          diskFreeBytes: nil, thermal: thermal, processes: []),
            pressure: pressure, compressed: nil, unavailableProcesses: 0, portsDate: date, scanSeconds: 0.01, hardware: hardware)
    }
}
