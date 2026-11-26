import PerformanceCore
@testable import PerformanceDaddy
import XCTest

@MainActor
final class PerformanceWorkspaceRoutingTests: XCTestCase {
    func testOnlyRegisteredLoadNotificationCategoriesReachPerformanceActions() {
        for category in LoadAlertCenter.notificationCategories {
            XCTAssertTrue(LoadAlertCenter.acceptsCategory(category.identifier))
        }
        XCTAssertFalse(LoadAlertCenter.acceptsCategory(""))
        XCTAssertFalse(LoadAlertCenter.acceptsCategory("browser.alert"))
    }

    func testFiltersAndTableSortAreScopedToTheActiveRoute() throws {
        let suite = "performance.routing." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = PerformanceWorkspaceSession(preferences: defaults)
        session.enter(.memory)
        let memorySort = [KeyPathComparator(\LiveProcess.memory, order: .reverse)]
        XCTAssertEqual(session.live.sortOrder, memorySort)
        session.live.search = "restricted"
        session.live.selection = [ProcessIdentity(pid: 77, started: 12)]
        let customSort = [KeyPathComparator(\LiveProcess.sortName)]
        session.live.sortOrder = customSort
        session.enter(.memory)
        XCTAssertEqual(session.live.search, "restricted")
        XCTAssertEqual(session.live.sortOrder, customSort)
        session.enter(.ports)
        XCTAssertTrue(session.live.search.isEmpty)
        XCTAssertTrue(session.live.selection.isEmpty)
        XCTAssertTrue(session.live.inspectPorts)
        XCTAssertEqual(session.live.sortOrder, [KeyPathComparator(\LiveProcess.sortPort)])
        session.enter(.alerts)
        XCTAssertFalse(session.live.inspectPorts)
    }
}
