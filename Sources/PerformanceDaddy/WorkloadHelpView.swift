import SaaSMakerUI
import SwiftUI

/// Clickable help complements macOS hover tooltips and remains keyboard accessible.
struct WorkloadHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reading your Mac").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    entry("Find and sort", "Search by name, PID, app, role, project or port. Press Command-F to search. Click any column heading to sort; click again to reverse.")
                    entry("Running", "Time since this exact process started, not time spent actively using CPU. A replacement process has its own start time.")
                    entry("CPU", "100% represents one logical core. A process can exceed 100%. Two readable samples are needed before a value appears.")
                    entry("RAM and pressure", "Process RAM is resident memory and can include shared pages. Do not add process rows to estimate physical RAM. Memory pressure is a separate macOS signal; allocated swap alone does not mean active paging.")
                    entry("Ports", "TCP listeners and bound UDP sockets on this Mac, not a remote port scan. Missing permissions or a process exit can leave partial coverage.")
                    entry("Stop safely", "Select a process to inspect it first. Stop opens an exact-target review. Normal stop requests termination; force stop can lose unsaved work. System processes are protected. A successful signal is not a confirmed exit.")
                    entry("Pause and inspect", "Pause freezes live measurements while you read. The clock button opens stop history. The share button exports a redacted local snapshot.")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20).frame(width: 410, height: 500)
            .foregroundStyle(PerformanceTheme.ink).background(PerformanceTheme.fog)
            .preferredColorScheme(.dark).buttonStyle(SMButtonStyle(.outline, size: .compact))
    }
    private func entry(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
