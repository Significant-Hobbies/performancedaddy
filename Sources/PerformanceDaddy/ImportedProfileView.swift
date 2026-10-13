import PerformanceCore
import SwiftUI

struct ImportedProfileView: View {
    let profile: ImportedProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Thread-stack evidence").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("\(profile.format) · weights in \(profile.unit)").font(.callout).foregroundStyle(.secondary)
            Text("Report timestamp (as written): \(profile.recordedAtText ?? "unavailable; no absolute clock was established")").font(.caption).foregroundStyle(.secondary)
            Text(profile.limitation).font(.callout)
            if !profile.threads.contains(where: \.isMain) {
                Text("Main thread was not identified. This report cannot assess its sampled activity.").foregroundStyle(PerformanceTheme.amber)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(profile.threads.enumerated()), id: \.offset) { _, thread in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(thread.name).font(.headline).textSelection(.enabled)
                            Text(thread.interpretation).font(.callout)
                            ForEach(Array(thread.stacks.sorted { $0.weight > $1.weight }.prefix(3).enumerated()), id: \.offset) { _, stack in
                                Text("\(String(format: "%.1f", stack.weight)) \(thread.unit): \(stack.frames.suffix(5).joined(separator: " → "))")
                                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        Divider()
                    }
                }
            }
            Text("For a beachball, use Activity Monitor → select the app → More → Sample Process → Save. Import the saved text here. Capture during the delay; an idle stack after it ends cannot explain the earlier stall.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(minWidth: 650, idealWidth: 780, minHeight: 480, idealHeight: 650)
    }
}
