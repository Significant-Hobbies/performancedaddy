import AppKit
import PerformanceCore
import ServiceManagement
@testable import PerformanceDaddy
import XCTest

@MainActor
final class MenuLifecycleTests: XCTestCase {
    func testClosingLastWindowKeepsTheMenuAppAvailable() {
        let delegate = PerformanceDaddyDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertTrue(DaddyQuitReview.shouldQuit(appName: "PerformanceDaddy", activeWork: nil))
    }

    func testQuitReviewCoversRecordingAndReviewedActions() {
        XCTAssertNil(PerformanceActiveWork.description(isRecording: false, performingAction: false))
        XCTAssertEqual(PerformanceActiveWork.description(isRecording: true, performingAction: false),
                       "A diagnosis recording is still running.")
        XCTAssertEqual(PerformanceActiveWork.description(isRecording: false, performingAction: true),
                       "A reviewed action is still running.")
    }

    func testMenuDoesNotClaimADiagnosisBeforeOneIsRecorded() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceDaddy-menu-\(UUID().uuidString).json")
        let model = DiagnosisViewModel(historyStore: DiagnosticHistoryStore(fileURL: fixture))
        XCTAssertEqual(model.menuStatus, "No diagnosis recorded yet")
    }

    func testCompletionNoticesPostOnlyWhenEnabledAndNoWindowIsVisible() {
        XCTAssertTrue(DaddyCompletionNotices.shouldPost(enabled: true, hasVisibleWindow: false))
        XCTAssertFalse(DaddyCompletionNotices.shouldPost(enabled: true, hasVisibleWindow: true))
        XCTAssertFalse(DaddyCompletionNotices.shouldPost(enabled: false, hasVisibleWindow: false))
    }

    func testCompletionNoticesStayOffWithoutABundledApp() async throws {
        let suite = "PerformanceDaddy-notices-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(DaddyCompletionNotices.isAvailable)
        let enabled = await DaddyCompletionNotices.setEnabled(true, defaults: defaults)
        XCTAssertFalse(enabled)
        XCTAssertFalse(DaddyCompletionNotices.isEnabled(defaults))
    }

    func testLaunchAtLoginReflectsTheSystemStateAfterEachChange() {
        var status = SMAppService.Status.notRegistered
        var failRegister = false
        var registeredStatus = SMAppService.Status.enabled
        let login = DaddyLaunchAtLogin(service: .init(
            status: { status },
            register: {
                if failRegister { throw CocoaError(.featureUnsupported) }
                status = registeredStatus
            },
            unregister: { status = .notRegistered }
        ))
        XCTAssertFalse(login.isEnabled)
        login.set(true)
        XCTAssertTrue(login.isEnabled)
        XCTAssertNil(login.message)
        login.set(false)
        XCTAssertFalse(login.isEnabled)
        failRegister = true
        login.set(true)
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(login.message, DaddyLaunchAtLogin.failureMessage)
        failRegister = false
        registeredStatus = .requiresApproval
        login.set(true)
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(login.message, DaddyLaunchAtLogin.approvalMessage)
    }
}
