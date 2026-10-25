import AppKit
@testable import PerformanceDaddy
import XCTest

@MainActor
final class MonitoringSurfaceTests: XCTestCase {
    func testSettingsVisibilityDoesNotTurnOnForegroundSampling() {
        let model = LiveViewModel()
        let window = FixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        let view = MonitoringSurface.SurfaceView(model: model, tracksSampling: false)
        window.contentView = view
        XCTAssertFalse(model.hasVisibleSurface)
        XCTAssertEqual(model.automaticRefreshInterval, 30)
        window.contentView = nil
    }

    func testClosedRetainedWindowCanReportOpenAgain() async {
        let model = LiveViewModel()
        var openings: [Bool] = []
        let window = FixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        let view = MonitoringSurface.SurfaceView(model: model, onWindowOpen: { openings.append($0) })
        window.contentView = view
        await Task.yield()
        window.open = false
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await Task.yield()
        XCTAssertFalse(model.hasVisibleSurface)
        XCTAssertEqual(openings.last, false)
        window.open = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await Task.yield()
        XCTAssertTrue(model.hasVisibleSurface)
        XCTAssertEqual(openings.last, true)
        window.contentView = nil
    }

    func testHiddenHealthyMonitoringBacksOffAndVisibleMonitoringStaysResponsive() {
        let model = LiveViewModel()
        XCTAssertEqual(model.automaticRefreshInterval, 30)
        model.needsCloserMonitoring = true
        XCTAssertEqual(model.automaticRefreshInterval, 10)
        let first = UUID(), second = UUID()
        model.setSurfaceVisible(first, visible: true)
        XCTAssertEqual(model.automaticRefreshInterval, 5)
        model.setSurfaceVisible(second, visible: true)
        model.setSurfaceVisible(first, visible: false)
        XCTAssertEqual(model.automaticRefreshInterval, 5)
        model.setSurfaceVisible(second, visible: false)
        XCTAssertEqual(model.automaticRefreshInterval, 10)
        model.needsCloserMonitoring = false
        XCTAssertEqual(model.automaticRefreshInterval, 30)
    }

    func testWindowOcclusionMinimizationAndDetachUpdateIndependentVisibility() {
        let model = LiveViewModel()
        let window = FixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        let view = MonitoringSurface.SurfaceView(model: model)
        window.contentView = view
        XCTAssertTrue(model.hasVisibleSurface)
        window.minimized = true
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        XCTAssertFalse(model.hasVisibleSurface)
        window.minimized = false
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        XCTAssertTrue(model.hasVisibleSurface)
        window.unoccluded = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertFalse(model.hasVisibleSurface)
        window.unoccluded = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertTrue(model.hasVisibleSurface)
        window.contentView = nil
        XCTAssertFalse(model.hasVisibleSurface)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertFalse(model.hasVisibleSurface)
    }

    func testOrderingOutPreservesDashboardUntilTheWindowActuallyCloses() async {
        let model = LiveViewModel()
        var openings: [Bool] = []
        let window = FixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        let view = MonitoringSurface.SurfaceView(model: model, onWindowOpen: { openings.append($0) })
        window.contentView = view
        await Task.yield()
        XCTAssertEqual(openings.last, true)
        window.open = false
        window.unoccluded = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await Task.yield()
        XCTAssertFalse(model.hasVisibleSurface)
        XCTAssertEqual(openings.last, true)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await Task.yield()
        XCTAssertEqual(openings.last, false)
        window.contentView = nil
    }

    private final class FixtureWindow: NSWindow {
        var open = true
        var minimized = false
        var unoccluded = true
        override var isVisible: Bool { open }
        override var isMiniaturized: Bool { minimized }
        override var occlusionState: NSWindow.OcclusionState { unoccluded ? [.visible] : [] }
    }
}
