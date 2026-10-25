import AppKit
@testable import PerformanceDaddy
import XCTest

@MainActor
final class MonitoringSurfaceTests: XCTestCase {
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

    private final class FixtureWindow: NSWindow {
        var minimized = false
        var unoccluded = true
        override var isVisible: Bool { true }
        override var isMiniaturized: Bool { minimized }
        override var occlusionState: NSWindow.OcclusionState { unoccluded ? [.visible] : [] }
    }
}
