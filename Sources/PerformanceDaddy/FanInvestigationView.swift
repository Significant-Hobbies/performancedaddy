import PerformanceCore
import SwiftUI
import SaaSMakerUI

struct FanInvestigationView: View {
    @ObservedObject var model: DiagnosisViewModel
    var hardware: HardwareEvidence? = nil
    var snapshot: LiveSnapshot? = nil
    var onInspect: ((LoadContributor) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SMEyebrow("fans & heat").accessibilityLabel("FANS & HEAT")
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                if model.isRecording {
                    recording
                } else if let report = model.report {
                    result(report)
                } else {
                    setup
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(PerformanceTheme.amber)
                }
                if let error = model.historyStorageError {
                    Text(error).font(.caption).foregroundStyle(PerformanceTheme.amber)
                }
            }
            .padding(32)
            .frame(maxWidth: 1_050, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(PerformanceTheme.ink)
        .onAppear {
            if model.report == nil && !model.isRecording { model.selectedLength = .standard }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "fan").font(.system(size: 42)).foregroundStyle(PerformanceTheme.mintInk)
                .accessibilityHidden(true)
            SMSectionHeader("Why is your fan running?", size: 34).accessibilityLabel("Why is your fan running?")
                .accessibilityAddTraits(.isHeader)
            Text("Record while the fan is loud. We’ll look for sustained CPU work, app and agent contributors, thermal pressure and macOS power constraints.")
                .foregroundStyle(PerformanceTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            if let hardware { HardwareEvidenceView(hardware: hardware) }
            if let snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is happening now").font(.headline)
                    Text("\(snapshot.date.formatted(date: .omitted, time: .standard)) · Thermal state: \(snapshot.system.thermal.rawValue) · Memory pressure: \(snapshot.pressure)")
                        .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    ForEach(Array(LoadContributors.group(snapshot.processes).filter { $0.cpuCores >= 0.1 && $0.owner.name != "kernel_task" }
                        .sorted { $0.cpuCores > $1.cpuCores }.prefix(5).enumerated()), id: \.offset) { _, workload in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workload.kind == .app ? "\(workload.name) and helpers" : workload.name).lineLimit(2)
                                Text("PID \(workload.owner.id.pid)" + (workload.kind == .agent && !workload.owner.directory.isEmpty && workload.owner.directory != "/" ? " · \(URL(fileURLWithPath: workload.owner.directory).lastPathComponent)" : ""))
                                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                            }
                            Spacer(minLength: 12)
                            Text(String(format: "%.1f cores", workload.cpuCores)).monospacedDigit()
                            if let onInspect { Button("inspect") { onInspect(workload) } }
                        }
                    }
                    Text("These are current CPU consumers, not proven fan causes. GPU work, earlier heat and ambient temperature can also matter. kernel_task can be responding to heat. Fan-control ownership and actual clock throttling are not measured.")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            coverage
            Picker("Recording length", selection: $model.selectedLength) {
                ForEach(DiagnosisViewModel.CaptureLength.allCases) { length in
                    Text(length.rawValue).tag(length)
                }
            }.pickerStyle(.segmented).frame(maxWidth: 260)
            Button("record \(model.selectedLength.rawValue) fan check", action: model.recordFanCheck)
                .accessibilityLabel("Record \(model.selectedLength.rawValue) fan check")
                .buttonStyle(DaddyButtonStyle(prominent: true))
            Text("Local and read-only. Nothing stops automatically. Two minutes gives more context than a quick check.")
                .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
        }
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 20) {
            SMSectionHeader("Watching possible heat contributors", size: 34).accessibilityLabel("Watching possible heat contributors")
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: model.progress).accessibilityLabel("Fan check progress")
            Text("\(model.progress.formatted(.percent.precision(.fractionLength(0)))) · Recording CPU, process activity, thermal state and available power constraints.")
                .foregroundStyle(PerformanceTheme.secondaryInk)
            coverage
            Button("cancel recording", action: model.cancelRecording).accessibilityLabel("Cancel recording")
            Text("You can keep using your Mac. No changes are being made.")
                .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
        }
    }

    private func result(_ report: DiagnosticReport) -> some View {
        let finding = report.fanInvestigation
        let duration = report.capture.duration.isFinite ? Int(min(report.capture.duration, 3_600)) : 0
        return VStack(alignment: .leading, spacing: 20) {
            if report.capture.isFixture {
                Label("Preview evidence — no live machine data", systemImage: "sparkles")
                    .foregroundStyle(PerformanceTheme.mintInk)
            }
            Text(finding.headline).font(.custom(PerformanceTheme.palette.displayFont, size: 32).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            SMStatusPill("\(finding.confidence.rawValue) · Fan cause unproven", tone: .warning)
            Text("Recorded \(report.capture.startedAt.formatted(date: .abbreviated, time: .standard)) – \(report.capture.endedAt.formatted(date: .omitted, time: .standard)) · \(duration) seconds · saved recording")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)

            band("NOW") {
                SMDisplay("During this recording", size: 22).accessibilityLabel("During this recording")
                evidenceRow("Average CPU", cores(finding.averageCPUCores))
                evidenceRow("Peak CPU", cores(finding.peakCPUCores))
                evidenceRow("CPU trend", finding.cpuTrend.rawValue)
                evidenceRow("Peak thermal state", finding.peakThermal.rawValue.capitalized)
                if let hardware = report.capture.samples.compactMap({ $0.incident?.hardware }).last { HardwareEvidenceView(hardware: hardware) }
                coverage
            }
            band("WHY") {
                Text(finding.explanation).fixedSize(horizontal: false, vertical: true)
                ForEach(finding.evidenceLinks, id: \.self) { link in
                    Text(link).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if finding.contributors.isEmpty {
                    Text("No positive readable process CPU rows identified a contributor. Missing rows do not prove idle.")
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                } else {
                    SMDisplay("Apps and workloads contributing CPU", size: 17).accessibilityLabel("Apps and workloads contributing CPU")
                    ForEach(Array(finding.contributors.prefix(5)), id: \.id) { contributor in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contributor.name).textSelection(.enabled)
                                Text("\(contributor.association) · \(contributor.samplesPresent)/\(finding.cpuSampleCount) CPU samples")
                                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                            }
                            Spacer(minLength: 16)
                            Text(cores(contributor.recordedAverageCores)).monospacedDigit()
                                .foregroundStyle(PerformanceTheme.mintInk)
                        }
                        Divider()
                    }
                    Text(finding.workloadCoverage)
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                }
            }
            band("NEXT") {
                SMDisplay("Listen and compare", size: 22).accessibilityLabel("Listen and compare")
                Text(finding.nextCheck).fixedSize(horizontal: false, vertical: true)
                Button("record another \(report.capture.duration >= 60 ? "2 min" : "15 sec") check", action: model.recordFanCheck)
                    .accessibilityLabel("Record another \(report.capture.duration >= 60 ? "2 min" : "15 sec") check")
                    .buttonStyle(DaddyButtonStyle(prominent: true))
                if let baseline = model.baselineReport, let comparison = model.comparison {
                    Text("Compared with \(baseline.capture.startedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                    Text(comparison.title).font(.headline)
                    Text(comparison.detail).font(.callout)
                    Text(FanInvestigation.compareWorkload(before: baseline.capture, after: report.capture)).font(.callout)
                    Text(FanInvestigation.compareFanSpeeds(before: baseline.capture, after: report.capture)).font(.callout)
                    Text("This comparison covers recorded resource, thermal and available fan RPM evidence. Fan noise and task responsiveness remain user-reported.")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                }
            }
            DisclosureGroup("Measurements and limitations") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.rootCauseAnalysis.coverage)
                    evidenceRow("CPU coverage", "\(finding.cpuSampleCount)/\(finding.sampleCount) samples")
                    evidenceRow("Thermal coverage", "\(finding.thermalSampleCount)/\(finding.sampleCount) samples")
                    evidenceRow("CPU allowance constraints", finding.powerLimitSampleCount == 0 ? "Unavailable" : "\(finding.constrainedPowerSampleCount)/\(finding.powerLimitSampleCount) readable samples")
                    Text("One CPU core is 100% process CPU. Sustained work requires at least one core in half of readable samples, at least ten seconds, continuous readings and 80% sample/window coverage. This is an investigation threshold, not whole-machine saturation.")
                    Text(finding.limitations)
                }.font(.callout).foregroundStyle(PerformanceTheme.secondaryInk).padding(.top, 12)
            }
            Button("set up a new check", action: model.clearReport).accessibilityLabel("Set up a new check")
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fan noise is your observation. Available RPM, sensor and GPU driver readings are shown separately. Thermal state alone does not establish fan speed or the source of heat.")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
        }
    }

    private func evidenceRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(PerformanceTheme.secondaryInk)
            Spacer(minLength: 16)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.accessibilityElement(children: .combine)
    }

    private func band<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        SMCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SMEyebrow(label.lowercased()).accessibilityLabel(label)
                    .foregroundStyle(PerformanceTheme.secondaryInk).accessibilityAddTraits(.isHeader)
                content()
            }
        }
    }

    private func cores(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(2)))) cores" } ?? "Unavailable"
    }
}
