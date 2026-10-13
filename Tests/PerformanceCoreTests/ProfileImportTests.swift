import XCTest
@testable import PerformanceCore

final class ProfileImportTests: XCTestCase {
    func testEventLoopWaitIsNotDiagnosedAsHangAndCountsAreNotDoubleCounted() throws {
        let text = """
        Analysis of sampling Fixture
        Call graph:
            10 Thread_0: Main Thread
            + 10 NSApplication run
            + ! 10 nextEventMatchingMask
            + !   10 CFRunLoopServiceMachPort
            + !     10 mach_msg_trap
        Total number in stack
        """
        let report = try ProfileImporter.parse(Data(text.utf8))
        XCTAssertEqual(report.threads.first?.totalWeight, 10)
        XCTAssertTrue(report.threads.first?.interpretation.contains("normal event-loop") == true)
        XCTAssertTrue(report.limitation.contains("not CPU percentages"))
    }
    func testSiblingBranchesAndResidualWeightsArePreserved() throws {
        let text = """
        Call graph:
            10 Thread_0: Main Thread
            + 10 applicationAction
            + ! 4 os_unfair_lock_lock
            + : 5 compute
        """
        let thread = try XCTUnwrap(ProfileImporter.parse(Data(text.utf8)).threads.first)
        XCTAssertEqual(thread.totalWeight, 10)
        XCTAssertEqual(thread.stacks.count, 3)
    }
    func testLockWaitIsEvidenceWithUnknownOwnerAndNoInventedDuration() throws {
        let text = """
        Call graph:
            10 Thread_0: Main Thread
            + 10 applicationAction
            + ! 10 semaphore_wait_trap
        """
        let report = try ProfileImporter.parse(Data(text.utf8))
        XCTAssertTrue(report.threads[0].interpretation.contains("owner"))
        XCTAssertTrue(report.limitation.contains("continuous hang duration"))
    }
    func testTraceExportKeepsSameNamedWorkloadsOnSeparateTracks() throws {
        let date = Date(); var builder = SnapshotEvidenceBuilder()
        let processes = [LiveProcess(id: .init(pid: 20, started: 100), parent: 1, uid: 501, name: "Example", executable: "/a/Example.app/Contents/MacOS/Example", directory: "", cpu: 100, memory: 100),
                         LiveProcess(id: .init(pid: 21, started: 100), parent: 1, uid: 501, name: "Example", executable: "/b/Example.app/Contents/MacOS/Example", directory: "", cpu: 100, memory: 100)]
        let base = SystemSample(timestamp: date, usedCPUCores: 2, memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: nil, thermal: .nominal, processes: [])
        let sample = builder.sample(LiveSnapshot(date: date, processes: processes, system: base, pressure: "Normal", compressed: nil, unavailableProcesses: 0, portsDate: .distantPast, scanSeconds: 0))
        let data = try IncidentTraceExport.data(DiagnosticCapture(startedAt: date, endedAt: date, samples: [sample]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try XCTUnwrap(object["traceEvents"] as? [[String: Any]])
        let tracks = events.filter { $0["name"] as? String == "CPU cores" }.compactMap { $0["pid"] as? Int }
        XCTAssertEqual(Set(tracks).count, 2)
    }

    func testMixedTimeUnitsRemainAttachedToTheirOwnThreads() throws {
        let text = """
        {"shared":{"frames":[{"name":"work"}]},"profiles":[{"type":"sampled","name":"one","unit":"seconds","startValue":0,"endValue":1,"samples":[[0]],"weights":[1]},{"type":"sampled","name":"two","unit":"milliseconds","startValue":0,"endValue":10,"samples":[[0]],"weights":[10]}]}
        """
        let profile = try ProfileImporter.parse(Data(text.utf8))
        XCTAssertEqual(profile.threads.map(\.unit), ["seconds", "milliseconds"])
        XCTAssertEqual(profile.threads.map(\.totalWeight), [1,10])
    }

    func testSpeedscopeUnitsIndicesAndThreadRoleAreValidated() throws {
        let good = """
        {"shared":{"frames":[{"name":"work"}]},"profiles":[{"type":"sampled","name":"worker","unit":"milliseconds","startValue":0,"endValue":10,"samples":[[0]],"weights":[10]}]}
        """
        let report = try ProfileImporter.parse(Data(good.utf8))
        XCTAssertFalse(report.threads[0].isMain)
        XCTAssertEqual(report.unit, "milliseconds")
        for bad in [good.replacingOccurrences(of: "[[0]]", with: "[[9]]"), good.replacingOccurrences(of: "milliseconds", with: "bytes"), good.replacingOccurrences(of: "[10]", with: "[-1]"), good.replacingOccurrences(of: "[10]", with: "[]"), good.replacingOccurrences(of: "[10]", with: "[true]"), good.replacingOccurrences(of: "[[0]]", with: "[[false]]")] {
            XCTAssertThrowsError(try ProfileImporter.parse(Data(bad.utf8)))
        }
        XCTAssertThrowsError(try ProfileImporter.parse(Data("{\"threads\":[]}".utf8)))
    }
}
