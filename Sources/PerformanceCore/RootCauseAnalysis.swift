import Foundation

public struct CauseAssessment: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case observed = "Signal observed"
        case notObserved = "Threshold not met"
        case insufficient = "Insufficient evidence"
    }
    public let id: String
    public let title: String
    public let status: Status
    public let evidence: String
    public let limitation: String
}

public struct RootCauseAnalysis: Equatable, Sendable {
    public var headline: String {
        let signals = Set(assessments.filter { $0.status == .observed }.map(\.id))
        if signals.contains("thermal") { return "Thermal pressure needs investigation." }
        if signals.contains("memory") && signals.contains("paging") { return "Memory demand and paging need investigation." }
        if signals.contains("pressure") { return "macOS memory pressure needs investigation." }
        if signals.contains("app_response") { return "App service response needs investigation." }
        if signals.contains("gpu") { return "GPU activity needs investigation." }
        if signals.contains("cpu") { return "CPU work is the strongest recorded signal." }
        if signals.contains("memory") { return "Low memory headroom needs a closer check." }
        if signals.contains("disk") { return "Low disk capacity needs review." }
        if signals.contains("paging") { return "Swap-out activity needs a closer check." }
        return "No measured signal explains the delay yet."
    }
    public let conclusion: String
    public let assessments: [CauseAssessment]
    public let contributors: [String]
    public let coverage: String
    public let nextCheck: String
    public let limitations: String

    public static func analyze(_ capture: DiagnosticCapture) -> Self {
        // Duplicate/out-of-window observations must not manufacture repeated evidence.
        var timestamps = Set<Date>()
        let samples = capture.samples.filter {
            $0.timestamp.timeIntervalSince1970.isFinite &&
            $0.timestamp >= capture.startedAt && $0.timestamp <= capture.endedAt &&
            timestamps.insert($0.timestamp).inserted
        }
        let count = samples.count
        let cpu = samples.compactMap(\.usedCPUCores).filter(valid)
        let headroom = samples.compactMap(\.memoryHeadroomRatio).filter { valid($0) && $0 <= 1 }
        let paging = samples.compactMap { $0.memory?.swapOutBytesPerSecond }.filter(valid)
        let thermal = samples.map(\.thermal).filter { $0 != .unavailable }
        let disk = samples.compactMap(\.diskFreeBytes).filter { $0 >= 0 }
        func covered(_ n: Int) -> Bool { n >= 2 && n * 5 >= count * 4 }
        func repeated(_ n: Int) -> Bool { n >= 2 && n * 2 >= count }
        func status(_ signal: Bool, _ validCount: Int) -> CauseAssessment.Status {
            signal ? .observed : covered(validCount) ? .notObserved : .insufficient
        }
        let cpuBusy = repeated(cpu.filter { $0 >= 1 }.count)
        let lowMemory = repeated(headroom.filter { $0 < 0.08 }.count)
        let swapping = repeated(paging.filter { $0 > 0 }.count)
        let hotCount = thermal.filter { $0 == .serious || $0 == .critical }.count
        let lowDisk = disk.contains { $0 < 20 * 1_024 * 1_024 * 1_024 }
        let cpuMean = cpu.isEmpty ? nil : cpu.reduce(0) { $0 + $1 / Double(cpu.count) }
        var assessments: [CauseAssessment] = [
            .init(id: "thermal", title: "Thermal pressure", status: status(hotCount > 0, thermal.count),
                  evidence: "Serious or critical state in \(hotCount)/\(count) samples; \(thermal.count) readable.",
                  limitation: "Thermal state does not identify the physical cause or prove it caused the reported delay."),
            .init(id: "memory", title: "Memory headroom", status: status(lowMemory, headroom.count),
                  evidence: "\(headroom.filter { $0 < 0.08 }.count)/\(count) samples below 8% estimated headroom; minimum \(headroom.min().map { number($0 * 100) + "%" } ?? "unavailable").",
                  limitation: "Free/inactive headroom is an estimate, not the macOS memory-pressure signal or proof of a leak."),
            .init(id: "paging", title: "Active swap-out", status: status(swapping, paging.count),
                  evidence: "Positive swap-out in \(paging.filter { $0 > 0 }.count)/\(count) samples; \(paging.count) readable rate samples.",
                  limitation: "Allocated swap is not active paging. Swap-out can contribute to delay, but no latency correlation was measured."),
            .init(id: "cpu", title: "CPU work", status: status(cpuBusy, cpu.count),
                  evidence: "Average \(cpuMean.map(number) ?? "unavailable") cores; peak \(cpu.max().map(number) ?? "unavailable"); \(cpu.count)/\(count) readable samples. \(cpu.filter { $0 >= 1 }.count)/\(count) samples at or above one core; the rule requires at least half the samples and at least two observations.",
                  limitation: "One core of activity is not whole-machine saturation. A blocked app can be slow while total CPU is low."),
            .init(id: "disk", title: "Disk capacity", status: status(lowDisk, disk.count),
                  evidence: "Minimum free space: \(disk.min().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "unavailable"); \(disk.count)/\(count) readable samples.",
                  limitation: "Below 20 GiB is a capacity review threshold, not proof of slow storage. Disk latency and throughput are not captured here."),
        ]
        let incidents = samples.compactMap(\.incident)
        if samples.contains(where: { $0.responsiveness != nil }) {
            let response = ResponsivenessSummary.analyze(capture)
            let slow = samples.compactMap { $0.responsiveness?.appProbe }.filter { $0.status == .replied && ($0.milliseconds ?? 0) >= 100 }.count
            assessments.append(.init(id: "app_response", title: "Last-used app service response",
                status: status(slow >= 2 || response.noReplyCount >= 2, response.replyCount), evidence: response.details,
                limitation: "100 ms is an investigation threshold for an Accessibility request, not an input-latency standard. Messaging failures are not proof of a hang; a quick reply does not prove rendering is fast."))
            let delayed = samples.compactMap { $0.responsiveness?.heartbeatMaximumMilliseconds }.filter { $0 >= 100 }.count
            assessments.append(.init(id: "monitor_response", title: "PerformanceDaddy queue response",
                status: status(delayed > 0, samples.filter { ($0.responsiveness?.heartbeatCount ?? 0) > 0 }.count),
                evidence: "\(delayed) recorded windows contained a main-queue acknowledgement delayed by at least 100 ms.",
                limitation: "Only PerformanceDaddy's queue is measured. Its own work or scheduling can delay it; this cannot establish whole-Mac or other-app responsiveness."))
        }
        if !incidents.isEmpty {
            let pressures = incidents.filter { $0.pressure == "Warning" || $0.pressure == "Critical" }.count
            assessments.append(.init(id: "pressure", title: "macOS memory pressure", status: status(repeated(pressures) || incidents.contains { $0.pressure == "Critical" }, incidents.filter { ["Normal", "Warning", "Critical"].contains($0.pressure) }.count),
                evidence: "Warning/critical in \(pressures)/\(count) observations.", limitation: "This is the OS pressure signal. It still needs correlation with the reported delay."))
            let gpu = incidents.compactMap { $0.hardware?.gpuUtilizationPercent }.filter { valid($0) && $0 <= 100 }
            let busyGPU = gpu.filter { $0 >= 70 }.count
            assessments.append(.init(id: "gpu", title: "GPU device activity", status: status(repeated(busyGPU), gpu.count),
                evidence: "At least 70% in \(busyGPU)/\(count) observations; peak \(gpu.max().map { number($0) + "%" } ?? "unavailable").",
                limitation: "Driver utilization is activity, not proof of rendering latency or which app caused it. Hardware coverage varies."))
            let fanRatios = incidents.compactMap { $0.hardware?.fans?.compactMap(\.fractionOfMaximum).max() }
            assessments.append(.init(id: "fans", title: "Measured fan speed", status: status(repeated(fanRatios.filter { $0 >= 0.9 }.count), fanRatios.count),
                evidence: "Highest recorded fraction of each fan's reported maximum: \(fanRatios.max().map { number($0 * 100) + "%" } ?? "unavailable").",
                limitation: "RPM is measured separately for each fan. A reported maximum and loudness do not establish the source of heat."))
            let ioRates = incidents.map { $0.workloads.compactMap { workload -> Double? in
                guard workload.readBytesPerSecond != nil || workload.writtenBytesPerSecond != nil else { return nil }
                return (workload.readBytesPerSecond ?? 0) + (workload.writtenBytesPerSecond ?? 0)
            }.reduce(0, +) }
            assessments.append(.init(id: "io", title: "Recorded workload disk I/O", status: status(repeated(ioRates.filter { $0 >= 50 * 1024 * 1024 }.count), incidents.filter { $0.workloads.contains { $0.readBytesPerSecond != nil || $0.writtenBytesPerSecond != nil } }.count),
                evidence: "Peak retained workload throughput: \(ioRates.max().map { ByteCountFormatter.string(fromByteCount: Int64(min(max(0, $0), Double(Int64.max) - 4096)), countStyle: .memory) + "/s" } ?? "unavailable").",
                limitation: "Throughput is not storage latency. Partial/omitted process reads make this a lower bound."))
            let changes = incidents.map(\.newlyObservedProcesses).reduce(0, +)
            assessments.append(.init(id: "launches", title: "Observed process arrivals", status: changes >= 20 ? .observed : .notObserved,
                evidence: "\(changes) newly observed process instances after the initial census.",
                limitation: "Polling is not an execution-event log. Arrivals can include previously unreadable processes; short-lived commands and tab-opening requests may be missed."))
        }
        // Signals first; preserve domain order within each tier.
        assessments = assessments.enumerated().sorted {
            let left = $0.element.status == .observed ? 0 : $0.element.status == .insufficient ? 1 : 2
            let right = $1.element.status == .observed ? 0 : $1.element.status == .insufficient ? 1 : 2
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)

        var totals: [String: Double] = [:]
        var appearances: [String: Int] = [:]
        for sample in samples {
            var names = Set<String>()
            for process in sample.processes where valid(process.cpuCores) {
                let name = String(process.name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(100))
                guard !name.isEmpty else { continue }
                // Divide before summation to avoid overflow on extreme finite inputs.
                totals[name, default: 0] += process.cpuCores / Double(max(count, 1))
                names.insert(name)
            }
            for name in names { appearances[name, default: 0] += 1 }
        }
        var contributors = totals.filter { $0.value.isFinite && $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(3).map {
            "\($0.key): \(number($0.value)) recorded cores per sample; present in \(appearances[$0.key] ?? 0)/\(count) samples."
        }
        if !incidents.isEmpty {
            var work: [String: (name: String, cpu: Double, readable: Int, footprint: UInt64, io: Double?)] = [:]
            for evidence in incidents {
                for item in evidence.workloads {
                    var prior = work[item.id] ?? (item.name + (item.project.map { " · " + $0 } ?? ""), 0, 0, 0, nil)
                    if let cpu = item.cpuCores, valid(cpu) { prior.cpu += cpu / Double(max(count, 1)); prior.readable += 1 }
                    prior.footprint = max(prior.footprint, item.footprintBytes ?? item.residentBytes)
                    if item.readBytesPerSecond != nil || item.writtenBytesPerSecond != nil {
                        let rate = (item.readBytesPerSecond ?? 0) + (item.writtenBytesPerSecond ?? 0)
                        if valid(rate) { prior.io = max(prior.io ?? 0, rate) }
                    }
                    work[item.id] = prior
                }
            }
            var displayed: [String] = []; var ids = Set<String>()
            let cpuLeaders = work.sorted { $0.value.cpu > $1.value.cpu }.prefix(5)
            let memoryLeaders = work.sorted { $0.value.footprint > $1.value.footprint }.prefix(3)
            let ioLeaders = work.filter { ($0.value.io ?? 0) > 0 }.sorted { ($0.value.io ?? 0) > ($1.value.io ?? 0) }.prefix(3)
            for (id, item) in Array(cpuLeaders) + Array(memoryLeaders) + Array(ioLeaders) where ids.insert(id).inserted {
                let io = item.io.map { ByteCountFormatter.string(fromByteCount: Int64(min(max(0, $0), Double(Int64.max) - 4096)), countStyle: .memory) + "/s peak recorded I/O" } ?? "I/O unavailable"
                displayed.append("\(item.name): \(item.readable > 0 ? number(item.cpu) + " recorded cores/observation" : "CPU rate unavailable"); CPU readable in \(item.readable)/\(count), peak footprint/RSS \(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.footprint), countStyle: .memory)); \(io).")
            }
            contributors = displayed
        }
        let conclusion: String
        let next: String
        if assessments.contains(where: { $0.id == "pressure" && $0.status == .observed }) && hotCount == 0 {
            conclusion = "macOS memory pressure was observed. Memory demand is a candidate contributor; the cause of your delay is not established."
            next = "Review the recorded footprint leaders and paging trends. After one reviewed change, repeat the same task and recording length; task responsiveness still needs verification."
        } else if assessments.contains(where: { $0.id == "gpu" && $0.status == .observed }) && hotCount == 0 {
            conclusion = "Repeated GPU activity was measured alongside the incident. It is a candidate heat or rendering contributor; app attribution and the cause of the delay are not established."
            next = "Repeat the same slow action and compare GPU activity, measured fan RPM and the foreground app. Import a selected-app stack report if it beachballs despite low CPU."
        } else if hotCount > 0 {
            conclusion = "Thermal pressure was observed and may be limiting performance. Its underlying cause is not established."
            next = "Keep airflow clear, allow cooling, then reproduce the same slow task and compare a recording of equal length. Check whether the task and thermal state both improve."
        } else if lowMemory && swapping {
            conclusion = "Low memory headroom and repeated swap-out activity were both observed in this recording. Memory demand is a candidate contributor, not a proven root cause."
            next = "Review the Memory view for a growing or unneeded app. If you choose to close one, save work first and repeat the same task and recording length; compare both paging and actual task delay."
        } else if cpuBusy {
            conclusion = contributors.isEmpty ?
                "Repeated CPU work was captured, but no positive readable process rows identify its owner. The cause of your task delay is not established." :
                "Repeated CPU work was captured. The named contributors explain recorded activity, but this does not yet prove why your task was slow."
            next = contributors.isEmpty ?
                "Repeat the slow action with the Processes view open and include system processes if needed. Process inspection may be restricted; a targeted profiler may be needed to identify the owner." :
                "Reproduce the delay while watching the named contributors. After a reviewed pause or completion of one workload, repeat the same task and equal-length recording to test whether the delay changes."
        } else {
            conclusion = "The root cause is not established by this recording. The assessment below shows exactly which signals were seen, absent at the rule threshold, or missing."
            next = lowMemory ? "Open Memory and check pressure and swap-rate trends while reproducing the delay; low headroom alone is not enough to justify stopping an app." :
                lowDisk ? "Review storage ownership in StorageDaddy before any cleanup. Reproduce the slow operation to distinguish a capacity concern from an actual I/O delay." :
                "For slow terminal opening, use Diagnose terminal startup. For another slow app, reproduce one specific action during a 2-minute check and inspect its process; network waits and app-internal blocking need targeted profiling."
        }
        let observer = samples.compactMap(\.samplerCPUCores).filter(valid).max()
        return Self(conclusion: conclusion, assessments: assessments, contributors: contributors,
                    coverage: "\(count) distinct in-window samples; \(capture.samples.count - count) invalid, duplicate or out-of-window samples excluded. Peak recorded observer CPU (PerformanceDaddy itself): \(observer.map(number) ?? "unavailable") cores.",
                    nextCheck: next,
                    limitations: incidents.isEmpty ? "No causal intervention was performed. Legacy attribution contains at most 16 CPU-ranked process rows per observation, grouped by name. GPU/fans, response latency, Network latency and disk latency are unavailable in this capture. Missing rows are not proven idle; recorded contributor averages are lower bounds." : "No causal intervention or task-response timing was measured. Up to 32 workload families are retained across CPU, footprint and I/O ranking; resource sums and contributor averages are lower bounds of readable evidence. Project and app associations come from working-directory, executable and parent metadata, not verified ownership. Driver GPU/SMC readings are version-dependent. Polling can miss short-lived activity. Network latency, UI hangs and disk latency need targeted evidence. Non-observation describes this window only.")
    }

    private static func valid(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func number(_ value: Double) -> String { String(format: "%.2f", value) }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
