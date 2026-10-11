import Foundation
@testable import PerformanceCore
import XCTest

final class ProcessUnderstandingTests: XCTestCase {
    private func process(_ pid: Int32 = 42, start: UInt64 = 1_000_000, path: String = "/opt/tool", uid: UInt32 = 501) -> LiveProcess {
        LiveProcess(id: .init(pid: pid, started: start), parent: 1, uid: uid, name: "tool", executable: path, directory: "", cpu: nil, memory: 0)
    }
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    func testStartDateUsesKernelMicrosecondsAndRejectsUnavailableOrFutureEvidence() throws {
        let identity = process(start: 1_750_000).id
        let started = try XCTUnwrap(ProcessUnderstanding.startDate(identity, at: date(11)))
        XCTAssertEqual(started.timeIntervalSince1970, 1.75)
        XCTAssertEqual(ProcessUnderstanding.duration(identity, at: date(11)), 9.25)
        XCTAssertNil(ProcessUnderstanding.startDate(process(start: 0).id, at: date(11)))
        XCTAssertNil(ProcessUnderstanding.startDate(process(start: 20_000_000).id, at: date(11)))
        XCTAssertNil(ProcessUnderstanding.startDate(identity, at: date(.infinity)))
    }

    func testDurationAndAppAssociationRejectInvalidEvidence() {
        XCTAssertNotNil(ProcessUnderstanding.catalogDescription(executable: "/usr/sbin/cfprefsd"))
        XCTAssertNil(ProcessUnderstanding.catalogDescription(executable: "/tmp/cfprefsd"))
        XCTAssertNil(ProcessUnderstanding.catalogDescription(executable: "/usr/sbin/cfprefsd-backup"))
        XCTAssertEqual(ProcessUnderstanding.duration(process().id, at: date(11)), 10)
        XCTAssertNil(ProcessUnderstanding.duration(process(start: 0).id, at: date(11)))
        XCTAssertNil(ProcessUnderstanding.duration(process(start: 20_000_000).id, at: date(11)))
        XCTAssertEqual(ProcessUnderstanding.appPath(for: "/Applications/Browser.app/Contents/Helpers/Child.app/Contents/MacOS/Child"), "/Applications/Browser.app")
        XCTAssertNil(ProcessUnderstanding.appPath(for: "/Applications/Browser.app/../tool"))
        XCTAssertNil(ProcessUnderstanding.appPath(for: "/opt/tool"))
    }

    func testJournalRejectsFailedSignalsAndExistingSiblingsAndDeduplicates() {
        var journal = ProcessLifecycleJournal()
        let original = process()
        journal.record(original, at: date(10), force: false, signalSent: false, observed: [original])
        XCTAssertTrue(journal.events.isEmpty)
        let sibling = process(43, start: 2_000_000)
        journal.record(original, at: date(10), force: false, signalSent: true, observed: [original, sibling])
        journal.observe([sibling], at: date(11))
        XCTAssertEqual(journal.events.count, 2)
        XCTAssertTrue(journal.events.last!.text.contains("not confirmed"))
        let replacement = process(42, start: 12_000_000)
        journal.observe([sibling, replacement], at: date(13))
        XCTAssertEqual(journal.events.count, 3)
        XCTAssertTrue(journal.events.last!.text.contains("does not prove"))
        journal.observe([sibling, replacement], at: date(14))
        XCTAssertEqual(journal.events.count, 3)
    }

    func testJournalRejectsDifferentUserPathAndFutureStartAndSurvivesGapsHonestly() {
        var journal = ProcessLifecycleJournal()
        journal.record(process(), at: date(10), force: true, signalSent: true, observed: [])
        journal.observe([process(43, start: 12_000_000, uid: 502), process(44, start: 12_000_000, path: "/other/tool"), process(45, start: 100_000_000)], at: date(20))
        XCTAssertEqual(journal.events.count, 2)
        journal.observe([process(46, start: 30_000_000)], at: date(80))
        XCTAssertEqual(journal.events.count, 3)
        XCTAssertTrue(journal.events.last!.text.contains("Launch cause unknown"))
        journal.observe([], at: date(90_000))
        XCTAssertTrue(journal.events.isEmpty)
    }

    func testMultipleCandidatesAreAmbiguousAndRetentionBounded() {
        var journal = ProcessLifecycleJournal()
        journal.record(process(), at: date(10), force: false, signalSent: true, observed: [])
        journal.observe([process(43, start: 12_000_000), process(44, start: 12_000_000)], at: date(13))
        XCTAssertTrue(journal.events.suffix(2).allSatisfy { $0.text.contains("ambiguous") })
        for pid in 100...700 {
            journal.record(process(Int32(pid)), at: date(20), force: false, signalSent: true, observed: [])
        }
        XCTAssertEqual(journal.events.count, 500)
    }

    func testExpiryDoesNotRequireSamplingAndWatchCapIsBounded() {
        var journal = ProcessLifecycleJournal()
        for pid in 1...101 {
            journal.record(process(Int32(pid), path: "/tool/\(pid)"), at: date(10), force: false, signalSent: true, observed: [])
        }
        journal.observe([], at: date(11))
        XCTAssertEqual(journal.events.count, 201) // 101 signals + only 100 watched missing observations.
        journal.expire(at: date(86_412))
        XCTAssertTrue(journal.events.isEmpty)
    }

    func testStartupPolicyRequiresExactExecutableAndPreservesConditionalPolicy() throws {
        let dictionary: [String: Any] = ["ProgramArguments": ["/opt/tool", "private argument"], "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "EnvironmentVariables": ["SECRET": "not displayed"]]
        let policy = try XCTUnwrap(StartupPolicy.parse(dictionary, executable: "/opt/tool", source: "fixture.plist", context: "User agent"))
        XCTAssertTrue(policy.launch.contains("not proof"))
        XCTAssertTrue(policy.keepAlive.contains("Conditional"))
        XCTAssertNil(StartupPolicy.parse(dictionary, executable: "/another/tool", source: "fixture", context: "agent"))
        XCTAssertNil(StartupPolicy.parse(["BundleProgram": "../tool"], executable: "/tool", source: "fixture", context: "agent", bundle: "/App.app"))
        let numeric = try XCTUnwrap(StartupPolicy.parse(["Program": "/opt/tool", "RunAtLoad": 1], executable: "/opt/tool", source: "fixture", context: "agent"))
        XCTAssertTrue(numeric.launch.hasPrefix("No verified"))
    }

    func testBoundedReaderRejectsSymlinkAndOversize() throws {
        let root = URL(fileURLWithPath: "/private/tmp/pd-understanding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.plist")
        try Data("test".utf8).write(to: file)
        XCTAssertEqual(ProcessMetadataReader.readRegularFile(file.path), Data("test".utf8))
        let link = root.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNil(ProcessMetadataReader.readRegularFile(link.path))
        try Data(repeating: 0, count: 131_073).write(to: file)
        XCTAssertNil(ProcessMetadataReader.readRegularFile(file.path))
    }

    func testLifecycleEventStoreRestoresOnlyBoundedValidRecentEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-lifecycle-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("events.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LifecycleHistoryStore(fileURL: file)
        let now = date(100_000)
        let valid = ProcessLifecycleJournal.Event(date: date(99_999), executable: "/opt/tool", uid: 501,
            text: "Stop signal sent; exit not yet confirmed.")
        let expired = ProcessLifecycleJournal.Event(date: date(1), executable: "/opt/tool", uid: 501,
            text: "Expired")
        let unsafe = ProcessLifecycleJournal.Event(date: date(99_999), executable: "relative/tool", uid: 501,
            text: "Unsafe")
        try await store.save([expired, valid, unsafe], at: now)
        let restored = await store.load(at: now)
        XCTAssertEqual(restored.map(\.id), [valid.id])
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        var journal = ProcessLifecycleJournal(events: restored, at: now)
        XCTAssertEqual(journal.events.count, 1)
        journal.observe([], at: now)
        XCTAssertEqual(journal.events.count, 1, "restored events must not resume old watches")
    }
}
