import Foundation

/// Explains possible heat contributors during a user-reported fan incident.
/// Never infers fan speed, GPU use or a physical cause from CPU/thermal state.
public struct FanInvestigation: Equatable, Sendable {
    public enum CPUTrend: String, Sendable {
        case rising = "CPU activity rose"
        case settling = "CPU activity settled"
        case steady = "CPU activity was steady"
        case unavailable = "CPU trend unavailable"
    }

    public struct Contributor: Equatable, Sendable {
        public let id: String
        public let name: String
        public let association: String
        public let recordedAverageCores: Double
        public let samplesPresent: Int
    }

    public let headline: String
    public let explanation: String
    public let confidence: FindingConfidence
    public let nextCheck: String
    public let sampleCount: Int
    public let cpuSampleCount: Int
    public let averageCPUCores: Double?
    public let peakCPUCores: Double?
    public let sustainedCPU: Bool
    public let cpuTrend: CPUTrend
    public let thermalSampleCount: Int
    public let peakThermal: ThermalCondition
    public let powerLimitSampleCount: Int
    public let constrainedPowerSampleCount: Int
    public let contributors: [Contributor]
    public let limitations: String
    public let workloadCoverage: String
    public let evidenceLinks: [String]

    public static func analyze(_ capture: DiagnosticCapture) -> Self {
        var timestamps = Set<Date>()
        let samples = capture.samples.filter {
            $0.timestamp.timeIntervalSince1970.isFinite &&
            $0.timestamp >= capture.startedAt && $0.timestamp <= capture.endedAt &&
            timestamps.insert($0.timestamp).inserted
        }.sorted { $0.timestamp < $1.timestamp }
        let cpuSamples = samples.filter { $0.usedCPUCores.map(valid) == true }
        let cpu = cpuSamples.compactMap(\.usedCPUCores)
        let span = cpuSamples.last.flatMap { last in cpuSamples.first.map { last.timestamp.timeIntervalSince($0.timestamp) } } ?? 0
        let continuous = zip(cpuSamples, cpuSamples.dropFirst()).allSatisfy {
            $1.timestamp.timeIntervalSince($0.timestamp) <= 6
        }
        let windowCovered = capture.duration.isFinite && capture.duration > 0 && span >= capture.duration * 0.8
        let covered = cpu.count >= 3 && cpu.count * 5 >= samples.count * 4 && span >= 10 && continuous && windowCovered
        let sustained = covered && cpu.filter { $0 >= 1 }.count * 2 >= cpu.count
        let mean = cpu.isEmpty ? nil : cpu.reduce(0) { $0 + $1 / Double(cpu.count) }
        let trend: CPUTrend
        if covered && cpu.count >= 6 {
            let n = cpu.count / 3
            let first = cpu.prefix(n).reduce(0) { $0 + $1 / Double(n) }
            let last = cpu.suffix(n).reduce(0) { $0 + $1 / Double(n) }
            trend = last - first >= 0.5 ? .rising : first - last >= 0.5 ? .settling : .steady
        } else {
            trend = .unavailable
        }
        let thermal = samples.map(\.thermal).filter { $0 != .unavailable }
        let peakThermal = thermal.max { rank($0) < rank($1) } ?? .unavailable
        let constrained = samples.filter {
            [$0.power?.cpuSpeedLimitPercent, $0.power?.schedulerLimitPercent]
                .contains { $0.map { $0 >= 0 && $0 < 100 } == true }
        }.count
        let powerLimits = samples.filter {
            [$0.power?.cpuSpeedLimitPercent, $0.power?.schedulerLimitPercent]
                .contains { $0.map { (0...100).contains($0) } == true }
        }.count
        var labels: [String: String] = [:]
        var associations: [String: String] = [:]
        var totals: [String: Double] = [:]
        var appearances: [String: Int] = [:]
        var activeWorkloadSamples: [String: Int] = [:]
        for sample in cpuSamples {
            if let workloads = sample.workloads {
                var ids = Set<String>()
                for workload in workloads where valid(workload.cpuCores) && ids.insert(workload.id).inserted {
                    totals[workload.id, default: 0] += workload.cpuCores / Double(cpu.count)
                    appearances[workload.id, default: 0] += 1
                    if workload.cpuCores >= 0.5 { activeWorkloadSamples[workload.id, default: 0] += 1 }
                    labels[workload.id] = workload.name
                    associations[workload.id] = workload.association
                }
                continue
            }
            var names = Set<String>()
            var identities = Set<Int32>()
            for process in sample.processes where valid(process.cpuCores) && process.cpuCores > 0 {
                guard identities.insert(process.id).inserted else { continue }
                let name = String(process.name.filter {
                    !$0.isNewline && !$0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
                }.prefix(100))
                guard !name.isEmpty else { continue }
                totals[name, default: 0] += process.cpuCores / Double(cpu.count)
                names.insert(name)
            }
            for name in names { appearances[name, default: 0] += 1 }
        }
        let contributors = totals.filter { $0.value.isFinite && $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(32).map { Contributor(id: $0.key, name: labels[$0.key] ?? $0.key, association: associations[$0.key] ?? "Legacy recording: process names only; ownership unverified", recordedAverageCores: $0.value, samplesPresent: appearances[$0.key] ?? 0) }
        let attributed = cpuSamples.filter { $0.workloads != nil }.count
        let recordedTotal = totals.values.reduce(0, +)
        let primary = contributors.first
        let strong = sustained && attributed * 5 >= cpu.count * 4 && attributed > 0 &&
            primary.map { recordedTotal <= (mean ?? 0) * 1.1 && $0.recordedAverageCores >= 0.5 && $0.recordedAverageCores >= (mean ?? 0) * 0.3 && $0.samplesPresent * 5 >= cpu.count * 4 && activeWorkloadSamples[$0.id, default: 0] * 2 >= cpu.count } == true
        let workloadCoverage = mean.map { total in
            let fraction = total > 0 ? recordedTotal / total : 0
            return fraction > 1.1 ? "Process and system CPU intervals disagree; share unavailable." :
                "Recorded workloads account for about \(Int(min(1, max(0, fraction)) * 100))% of system CPU. The remainder is unattributed, including unreadable or omitted processes and kernel work."
        } ?? "System CPU unavailable; workload share cannot be calculated."
        let heatCoincidence = cpuSamples.filter { ($0.usedCPUCores ?? 0) >= 1 && rank($0.thermal) >= 1 }.count
        var links = [
            primary.map { "\($0.name) → CPU: measured \(String(format: "%.2f", $0.recordedAverageCores)) cores on average. \($0.association)." } ?? "Workload → CPU: no readable positive contributor identified.",
            heatCoincidence > 0 ? "CPU → thermal pressure: elevated CPU and thermal state overlapped in \(heatCoincidence) samples. This association does not prove which workload generated the heat." : "CPU → thermal pressure: no overlapping elevated readings established this link. Earlier heat and unmeasured GPU work remain unresolved.",
            "Thermal pressure → fan noise: unresolved. Fan RPM and noise changes were not measured."
        ]
        let pagingSamples = samples.filter {
            guard let memory = $0.memory else { return false }
            return [memory.swapInBytesPerSecond, memory.swapOutBytesPerSecond].contains { rate in
                rate.map { $0.isFinite && $0 > 1_048_576 } == true
            }
        }.count
        if pagingSamples > 0 {
            links.append("Memory → paging: swap transfers exceeded 1 MB/s in \(pagingSamples) samples. Paging adds memory and disk work; these counters do not identify the responsible app or prove a fan cause.")
        }
        let headline: String
        let explanation: String
        if strong, let primary {
            headline = "\(primary.name) is the leading CPU contributor."
            explanation = "This workload accounted for about \(Int(min(1, primary.recordedAverageCores / (mean ?? 1)) * 100))% of recorded system CPU, averaging \(String(format: "%.2f", primary.recordedAverageCores)) cores. Its sustained work is a plausible heat contributor; the fan connection still needs a follow-up check."
        } else if sustained {
            headline = attributed > 0 ? "CPU load is spread across workloads; no clear main cause." : "Sustained CPU work is a possible heat contributor."
            if attributed > 0, let primary, let mean, mean > 0, recordedTotal <= mean * 1.1 {
                explanation = "The largest recorded contributor was \(primary.name), averaging \(String(format: "%.2f", primary.recordedAverageCores)) cores, about \(Int(min(1, primary.recordedAverageCores / mean) * 100))% of system CPU. It did not explain enough sustained load to single out. \(workloadCoverage)"
            } else {
                explanation = "CPU activity reached at least one core in half or more of the readable samples. This measures ongoing work, not whole-machine saturation or the cause of fan noise."
            }
        } else if peakThermal == .serious || peakThermal == .critical {
            headline = "Thermal pressure was observed; its source is unresolved."
            explanation = "macOS reported significant thermal pressure. The recording does not identify which workload or physical condition caused it."
        } else if !covered {
            headline = "More evidence is needed to explain the fan."
            explanation = "A continuous CPU window of at least ten seconds with at least 80% readable coverage is needed. Missing readings never mean idle."
        } else {
            headline = "This recording does not explain the fan noise."
            explanation = "Sustained CPU work did not meet the investigation threshold. GPU activity, earlier heat and environmental conditions remain unmeasured possibilities; nominal thermal state does not prove a quiet fan."
        }
        return Self(headline: headline, explanation: explanation,
                    confidence: strong ? .medium : .low,
                    nextCheck: trend == .settling ?
                        "CPU work declined during this capture. Listen for whether the fan settles too, then record another equal-length check. Fan speed was not measured." :
                        "Record two minutes while the fan is loud. If you choose to pause a named workload, save your work first, then repeat an equal-length capture and note whether the fan noise changes.",
                    sampleCount: samples.count, cpuSampleCount: cpu.count,
                    averageCPUCores: mean, peakCPUCores: cpu.max(), sustainedCPU: sustained,
                    cpuTrend: trend, thermalSampleCount: thermal.count, peakThermal: peakThermal,
                    powerLimitSampleCount: powerLimits,
                    constrainedPowerSampleCount: constrained, contributors: contributors,
                    limitations: "Fan noise is user-reported. Fan RPM, raw temperature and GPU activity are not measured. Power allowances are OS constraints, not clock measurements or proof of thermal throttling. App and agent ownership uses executable metadata and parent links, not authenticated identity. Up to 32 workload groups are saved; missing groups never prove idle and averages are lower bounds. Legacy recordings only contain process names. No causal intervention or fan improvement was measured.",
                    workloadCoverage: workloadCoverage, evidenceLinks: links)
    }

    public static func compareWorkload(before: DiagnosticCapture, after: DiagnosticCapture) -> String {
        let baseline = analyze(before), current = analyze(after)
        guard abs(before.duration - after.duration) <= 2,
              baseline.cpuTrend != .unavailable, current.cpuTrend != .unavailable,
              let target = baseline.contributors.first,
              before.samples.contains(where: { $0.workloads != nil }) else {
            return "Workload comparison needs equally long, continuous recordings with app attribution."
        }
        guard let followup = current.contributors.first(where: { $0.id == target.id }) else {
            return "\(target.name) is absent from the saved top contributors. It may have exited, become quieter or become unreadable; this does not prove it stopped."
        }
        let change = followup.recordedAverageCores - target.recordedAverageCores
        let systemChange = (current.averageCPUCores ?? 0) - (baseline.averageCPUCores ?? 0)
        return "\(target.name): \(String(format: "%.2f", target.recordedAverageCores)) → \(String(format: "%.2f", followup.recordedAverageCores)) cores. System CPU \(systemChange < -0.2 ? "fell" : systemChange > 0.2 ? "rose" : "was similar"); peak thermal state \(baseline.peakThermal.rawValue) → \(current.peakThermal.rawValue). \(change < -0.2 && systemChange < -0.2 ? "The workload and system CPU declined together, supporting its contribution to CPU load." : "This pair does not confirm that reducing this workload reduced system load.") Fan improvement remains unmeasured."
    }

    private static func valid(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func rank(_ value: ThermalCondition) -> Int {
        switch value {
        case .unavailable: -1
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }
}
