import SwiftUI

@main
struct PerformanceDaddyApp: App {
    init() {
        if CommandLine.arguments.dropFirst().first == "--agent-hook" {
            AgentHookCommand.run()
            exit(0)
        }
    }
    @NSApplicationDelegateAdaptor(PerformanceDaddyDelegate.self) private var delegate
    @StateObject private var live = LiveViewModel()
    @StateObject private var diagnosis = DiagnosisViewModel()
    @StateObject private var updates = AppUpdates()
    @StateObject private var alerts = LoadAlertCenter()
    @StateObject private var login = DaddyLaunchAtLogin()
    var body: some Scene {
        Window("PerformanceDaddy", id: "main") {
            DashboardView(model: diagnosis, live: live)
                .frame(minWidth: 980, minHeight: 800)
                .background(MonitoringSurface(model: live))
                .task { updates.start(live: live, diagnosis: diagnosis) }
                .onAppear(perform: reviewActiveWorkBeforeQuit)
        }
        .defaultSize(width: 1_180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                DaddyUpdateMenu(updates: updates)
            }
        }
        WindowGroup(id: "agent-wall") {
            AgentWallView(model: live)
                .frame(minWidth: 520, minHeight: 360)
                .background(MonitoringSurface(model: live))
                .task { live.start() }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra {
            AgentStatusMenu(model: live, diagnosis: diagnosis, updates: updates, login: login)
                .background(MonitoringSurface(model: live))
        } label: {
            AgentStatusMenuBarLabel(model: live, alerts: alerts)
                .onAppear(perform: reviewActiveWorkBeforeQuit)
        }
        .menuBarExtraStyle(.window)
        Settings {
            LoadAlertSettingsView(alerts: alerts)
        }
    }

    /// The menu bar label lives for the whole session, so quitting from the
    /// menu or Dock reviews work even when the main window was never opened.
    private func reviewActiveWorkBeforeQuit() {
        delegate.activeWork = { [diagnosis, live] in
            PerformanceActiveWork.description(isRecording: diagnosis.isRecording, performingAction: live.performingAction)
        }
    }
}

enum PerformanceActiveWork {
    static func description(isRecording: Bool, performingAction: Bool) -> String? {
        if isRecording { return "A diagnosis recording is still running." }
        if performingAction { return "A reviewed action is still running." }
        return nil
    }
}

@MainActor
final class PerformanceDaddyDelegate: NSObject, NSApplicationDelegate {
    var activeWork: (() -> String?)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = PerformanceAppIcon.image { NSApplication.shared.applicationIconImage = icon }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DaddyQuitReview.shouldQuit(appName: "PerformanceDaddy", activeWork: activeWork?()) ? .terminateNow : .terminateCancel
    }
}

@MainActor
enum PerformanceAppIcon {
    static let image = DecodedArtwork.image(url: DaddyResources.url(forResource: "PerformanceDaddy"), maximumPixels: 256)
}
