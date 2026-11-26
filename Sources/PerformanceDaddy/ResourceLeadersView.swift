import PerformanceCore
import SaaSMakerUI
import SwiftUI

/// The result is the review. Every action names the workload whose scope was measured.
struct ResourceLeadersView: View {
    @ObservedObject var model: LiveViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var leaders: LiveViewModel.ResourceLeaders?
    @State private var outcome: String?
    @State private var measuring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CPU & RAM culprits").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let leaders {
                Text("Measured at \(leaders.date.formatted(date: .omitted, time: .standard)) · Memory pressure: \(leaders.pressure)")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("Largest resident memory", rows: leaders.memory, memory: true)
                        section("Highest CPU use", rows: leaders.cpu, memory: false)
                    }
                }
                Text("Quitting closes an app and its windows. Stopping a process can interrupt work and lose unsaved changes.")
                    .font(.callout).foregroundStyle(.secondary)
                if let outcome { Text(outcome).font(.callout.weight(.medium)).textSelection(.enabled) }
                Button("Measure again") { Task { await measure() } }
                    .disabled(measuring || model.performingAction)
            } else {
                Spacer()
                ProgressView("Measuring workloads…").frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(24).frame(minWidth: 520, idealWidth: 620, maxWidth: 650, minHeight: 440, idealHeight: 590, maxHeight: 640)
            .background(PerformanceTheme.fog)
            .task { await measure() }
    }

    private func section(_ title: String, rows: [LoadContributor], memory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text(memory ? "No resident-memory measurements available." : "No positive CPU usage was measured.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.owner.id) { work in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.name).fontWeight(.medium).lineLimit(1)
                        Text("PID \(String(work.owner.id.pid)) · " + (work.kind == .app ? "App and its helpers" : "\(work.targets.count) process\(work.targets.count == 1 ? "" : "es")"))
                            .font(.caption).foregroundStyle(.secondary)
                        if work.targets.count > 1 {
                            DisclosureGroup("See targets") {
                                ForEach(work.targets) { target in Text("\(target.name) · PID \(String(target.id.pid))") }
                            }.font(.caption)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(memory ? LiveViewModel.bytes(work.memoryBytes) : String(format: "%.2f cores", work.cpuCores))
                        .monospacedDigit()
                    if let reason = model.leaderRestriction(work) {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(work.kind == .app ? "Quit app" : work.targets.count == 1 ? "Stop process" : "Stop \(work.targets.count) processes") {
                            Task {
                                outcome = await model.stopMeasuredLeader(work)
                            }
                        }
                        .accessibilityLabel("\(work.kind == .app ? "Quit" : "Stop") \(work.name), PID \(String(work.owner.id.pid))")
                        .disabled(measuring || model.performingAction || outcome != nil)
                    }
                }
                Divider()
            }
        }
    }

    private func measure() async {
        guard !measuring else { return }
        measuring = true
        defer { measuring = false }
        if model.refreshing {
            while model.refreshing && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
        } else { await model.refresh() }
        if !Task.isCancelled, let sample = model.snapshot, !sample.processes.contains(where: { $0.cpu != nil }) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { await model.refresh() }
        }
        if !Task.isCancelled, let sample = model.snapshot { leaders = LiveViewModel.ResourceLeaders(sample) }
        outcome = nil
    }
}
