import PerformanceCore
import SaaSMakerUI
import SwiftUI

/// The result is the review. Every action names the workload whose scope was measured.
struct ResourceLeadersView: View {
    @ObservedObject var model: LiveViewModel
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var leaders: LiveViewModel.ResourceLeaders?
    @State private var outcome: String?
    @State private var measuring = false
    @State private var measurementUnavailable = false
    @State private var acting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CPU & RAM culprits").font(.title2.bold())
                Spacer()
                Button("Done") { if let onDone { onDone() } else { dismiss() } }.keyboardShortcut(.cancelAction)
            }
            if let leaders {
                Text("Measured at \(leaders.date.formatted(date: .omitted, time: .standard)) · Memory pressure: \(leaders.pressure)")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("Largest resident memory", rows: leaders.memory, memory: true, measurement: leaders)
                        section("Highest CPU use", rows: leaders.cpu, memory: false, measurement: leaders)
                    }
                }
                Text("Quitting closes an app and its windows. Stopping a process can interrupt work and lose unsaved changes.")
                    .font(.callout).foregroundStyle(.secondary)
                if let outcome { Text(outcome).font(.callout.weight(.medium)).textSelection(.enabled) }
                Button("Measure again") { Task { await measure() } }
                    .disabled(measuring || acting || model.performingAction)
            } else if measurementUnavailable {
                Text("A current workload measurement is unavailable.")
                Button("Measure again") { Task { await measure() } }
            } else {
                Spacer()
                ProgressView("Measuring workloads…").frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(24).frame(minWidth: 520, idealWidth: 620, maxWidth: onDone == nil ? 650 : .infinity, minHeight: 440, idealHeight: 590, maxHeight: onDone == nil ? 640 : .infinity)
            .background(PerformanceTheme.fog)
            .task { await measure() }
    }

    private func section(_ title: String, rows: [LoadContributor], memory: Bool, measurement: LiveViewModel.ResourceLeaders) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text(memory ? "No resident-memory measurements available." : measurement.measuredCPU ? "No positive CPU usage was measured." : "CPU usage is not yet available.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.owner.id) { work in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.name).fontWeight(.medium).lineLimit(1)
                        Text("PID \(String(work.owner.id.pid)) · " + (work.kind == .app ? "App and its helpers" : "\(work.targets.count) process\(work.targets.count == 1 ? "" : "es")"))
                            .font(.caption).foregroundStyle(.secondary)
                        if let hosted = measurement.hosted[work.owner.id], !hosted.isEmpty {
                            Text("Quitting may also end \(hosted.count) hosted process\(hosted.count == 1 ? "" : "es").")
                                .font(.caption).foregroundStyle(PerformanceTheme.amber)
                        }
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
                            acting = true
                            Task {
                                outcome = await model.stopMeasuredLeader(work, from: measurement)
                                acting = false
                            }
                        }
                        .accessibilityLabel("\(work.kind == .app ? "Quit" : "Stop") \(work.name), PID \(String(work.owner.id.pid))")
                        .disabled(measuring || acting || model.performingAction || outcome != nil)
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
        measurementUnavailable = false
        let started = Date()
        while model.refreshing && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
        guard !Task.isCancelled else { return }
        await model.refresh()
        if !Task.isCancelled, let sample = model.snapshot, !sample.processes.contains(where: { $0.cpu != nil }) {
            try? await Task.sleep(for: .seconds(1))
            while model.refreshing && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            if !Task.isCancelled { await model.refresh() }
        }
        guard !Task.isCancelled else { return }
        if let sample = model.snapshot, sample.date >= started { leaders = LiveViewModel.ResourceLeaders(sample) }
        else { leaders = nil; measurementUnavailable = true }
        outcome = nil
    }
}
