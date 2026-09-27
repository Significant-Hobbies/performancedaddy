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
    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView(model: diagnosis, live: live)
                .frame(minWidth: 980, minHeight: 800)
                .task { updates.start(live: live, diagnosis: diagnosis) }
        }
        .defaultSize(width: 1_180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck || !updates.isIdle)
                Toggle("Automatically Check for Updates", isOn: $updates.automaticallyChecks)
            }
        }
        WindowGroup(id: "agent-wall") {
            AgentWallView(model: live)
                .frame(minWidth: 520, minHeight: 360)
                .task { live.start() }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra {
            LiveMenu(model: live, updates: updates)
        } label: {
            Label(live.usedMemory, systemImage: "memorychip")
        }
    }
}

@MainActor
final class PerformanceDaddyDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = PerformanceAppIcon.image { NSApplication.shared.applicationIconImage = icon }
    }
}

@MainActor
enum PerformanceAppIcon {
    static let image = DaddyResources.url(forResource: "PerformanceDaddy").flatMap(NSImage.init(contentsOf:))
}

private struct LiveMenu: View {
    @ObservedObject var model: LiveViewModel
    @ObservedObject var updates: AppUpdates
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("RAM estimate: \(model.usedMemory)")
        Text("Pressure: \(model.snapshot?.pressure ?? "Measuring")")
        Text("\(model.portCount) open sockets · \(model.agentCount) agent processes")
        Divider()
        Button("Open PerformanceDaddy") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(model.paused ? "Resume monitoring" : "Pause monitoring") { model.paused.toggle() }
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck || !updates.isIdle)
        Divider()
        Button("Quit PerformanceDaddy") { NSApplication.shared.terminate(nil) }
    }
}
