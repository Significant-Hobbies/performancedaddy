import Foundation

public struct IncidentExplanation: Equatable, Sendable {
    public let observed: String
    public let candidate: String
    public let unknown: String
    public let nextCheck: String
    public let reviewSearch: String?
    public let window: String

    public static func analyze(_ capture: DiagnosticCapture) -> Self {
        let marker = capture.marker?.date
        var seen = Set<Date>()
        let samples = capture.samples.filter {
            $0.timestamp >= capture.startedAt && $0.timestamp <= capture.endedAt && seen.insert($0.timestamp).inserted &&
                (marker == nil || abs($0.timestamp.timeIntervalSince(marker!)) <= 10)
        }
        let incidents = samples.compactMap(\.incident)
        let partial = incidents.contains { $0.unavailableProcesses > 0 }
        let window = marker == nil ? "Recorded window" : "Within 10 seconds of your slow-moment marker"
        let unknown = "Coincident measurements do not prove a cause. \(partial ? "Some process reads were unavailable. " : "")Typing-to-display, scrolling and other apps' event queues were not measured."
        func result(_ observation: String, _ workload: WorkloadEvidence?, _ metric: String, _ next: String) -> Self {
            let candidate = workload.map { "\($0.name)\($0.project.map { " · " + $0 } ?? ""): \(metric). This is a candidate contributor, not a confirmed cause." }
                ?? "No responsible workload is established by these observations."
            let search = workload.map { $0.name.components(separatedBy: " & helpers")[0].components(separatedBy: " · PID")[0] }
            return Self(observed: observation, candidate: candidate, unknown: unknown, nextCheck: next,
                        reviewSearch: search, window: "\(window) · \(samples.count) observations")
        }
        let workloads = incidents.flatMap(\.workloads)
        if samples.contains(where: { $0.thermal == .serious || $0.thermal == .critical }) {
            return result("macOS reported serious or critical thermal pressure near this incident.", nil, "",
                          "Let ongoing work finish and check ventilation. Repeat the same slow action after thermal pressure settles; record the change and follow-up. Fan RPM alone cannot locate the heat source.")
        }
        if incidents.contains(where: { $0.pressure == "Critical" }) || incidents.filter({ $0.pressure == "Warning" }).count >= 2 {
            let largest = workloads.max { ($0.footprintBytes ?? $0.residentBytes) < ($1.footprintBytes ?? $1.residentBytes) }
            let paging = samples.contains { ($0.memory?.swapOutBytesPerSecond ?? 0) > 0 }
            return result("macOS memory pressure was elevated\(paging ? " and active swap-out was recorded" : "") near this incident.", largest,
                          largest.map { "peak recorded footprint/RSS " + ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.footprintBytes ?? $0.residentBytes), countStyle: .memory) } ?? "",
                          "Review the named workload and save its work. If you choose to pause or close it, make one change, repeat the same slow action, and compare both pressure and app response.")
        }
        let probes = samples.compactMap { $0.responsiveness?.appProbe }.filter { probe in
            marker == nil || abs(probe.date.timeIntervalSince(marker!)) <= 10
        }
        let groups = Dictionary(grouping: probes) { ($0.bundleID ?? $0.app) + ":" + ($0.version ?? "unknown") }
        let delayed = groups.values.filter { group in
            group.filter { $0.status == .didNotReply }.count >= 2 || group.filter { $0.status == .replied && ($0.milliseconds ?? 0) >= 100 }.count >= 2
        }.sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }.first
        if let delayed {
            let failures = delayed.filter { $0.status == .didNotReply }
            let slowReplies = delayed.filter { $0.status == .replied && ($0.milliseconds ?? 0) >= 100 }
            let app = delayed.last?.app ?? "The last-used app"
            return result("\(app)'s accessibility service had \(slowReplies.count) replies taking at least 100 ms and \(failures.count) requests without a completed reply near this incident.", nil, "",
                          "Import a Sample Process report from \(app) while the symptom is happening. Repeat the same action with app probing enabled. A messaging failure can reflect a busy app or a service failure; it is not proof of a beachball.")
        }
        let capacity = incidents.compactMap { $0.logicalCPUs > 0 ? Double($0.logicalCPUs) : nil }.max()
        let saturated = samples.filter { sample in capacity.map { (sample.usedCPUCores ?? 0) >= $0 * 0.8 } ?? false }.count >= 2
        let activeWindows = incidents.filter { $0.workloads.contains { ($0.cpuCores ?? 0) >= 1 } }.count
        if saturated || activeWindows >= 2 {
            let leader = workloads.filter { $0.cpuCores != nil }.max { ($0.cpuCores ?? 0) < ($1.cpuCores ?? 0) }
            return result(saturated ? "At least 80% of the recorded CPU capacity was busy in multiple observations near this incident." : "A recorded workload used at least one CPU core in multiple observations near this incident. This is activity, not whole-Mac saturation.", leader,
                          leader.flatMap(\.cpuCores).map { String(format: "%.2f cores at its captured peak", $0) } ?? "",
                          "Review whether the named workload is expected. If you pause it yourself, repeat the same action and record a follow-up; falling CPU use alone cannot prove the action feels faster.")
        }
        if let gpu = incidents.compactMap({ $0.hardware?.gpuUtilizationPercent }).filter({ $0 >= 70 }).max() {
            return result(String(format: "GPU device activity reached %.0f%% near this incident.", gpu), nil, "",
                          "Repeat the same scrolling or switching action and import the affected app's stacks if it stalls. Device activity cannot identify which app owns GPU work or measure frame latency.")
        }
        let lag = samples.compactMap { $0.responsiveness?.heartbeatMaximumMilliseconds }.max()
        return result(lag.map { $0 >= 100 ? String(format: "PerformanceDaddy's own main queue was delayed by up to %.0f ms; no captured resource pressure explains your other apps' delay.", $0) : "No captured resource pressure explains the delay near this incident." } ?? "No captured resource pressure explains the delay near this incident.", nil, "",
                      "Repeat the specific typing, switching or scrolling action. Enable the optional app-response probe or import the affected app's Sample Process report while it is slow. Quiet CPU readings do not rule out a blocked app.")
    }
}
