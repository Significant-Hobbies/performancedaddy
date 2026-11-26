import Charts
import Combine
import PerformanceCore
import SwiftUI

/// A read-only summary for a host overview. Visibility is registered with the same
/// sampler as the detailed workspace; SwiftUI observes the displayed readings only.
public struct PerformanceActivityOverview: View {
    private let live: LiveViewModel
    @State private var reading: Reading?
    @State private var history: [LiveViewModel.MemoryPoint] = []
    @State private var paused = false

    public init(session: PerformanceWorkspaceSession) { live = session.live }

    private struct Reading {
        let date: Date
        let cpu: String
        let ram: String
        let pressure: String

        @MainActor init(_ snapshot: LiveSnapshot) {
            date = snapshot.date
            pressure = snapshot.pressure
            if let cores = snapshot.system.usedCPUCores, cores.isFinite, cores >= 0 {
                let fraction = min(1, cores / Double(max(1, ProcessInfo.processInfo.processorCount)))
                cpu = fraction.formatted(.percent.precision(.fractionLength(1)))
            } else {
                cpu = "—"
            }
            if let headroom = snapshot.system.memoryHeadroomRatio, (0...1).contains(headroom) {
                ram = LiveViewModel.bytes(UInt64(Double(ProcessInfo.processInfo.physicalMemory) * (1 - headroom)))
            } else {
                ram = "—"
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("System activity").font(.headline)
                Spacer()
                if let reading {
                    Text((paused ? "Paused · " : "") + reading.date.formatted(date: .omitted, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                metric("CPU utilization", reading?.cpu)
                metric("Estimated RAM in use", reading?.ram)
                metric("Memory pressure", reading?.pressure)
            }
            if history.count >= 2 {
                Chart(history) { point in
                    LineMark(x: .value("Time", point.date), y: .value("RAM in use", point.used * 100))
                        .foregroundStyle(PerformanceTheme.mintInk)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 34)
                .accessibilityLabel("Estimated RAM usage, last five minutes")
            }
        }
        .background(MonitoringSurface(model: live))
        .onReceive(live.$snapshot) { reading = $0.map(Reading.init) }
        .onReceive(live.$memoryHistory) { history = $0 }
        .onReceive(live.$paused.removeDuplicates()) { paused = $0 }
        .task { live.start() }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? "Measuring…").monospacedDigit().gridColumnAlignment(.trailing)
        }.font(.callout)
    }
}
