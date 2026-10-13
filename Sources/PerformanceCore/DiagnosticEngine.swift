import Foundation

public struct DiagnosticEngine: Sendable {
    private static let buildProcessNames = [
        "npm", "node", "swift", "swiftc", "xcodebuild", "clang", "cargo", "rustc", "gradle", "java"
    ]
    private static let spotlightProcessNames = ["mds", "mds_stores", "mdworker", "mdworker_shared"]

    public init() {}

    public func compare(before: DiagnosticReport, after: DiagnosticReport) -> DiagnosticComparison {
        let beforeRich = before.capture.samples.contains { $0.incident != nil }
        let afterRich = after.capture.samples.contains { $0.incident != nil }
        if beforeRich != afterRich {
            return DiagnosticComparison(outcome: .inconclusive, title: "The capture capabilities differ.", detail: "Make two new recordings with the same task and evidence coverage. The older recording lacks incident pressure, I/O and hardware evidence.", cpuDelta: nil, memoryHeadroomDelta: nil)
        }
        let beforeModes = Set(before.capture.samples.compactMap { $0.power?.lowPowerMode })
        let afterModes = Set(after.capture.samples.compactMap { $0.power?.lowPowerMode })
        if beforeRich && (beforeModes.count > 1 || afterModes.count > 1 || (!beforeModes.isEmpty && !afterModes.isEmpty && beforeModes != afterModes)) {
            return DiagnosticComparison(outcome: .inconclusive, title: "The power policies differ.", detail: "Repeat the same task under the same power mode. Lower CPU activity under a different policy does not establish better responsiveness.", cpuDelta: nil, memoryHeadroomDelta: nil)
        }
        let beforeContext = before.capture.samples.compactMap { $0.incident?.foreground?.bundleID }.last
        let afterContext = after.capture.samples.compactMap { $0.incident?.foreground?.bundleID }.last
        if let beforeContext, let afterContext, beforeContext != afterContext {
            return DiagnosticComparison(outcome: .inconclusive, title: "The foreground contexts differ.", detail: "Repeat the same task with the same app before interpreting these resource differences. Task responsiveness has not been measured.", cpuDelta: nil, memoryHeadroomDelta: nil)
        }
        let beforeCPU = average(before.cpuSeries)
        let afterCPU = average(after.cpuSeries)
        let cpuDelta = beforeCPU.flatMap { beforeValue in
            afterCPU.map { $0 - beforeValue }
        }
        let beforeHeadroom = before.capture.samples.compactMap(\.memoryHeadroomRatio).filter { validHeadroom($0) }.min()
        let afterHeadroom = after.capture.samples.compactMap(\.memoryHeadroomRatio).filter { validHeadroom($0) }.min()
        let headroomDelta = beforeHeadroom.flatMap { beforeValue in
            afterHeadroom.map { $0 - beforeValue }
        }

        let beforeValid = before.capture.samples.filter { validCPU($0.usedCPUCores) && validHeadroom($0.memoryHeadroomRatio) && $0.thermal != .unavailable }
        let afterValid = after.capture.samples.filter { validCPU($0.usedCPUCores) && validHeadroom($0.memoryHeadroomRatio) && $0.thermal != .unavailable }
        guard beforeValid.count >= 2, afterValid.count >= 2,
              before.capture.isFixture == after.capture.isFixture,
              before.capture.duration > 0, after.capture.duration > 0,
              max(before.capture.duration, after.capture.duration) / min(before.capture.duration, after.capture.duration) <= 2 else {
            return DiagnosticComparison(
                outcome: .inconclusive,
                title: "There is not enough evidence to compare yet.",
                detail: "Both checks need CPU, memory and thermal evidence, comparable durations, and the same live/fixture source.",
                cpuDelta: cpuDelta,
                memoryHeadroomDelta: headroomDelta
            )
        }

        let beforeThermal = before.capture.samples.map { thermalRank($0.thermal) }.max() ?? 0
        let afterThermal = after.capture.samples.map { thermalRank($0.thermal) }.max() ?? 0
        let cpuImproved = (cpuDelta ?? 0) <= -0.5
        let cpuWorsened = (cpuDelta ?? 0) >= 0.5
        let memoryImproved = (headroomDelta ?? 0) >= 0.08
        let memoryWorsened = (headroomDelta ?? 0) <= -0.08
        let outcome: ComparisonOutcome
        func pressure(_ report: DiagnosticReport) -> Int? {
            let values = report.capture.samples.compactMap { sample -> Int? in
                switch sample.incident?.pressure { case "Normal": 0; case "Warning": 1; case "Critical": 2; default: nil }
            }
            guard values.count >= 2, values.count * 5 >= report.capture.samples.count * 4 else { return nil }
            return values.max()
        }
        if beforeRich && (pressure(before) == nil || pressure(after) == nil) {
            return DiagnosticComparison(outcome: .inconclusive, title: "Memory-pressure coverage is insufficient.", detail: "The recorded CPU differences cannot establish overall improvement while memory-pressure evidence is missing. Repeat the same task.", cpuDelta: cpuDelta, memoryHeadroomDelta: headroomDelta)
        }
        let pressureDelta = pressure(before).flatMap { a in pressure(after).map { $0 - a } }
        func paging(_ report: DiagnosticReport) -> Bool? {
            let rates = report.capture.samples.compactMap { $0.memory?.swapOutBytesPerSecond }.filter { $0.isFinite && $0 >= 0 }
            guard rates.count >= 2, rates.count * 5 >= report.capture.samples.count * 4 else { return nil }
            return rates.filter { $0 >= 1_048_576 }.count * 2 >= rates.count
        }
        let pagingWorsened = paging(before) == false && paging(after) == true
        let pagingImproved = paging(before) == true && paging(after) == false
        let improved = cpuImproved || memoryImproved || afterThermal < beforeThermal || (pressureDelta ?? 0) < 0 || pagingImproved
        let worsened = cpuWorsened || memoryWorsened || afterThermal > beforeThermal || (pressureDelta ?? 0) > 0 || pagingWorsened
        if improved && worsened {
            outcome = .inconclusive
        } else if improved {
            outcome = .improved
        } else if worsened {
            outcome = .worsened
        } else {
            outcome = .unchanged
        }

        let title: String
        let detail: String
        switch outcome {
        case .improved:
            title = "Some recorded resource readings improved."
            detail = comparisonDetail(cpuDelta: cpuDelta, headroomDelta: headroomDelta, fallback: "The evidence moved in a healthier direction.") + " This compares resources, not task responsiveness, and does not prove what caused the change."
        case .worsened:
            title = "The follow-up check was busier."
            detail = comparisonDetail(cpuDelta: cpuDelta, headroomDelta: headroomDelta, fallback: "The evidence moved away from the earlier baseline.")
        case .unchanged:
            title = "The follow-up check is broadly unchanged."
            detail = comparisonDetail(cpuDelta: cpuDelta, headroomDelta: headroomDelta, fallback: "No meaningful change crossed the comparison threshold.")
        case .inconclusive:
            title = "The follow-up results are mixed."
            detail = "Some measurements improved while others worsened. Repeat the same workload before drawing a conclusion."
        }
        return DiagnosticComparison(
            outcome: outcome,
            title: title,
            detail: detail,
            cpuDelta: cpuDelta,
            memoryHeadroomDelta: headroomDelta
        )
    }

    public func analyze(_ capture: DiagnosticCapture) -> DiagnosticReport {
        if capture.samples.compactMap(\.incident).count >= 2 { return analyzeIncident(capture) }
        let usableSamples = capture.samples.filter { validCPU($0.usedCPUCores) }
        let cpuSeries = usableSamples.compactMap(\.usedCPUCores)
        guard usableSamples.count >= 2 else {
            return report(capture, cpuSeries, inconclusiveEvidence(from: capture.samples))
        }

        let peakCores = cpuSeries.max() ?? 0
        let averageCores = cpuSeries.reduce(0, +) / Double(max(cpuSeries.count, 1))
        let processAverages = averageProcessCPU(in: usableSamples)
        let dominant = processAverages.max { $0.value < $1.value }
        let buildCores = processAverages
            .filter { name, _ in Self.buildProcessNames.contains(name) }
            .values.reduce(0, +)
        let spotlightCores = processAverages
            .filter { name, _ in Self.spotlightProcessNames.contains(name) }
            .values.reduce(0, +)
        let minimumHeadroom = usableSamples.compactMap(\.memoryHeadroomRatio).filter { validHeadroom($0) }.min()
        let peakSwap = usableSamples.compactMap(\.swapUsedBytes).max()
        let worstThermal = usableSamples.map(\.thermal).max(by: { thermalRank($0) < thermalRank($1) }) ?? .unavailable
        let evidence = evidenceItems(from: usableSamples)

        if worstThermal == .serious || worstThermal == .critical {
            let finding = DiagnosticFinding(
                kind: .thermalPressure,
                verdict: "macOS reported significant thermal pressure.",
                summary: "macOS reported thermal pressure during this check.",
                nowTitle: "Thermal pressure warrants attention",
                nowDetail: "The system entered \(worstThermal.rawValue) thermal state during the recording.",
                whyTitle: "macOS reduces available performance when temperatures stay high.",
                whyDetail: "The recording proves thermal pressure, but not which physical condition caused it.",
                nextTitle: "Let the Mac cool and verify again",
                nextDetail: "Keep airflow clear and repeat the same check before changing software.",
                confidence: .high,
                evidence: evidence
            )
            return report(capture, cpuSeries, finding)
        }

        let lowHeadroomCount = usableSamples.filter { validHeadroom($0.memoryHeadroomRatio) && ($0.memoryHeadroomRatio ?? 1) < 0.08 }.count
        let pagingCount = usableSamples.filter { sample in
            let rate = sample.memory?.swapOutBytesPerSecond
            return rate.map { $0.isFinite && $0 > 0 } == true
        }.count
        if lowHeadroomCount >= 2 && lowHeadroomCount * 2 >= usableSamples.count {
            let finding = DiagnosticFinding(
                kind: .memoryPressure,
                verdict: "Available memory headroom stayed low.",
                summary: "Repeated estimates showed little free or inactive memory; this is not itself proof of a slowdown.",
                nowTitle: "Low estimated memory headroom",
                nowDetail: memoryNowDetail(headroom: minimumHeadroom, swap: peakSwap),
                whyTitle: pagingCount >= 2 ? "Swap-out activity was also observed." : "Active paging was not established by this capture.",
                whyDetail: "Allocated swap is not evidence of current paging. Check memory pressure and resource trends before closing an app.",
                nextTitle: "Close one unneeded heavy app",
                nextDetail: "Then run the same check again to confirm memory headroom improves.",
                confidence: .medium,
                evidence: evidence
            )
            return report(capture, cpuSeries, finding)
        }

        let completeEvidence = usableSamples.allSatisfy {
            validHeadroom($0.memoryHeadroomRatio) && $0.swapUsedBytes != nil && $0.thermal != .unavailable
        }
        if buildCores >= 1.0 && peakCores >= 1.5 && completeEvidence {
            let indexingNote = spotlightCores >= 0.1
                ? " Spotlight processes were also observed; their activity is not attributed to this workload."
                : ""
            let finding = DiagnosticFinding(
                kind: .temporaryBuildLoad,
                verdict: "Development tools are using CPU.",
                summary: "Recognized development executables were active; their task and impact are not proven by process names.",
                nowTitle: "Development tools averaged \(formatCores(buildCores)) CPU cores",
                nowDetail: "The load was concentrated in development processes during this \(formatDuration(capture.duration)) check.",
                whyTitle: "A build, server or other development task may explain this activity.",
                whyDetail: "Executable names do not establish which task is running.\(indexingNote)",
                nextTitle: "Review the development workload",
                nextDetail: "Run Verify again afterward. PerformanceDaddy has made no changes.",
                confidence: .medium,
                evidence: evidence
            )
            return report(capture, cpuSeries, finding)
        }

        if let dominant, dominant.value >= 0.75 && peakCores >= 1.0 {
            let name = displayName(dominant.key)
            let finding = DiagnosticFinding(
                kind: .processLoad,
                verdict: "\(name) is doing most of the work.",
                summary: "Processes sharing this executable name were a major CPU contributor during the recording.",
                nowTitle: "\(name) averaged \(formatCores(dominant.value)) CPU cores",
                nowDetail: "System CPU peaked at \(formatCores(peakCores)) cores.",
                whyTitle: "Sustained CPU work was observed in \(name).",
                whyDetail: "The capture identifies the contributor, but cannot prove whether its current task is expected.",
                nextTitle: "Review \(name) before quitting it",
                nextDetail: "Save active work first, then compare another recording if you choose to quit it.",
                confidence: .medium,
                evidence: evidence
            )
            return report(capture, cpuSeries, finding)
        }

        let healthy = averageCores < 0.75 && completeEvidence && (minimumHeadroom ?? 0) >= 0.15
        let finding = DiagnosticFinding(
            kind: healthy ? .healthy : .inconclusive,
            verdict: healthy ? "No sustained resource pressure was captured." : "The cause is not clear yet.",
            summary: healthy
                ? "CPU stayed low, estimated memory headroom remained available and no serious thermal state was observed."
                : "The recording saw activity, but no single cause met the evidence threshold.",
            nowTitle: healthy ? "This check stayed calm" : "Activity was mixed across the recording",
            nowDetail: "Average system use was \(formatCores(averageCores)) CPU cores.",
            whyTitle: healthy
                ? "The slowdown may have ended before the recording began."
                : "Several small contributors can feel slow without one dominant fault.",
            whyDetail: "PerformanceDaddy will not guess when the available evidence is weak.",
            nextTitle: "Record while the slowdown is happening",
            nextDetail: "A longer capture can improve attribution without changing the Mac.",
            confidence: healthy ? .medium : .low,
            evidence: evidence
        )
        return report(capture, cpuSeries, finding)
    }

    private func analyzeIncident(_ capture: DiagnosticCapture) -> DiagnosticReport {
        let analysis = RootCauseAnalysis.analyze(capture)
        let observed = Set(analysis.assessments.filter { $0.status == .observed }.map(\.id))
        let cpuSeries = capture.samples.compactMap(\.usedCPUCores).filter { $0.isFinite && $0 >= 0 }
        let kind: FindingKind = observed.contains("thermal") ? .thermalPressure : observed.contains("pressure") || observed.contains("memory") ? .memoryPressure : .inconclusive
        let hardware = capture.samples.compactMap { $0.incident?.hardware }.last
        let cpu = hardware?.cpuSensorMaximumCelsius.map { String(format: "%.1f°C", $0) } ?? "unavailable"
        let gpu = hardware?.gpuUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "unavailable"
        let fans = hardware?.fans?.map { fan in
            "\(fan.name): " + (fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "unavailable")
        }.joined(separator: "; ") ?? "unavailable"
        let finding = DiagnosticFinding(kind: kind, verdict: analysis.headline, summary: analysis.conclusion,
            nowTitle: capture.marker == nil ? "Measured resources during this check" : "Evidence around your slow moment",
            nowDetail: "Latest CPU sensor maximum: \(cpu). GPU: \(gpu). Fans: \(fans).",
            whyTitle: analysis.headline, whyDetail: analysis.conclusion,
            nextTitle: "Narrow the cause with a comparable check", nextDetail: analysis.nextCheck,
            confidence: observed.isEmpty ? .low : .medium, evidence: evidenceItems(from: capture.samples))
        return DiagnosticReport(capture: capture, finding: finding, cpuSeries: cpuSeries)
    }

    private func report(
        _ capture: DiagnosticCapture,
        _ cpuSeries: [Double],
        _ finding: DiagnosticFinding
    ) -> DiagnosticReport {
        DiagnosticReport(capture: capture, finding: finding, cpuSeries: cpuSeries)
    }

    private func averageProcessCPU(in samples: [SystemSample]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for sample in samples {
            for process in sample.processes {
                if validCPU(process.cpuCores) { totals[process.name.lowercased(), default: 0] += process.cpuCores }
            }
        }
        let divisor = Double(samples.count)
        return totals.mapValues { $0 / divisor }
    }

    private func evidenceItems(from samples: [SystemSample]) -> [EvidenceItem] {
        let minimumHeadroom = samples.compactMap(\.memoryHeadroomRatio).filter { validHeadroom($0) }.min()
        let peakSwap = samples.compactMap(\.swapUsedBytes).max()
        let minimumDisk = samples.compactMap(\.diskFreeBytes).min()
        let worstThermal = samples.map(\.thermal).max(by: { thermalRank($0) < thermalRank($1) }) ?? .unavailable

        return [
            EvidenceItem(
                id: "memory",
                label: "Memory headroom",
                value: minimumHeadroom.map { "\(Int(($0 * 100).rounded()))%" } ?? "Unavailable",
                isHealthy: (minimumHeadroom ?? 0) >= 0.15,
                isAvailable: minimumHeadroom != nil
            ),
            EvidenceItem(
                id: "swap",
                label: "Swap allocated · not a paging rate",
                value: peakSwap.map(formatBytes) ?? "Unavailable",
                isHealthy: peakSwap != nil,
                isAvailable: peakSwap != nil
            ),
            EvidenceItem(
                id: "thermal",
                label: "Thermal state",
                value: worstThermal == .unavailable ? "Unavailable" : worstThermal.rawValue.capitalized,
                isHealthy: worstThermal == .nominal || worstThermal == .fair,
                isAvailable: worstThermal != .unavailable
            ),
            EvidenceItem(
                id: "disk",
                label: "Disk free",
                value: minimumDisk.map { formatBytes(UInt64(max(0, $0))) } ?? "Unavailable",
                isHealthy: (minimumDisk ?? 0) >= 20 * 1_024 * 1_024 * 1_024,
                isAvailable: minimumDisk != nil
            ),
        ]
    }

    private func inconclusiveEvidence(from samples: [SystemSample]) -> DiagnosticFinding {
        DiagnosticFinding(
            kind: .inconclusive,
            verdict: "The recording was too short to diagnose.",
            summary: "At least two usable samples are required before PerformanceDaddy will make a claim.",
            nowTitle: "Not enough evidence",
            nowDetail: "The capture ended before a stable pattern could be measured.",
            whyTitle: "A single measurement cannot distinguish a spike from a sustained slowdown.",
            whyDetail: "Unavailable evidence lowers confidence instead of being filled with an estimate.",
            nextTitle: "Run the check again",
            nextDetail: "Keep PerformanceDaddy open until the recording finishes.",
            confidence: .low,
            evidence: evidenceItems(from: samples)
        )
    }

    private func memoryNowDetail(headroom: Double?, swap: UInt64?) -> String {
        let headroomText = headroom.map { "\(Int(($0 * 100).rounded()))% memory headroom" } ?? "memory headroom unavailable"
        let swapText = swap.map { "\(formatBytes($0)) swap" } ?? "swap unavailable"
        return "Lowest estimated headroom: \(headroomText). Peak allocated swap: \(swapText). These may occur in different samples."
    }

    private func thermalRank(_ condition: ThermalCondition) -> Int {
        switch condition {
        case .unavailable: 0
        case .nominal: 1
        case .fair: 2
        case .serious: 3
        case .critical: 4
        }
    }

    private func displayName(_ raw: String) -> String {
        raw == "node" ? "Node" : raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatCores(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration >= 90 { return "\(Int((duration / 60).rounded())) minute" }
        return "\(Int(duration.rounded())) second"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    private func average(_ values: [Double]) -> Double? {
        let values = values.filter { validCPU($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func validCPU(_ value: Double?) -> Bool { value.map { $0.isFinite && $0 >= 0 } ?? false }
    private func validHeadroom(_ value: Double?) -> Bool { value.map { $0.isFinite && (0...1).contains($0) } ?? false }

    private func comparisonDetail(
        cpuDelta: Double?,
        headroomDelta: Double?,
        fallback: String
    ) -> String {
        var parts: [String] = []
        if let cpuDelta {
            let direction = cpuDelta >= 0 ? "more" : "fewer"
            parts.append("CPU averaged \(formatCores(abs(cpuDelta))) \(direction) cores")
        }
        if let headroomDelta {
            let points = Int((abs(headroomDelta) * 100).rounded())
            let direction = headroomDelta >= 0 ? "higher" : "lower"
            parts.append("memory headroom was \(points) points \(direction)")
        }
        guard !parts.isEmpty else { return fallback }
        return parts.joined(separator: "; ").capitalized + "."
    }
}
