import PerformanceCore
import SwiftUI

struct HardwareEvidenceView: View {
    let hardware: HardwareEvidence
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measured hardware").font(.headline)
            if let fans = hardware.fans {
                if fans.isEmpty { Text("Driver reports no fans.") }
                ForEach(Array(fans.enumerated()), id: \.offset) { _, fan in
                    Text("\(fan.name): \(fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "unavailable") · \(fan.fractionOfMaximum.map { String(format: "%.0f%% of reported maximum", $0 * 100) } ?? "maximum unavailable")").monospacedDigit()
                }
            } else { Text("Fan counters unavailable on this configuration.") }
            Text("CPU sensor maximum: \(hardware.cpuSensorMaximumCelsius.map { String(format: "%.1f°C", $0) } ?? "unavailable") · \(hardware.cpuSensorCount) readable sensors")
            Text("GPU sensor maximum: \(hardware.gpuSensorMaximumCelsius.map { String(format: "%.1f°C", $0) } ?? "unavailable") · device activity \(hardware.gpuUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "unavailable")")
            Text(hardware.source).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
