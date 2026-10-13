import SwiftUI
import PerformanceCore
import SaaSMakerUI

struct AppResponseSettingsView: View {
    @ObservedObject var live: LiveViewModel
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Probe the last-used app's response", isOn: $live.appResponseEnabled)
                Text("Optional read-only Accessibility request, at most once every five seconds. Only the app name, version, completion status and timing are retained. No screen content, text or global keystrokes are read.")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                if live.appResponseEnabled && !live.appResponsePermissionAvailable {
                    Button("allow Accessibility access…", action: live.requestAppResponsePermission)
                    Text("Enable PerformanceDaddy in macOS Accessibility settings. Recording still works without access; app-response evidence will be unavailable.")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                }
                Text("Main-queue and local input dispatch measurements cover PerformanceDaddy only. An app-service reply does not measure typing-to-display or frame latency.")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }.padding(.top, 8)
        } label: {
            Text("App response probe: \(live.appResponseEnabled ? live.appResponsePermissionAvailable ? "on" : "needs Accessibility access" : "off")")
                .font(.caption.weight(.medium))
        }
    }
}

struct ResponsivenessReportView: View {
    let capture: DiagnosticCapture
    var body: some View {
        SMCard(padding: 20) {
            VStack(alignment: .leading, spacing: 9) {
                SMDisplay("Measured responsiveness", size: 17)
                Text(ResponsivenessSummary.analyze(capture).details).font(.callout)
                Text("The app probe measures its Accessibility service. Heartbeat and local-event delay measure PerformanceDaddy's queue before dispatch. None measures another app's completed interaction or screen presentation. Fast replies do not rule out your reported slowdown.")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FollowUpPreparationView: View {
    let report: DiagnosticReport
    let onCancel: () -> Void
    let onRecord: (String, ReportedChange, String, Bool) -> Void
    @State private var task = ""
    @State private var change: ReportedChange = .none
    @State private var detail = ""
    @State private var sameTask = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SMDisplay("Check the same action again", size: 24)
            Text("Make one chosen change yourself, then repeat the slow action during this recording. PerformanceDaddy only measures; it will not stop anything.")
                .foregroundStyle(PerformanceTheme.secondaryInk)
            TextField("Action to repeat, e.g. switch between Safari and Xcode", text: $task)
                .onChange(of: task) { _, value in task = String(value.prefix(120)) }
            Picker("What changed?", selection: $change) {
                ForEach(ReportedChange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("App/workload or change details (optional)", text: $detail)
                .onChange(of: detail) { _, value in detail = String(value.prefix(120)) }
            Toggle("I will repeat the same action, app and power mode", isOn: $sameTask)
            Text("The comparison uses only the original post-marker window (about \(Int(FollowUpBaseline(report.capture).capture.duration.rounded())) seconds), with its preceding history kept for explanation. Afterwards, report whether that same action felt better.")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            HStack {
                Button("cancel", action: onCancel)
                Spacer()
                Button("start follow-up") { onRecord(task, change, detail, sameTask) }
                    .buttonStyle(DaddyButtonStyle(prominent: true))
                    .disabled(!sameTask || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 570)
            .performanceTheme(PerformanceTheme.palette).buttonStyle(DaddyButtonStyle())
    }
}
