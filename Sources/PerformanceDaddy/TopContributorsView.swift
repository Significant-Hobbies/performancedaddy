import SaaSMakerUI
import PerformanceCore
import SwiftUI

/// Ranked read-only evidence behind a toolbar metric. Rankings reuse only what
/// the snapshot already measures; no per-process swap or pressure attribution.
struct TopContributorsView: View {
    let metric: LiveViewModel.ToolbarMetric
    @ObservedObject var model: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SMMacButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            let rows = model.topContributors(for: metric)
            if rows.isEmpty {
                Text(metric == .sockets ? "No TCP listeners or bound UDP ports observed in the latest scan." : "Waiting for the first local sample…")
                    .foregroundStyle(PerformanceTheme.secondaryInk)
            } else {
                ForEach(rows) { process in
                    Button {
                        model.selection = [process.id]
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            ProcessIcon(process: process)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(process.sortName).fontWeight(.medium).lineLimit(1)
                                Text(model.processSubtitle(process)).font(.caption)
                                    .foregroundStyle(PerformanceTheme.secondaryInk).lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            Text(value(process)).monospacedDigit()
                                .foregroundStyle(PerformanceTheme.mintInk)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Select \(process.sortName) in the list")
                    .help("Select \(process.sortName) in the list")
                }
            }
            Text(footnote).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(width: 380)
        .foregroundStyle(PerformanceTheme.ink).background(PerformanceTheme.fog)
        .preferredColorScheme(.dark)
    }

    private var title: String {
        switch metric {
        case .ram, .pressure, .swap: "Largest resident processes"
        case .sockets: "Most open sockets"
        }
    }

    private var footnote: String {
        switch metric {
        case .ram:
            "Resident RAM includes shared memory; these rows do not add up to system RAM. Selecting a row highlights the process when it is listed."
        case .pressure:
            "Memory pressure is a whole-system signal. These are the largest resident processes observed, not proven pressure causes."
        case .swap:
            "macOS exposes no supported per-process swap measurement. These are the largest resident processes observed, not proven swap users."
        case .sockets:
            "TCP listeners and bound UDP ports observed in the latest socket scan. Bind scope does not prove network reachability."
        }
    }

    private func value(_ process: LiveProcess) -> String {
        switch metric {
        case .ram, .pressure, .swap: LiveViewModel.bytes(process.memory)
        case .sockets: "\(process.ports.count)"
        }
    }
}
