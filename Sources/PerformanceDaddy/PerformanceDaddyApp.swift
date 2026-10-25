import SwiftUI

@main
enum PerformanceDaddyMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--agent-hook" {
            AgentHookCommand.run()
            return
        }
        if arguments.first == "--capture-diagnostic" {
            PerformanceDiagnosticCommand.run(arguments: arguments)
        }
        if DiagnosticCaptureOptions.hasPIDOption(arguments) {
            FileHandle.standardError.write(Data("--pid is supported only with --capture-diagnostic.\n".utf8))
            exit(2)
        }
        if CommandLine.arguments.contains("--check-ui-resources") {
            guard PerformanceUIResources.loaded else {
                FileHandle.standardError.write(Data("PerformanceDaddy UI resources missing or invalid\n".utf8))
                exit(EXIT_FAILURE)
            }
            print("PerformanceDaddy UI resources loaded")
            return
        }
        PerformanceDaddyApp.main()
    }
}

struct PerformanceDaddyApp: App {
    @NSApplicationDelegateAdaptor(PerformanceDaddyDelegate.self) private var delegate
    // Surfaces observe these services. The scene only owns their lifetime.
    @State private var live = LiveViewModel()
    @State private var diagnosis = DiagnosisViewModel()
    @State private var updates = AppUpdates()
    @State private var alerts = LoadAlertCenter()
    @State private var login = DaddyLaunchAtLogin()
    var body: some Scene {
        Window("PerformanceDaddy", id: "main") {
            DashboardWindowContent(diagnosis: diagnosis, live: live)
                .task { if !PerformanceStartupCheck.enabled { updates.start(live: live, diagnosis: diagnosis) } }
                .onAppear {
                    reviewActiveWorkBeforeQuit()
                    PerformanceStartupCheck.windowAppeared()
                }
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
            LoadAlertSettingsView(alerts: alerts, live: live)
        }
    }

    /// The menu bar label lives for the whole session, so quitting from the
    /// menu or Dock reviews work even when the main window was never opened.
    private func reviewActiveWorkBeforeQuit() {
        diagnosis.attach(to: live)
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
