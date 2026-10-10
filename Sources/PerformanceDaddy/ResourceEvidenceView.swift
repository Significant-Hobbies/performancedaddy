import PerformanceCore
import SwiftUI
import SaaSMakerUI

/// Read-only detail, deliberately separate from reviewed process actions.
struct ResourceEvidenceView: View {
    let snapshot: LiveSnapshot?
    let paused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SMSectionHeader("Memory & thermals", size: 22).accessibilityLabel("Memory & thermals").accessibilityAddTraits(.isHeader)
                Spacer()
                Button("done") { dismiss() }.accessibilityLabel("Done").buttonStyle(DaddyButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if let snapshot {
                Text("\(paused ? "Paused snapshot" : "Sampled") · \(snapshot.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Memory") {
                            row("Pressure", snapshot.pressure)
                            row("Wired · cannot be paged out", bytes(snapshot.system.memory?.wiredBytes))
                            row("Compressed · physical storage", bytes(snapshot.system.memory?.compressedBytes))
                            row("File-backed pages", bytes(snapshot.system.memory?.fileBackedBytes))
                            row("Free pages", bytes(snapshot.system.memory?.freeBytes))
                            row("Inactive pages", bytes(snapshot.system.memory?.inactiveBytes))
                            note("These kernel categories overlap: do not add them together. File-backed and inactive memory are not automatically junk.")
                        }
                        section("Swap activity") {
                            row("Allocated on disk", bytes(snapshot.system.swapUsedBytes))
                            row("Swap in", rate(snapshot.system.memory?.swapInBytesPerSecond))
                            row("Swap out", rate(snapshot.system.memory?.swapOutBytesPerSecond))
                            if let interval = snapshot.system.memory?.rateIntervalSeconds {
                                note(String(format: "Average over %.1f seconds. Rates represent VM pages moved through swap, not physical disk throughput. Allocated swap alone does not prove a current slowdown.", interval))
                            } else {
                                note("Rates need two valid samples within 30 seconds. A pause, missing read or counter reset starts a new measurement window.")
                            }
                        }
                        section("Thermals & power") {
                            row("Thermal state", snapshot.system.thermal.rawValue.capitalized)
                            row("Low Power Mode", snapshot.system.power.map { $0.lowPowerMode ? "On" : "Off" } ?? "Unavailable")
                            row("CPU speed allowance", percent(snapshot.system.power?.cpuSpeedLimitPercent))
                            row("CPU scheduling allowance", percent(snapshot.system.power?.schedulerLimitPercent))
                            note("Thermal state comes from Apple's public ProcessInfo signal. Allowances are macOS-reported limits, not measured clock speed. A limit alone does not identify its cause; unavailable does not mean unrestricted.")
                        }
                        section("Fan & temperature coverage") {
                            row("Fan RPM", "Unavailable")
                            row("Temperature in °C", "Unavailable")
                            note("macOS exposes no supported public raw fan/temperature provider used by this release. This does not mean zero RPM, a fanless Mac or a cool CPU. PerformanceDaddy does not use private SMC interfaces or change cooling settings.")
                        }
                    }
                }
            } else {
                Text("Waiting for the first local sample…").foregroundStyle(PerformanceTheme.secondaryInk)
            }
        }
        .padding(20).frame(width: 460, height: 540)
        .foregroundStyle(PerformanceTheme.ink).background(PerformanceTheme.fog)
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SMCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SMEyebrow(title.lowercased()).accessibilityLabel(title)
                    .foregroundStyle(PerformanceTheme.mintInk).accessibilityAddTraits(.isHeader)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(PerformanceTheme.secondaryInk)
            Spacer(minLength: 16)
            Text(value).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func bytes(_ value: UInt64?) -> String { value.map(LiveViewModel.bytes) ?? "Unavailable" }
    private func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "Unavailable" }
    private func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return snapshot?.system.memory == nil ? "Unavailable" : "Measuring"
        }
        // Explicit binary units preserve sub-KB rates without UInt64 conversion.
        return String(format: "%.1f KiB/s", value / 1024)
    }
}
