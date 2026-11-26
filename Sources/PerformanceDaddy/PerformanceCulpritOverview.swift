import Combine
import PerformanceCore
import SwiftUI

/// The home workspace displays individual processes from the active Performance session.
public struct PerformanceCulpritOverview: View {
    private enum Ranking: String, CaseIterable {
        case memory = "Memory", cpu = "CPU"
    }

    private struct Reading {
        let date: Date
        let memory: [LiveProcess]
        let cpu: [LiveProcess]

        init(_ snapshot: LiveSnapshot) {
            date = snapshot.date
            memory = Array(snapshot.processes.filter { $0.memory > 0 }.sorted {
                $0.memory == $1.memory ? $0.id.pid < $1.id.pid : $0.memory > $1.memory
            }.prefix(5))
            cpu = Array(snapshot.processes.filter { $0.cpu?.isFinite == true }.sorted {
                $0.cpu == $1.cpu ? $0.id.pid < $1.id.pid : ($0.cpu ?? 0) > ($1.cpu ?? 0)
            }.prefix(5))
        }
    }

    private let live: LiveViewModel
    @State private var reading: Reading?
    @State private var paused = false
    @State private var ranking = Ranking.memory
    public init(session: PerformanceWorkspaceSession) { live = session.live }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top processes").font(.headline)
                    TimelineView(.periodic(from: .now, by: 10)) { tick in
                        Text(status(at: tick.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Rank processes by", selection: $ranking) {
                    ForEach(Ranking.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            let rows = (ranking == .memory ? reading?.memory : reading?.cpu) ?? []
            if !rows.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow {
                        Text("Process")
                        Text("CPU").help("100% equals one fully occupied CPU core.")
                        Text("Resident RAM")
                    }.font(.caption).foregroundStyle(.secondary)
                    ForEach(rows) { process in
                        GridRow {
                            HStack(spacing: 7) {
                                ProcessIcon(process: process)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(process.name).lineLimit(1).truncationMode(.middle)
                                    Text("PID \(String(process.id.pid))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            Text(process.cpu.map { String(format: "%.1f%%", $0) } ?? "—")
                                .monospacedDigit().gridColumnAlignment(.trailing)
                                .accessibilityLabel(process.cpu.map { String(format: "CPU %.1f percent", $0) } ?? "CPU not yet measured")
                            Text(LiveViewModel.bytes(process.memory)).monospacedDigit().gridColumnAlignment(.trailing)
                                .accessibilityLabel("Resident memory \(LiveViewModel.bytes(process.memory))")
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if ranking == .cpu, reading != nil {
                Text("Waiting for a measured CPU interval.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(reading == nil ? "Reading local processes…" : "No resident-memory readings available.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-culprit-overview")
        .background(MonitoringSurface(model: live))
        .onReceive(live.$snapshot) { reading = $0.map(Reading.init) }
        .onReceive(live.$paused.removeDuplicates()) { paused = $0 }
        .task { live.start() }
    }

    private func status(at date: Date) -> String {
        guard let reading else { return paused ? "Monitoring paused" : "Warming up" }
        let time = reading.date.formatted(date: .omitted, time: .standard)
        if paused { return "Paused · Last sample \(time)" }
        if date.timeIntervalSince(reading.date) > 30 { return "Stale · Last sample \(time)" }
        if reading.cpu.isEmpty { return "CPU warming up · Sampled \(time)" }
        return "Sampled \(time)"
    }
}
