import PerformanceCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DiagnosisViewModel
    @ObservedObject var live: LiveViewModel
    @State private var destination = "Processes"
    @State private var showingDeleteRecentRuns = false
    @State private var showingDeleteBaseline = false
    @State private var showingReplaceBaseline = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 220)
        } detail: {
            ZStack {
                PerformanceTheme.fog.ignoresSafeArea()
                if let page = LivePage(rawValue: destination) {
                    LiveWorkloadsView(model: live, page: page)
                } else if destination == "Configuration" {
                    ConfigurationView()
                } else if destination == "App access" {
                    AppAccessAuditView(live: live)
                } else if destination == "Fans & heat" {
                    FanInvestigationView(model: model)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Root-cause analysis").font(.headline)
                            Spacer()
                            Menu("Recent runs (\(model.recentReports.count))") {
                                ForEach(Array(model.recentReports.enumerated()), id: \.offset) { _, report in
                                    Button {
                                        model.review(report)
                                    } label: {
                                        Label("\(report.capture.startedAt.formatted(date: .abbreviated, time: .standard)) · \(report.rootCauseAnalysis.headline)",
                                              systemImage: model.report?.capture.startedAt == report.capture.startedAt ? "checkmark" : "clock")
                                    }
                                }
                                if !model.recentReports.isEmpty {
                                    Divider()
                                    Button("Delete all recent runs…", role: .destructive) {
                                        showingDeleteRecentRuns = true
                                    }
                                }
                            }.disabled(model.recentReports.isEmpty || model.isRecording)
                                .help("Last ten completed recordings, stored locally on this Mac.")
                            if let baseline = model.savedBaselineReport {
                                Menu("Known-good baseline") {
                                    Button("Review saved baseline") { model.review(baseline) }
                                    Divider()
                                    Button("Delete saved baseline…", role: .destructive) {
                                        showingDeleteBaseline = true
                                    }
                                }.disabled(model.isRecording)
                            }
                            if model.historyStorageError != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(PerformanceTheme.amber)
                                    .help(model.historyStorageError ?? "Recent-run storage unavailable")
                                    .accessibilityLabel(model.historyStorageError ?? "Recent-run storage unavailable")
                            }
                            if model.baselineStorageError != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(PerformanceTheme.amber)
                                    .help(model.baselineStorageError ?? "Known-good baseline storage unavailable")
                                    .accessibilityLabel(model.baselineStorageError ?? "Known-good baseline storage unavailable")
                            }
                        }.padding(.horizontal, 28).padding(.top, 16)
                        diagnosisContent
                    }
                }
            }
        }
        .tint(PerformanceTheme.action)
        .preferredColorScheme(.dark)
        .buttonStyle(DaddyButtonStyle())
        .toolbar(.hidden, for: .windowToolbar)
        .task {
            await model.loadHistory()
            live.start()
        }
        .confirmationDialog("Delete all recent runs?", isPresented: $showingDeleteRecentRuns) {
            Button("Delete \(model.recentReports.count) saved runs", role: .destructive) {
                Task { await model.deleteRecentRuns() }
            }
        } message: {
            Text("This removes the local recordings and clears the open report. A separately saved known-good baseline stays available.")
        }
        .confirmationDialog("Delete known-good baseline?", isPresented: $showingDeleteBaseline) {
            Button("Delete saved baseline", role: .destructive) {
                Task { await model.deleteKnownGoodBaseline() }
            }
        } message: {
            Text("Future checks will no longer compare against this local capture. Recent runs stay available.")
        }
        .alert("Replace known-good baseline?", isPresented: $showingReplaceBaseline) {
            Button("Replace baseline", role: .destructive) {
                if let report = model.report {
                    Task { await model.saveKnownGoodBaseline(report) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The previous saved baseline will be replaced by this capture. Recent runs stay available.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                DaddyArtwork(brand: true).frame(width: 24, height: 24)
                Text("performancedaddy")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(-0.6).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.top, 20).padding(.bottom, 10)
            Button { destination = "Diagnose" } label: {
                Label("Diagnose slowdown", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity).frame(height: 28)
            }.buttonStyle(DaddyButtonStyle(prominent: true))
                .help("Open a timed, read-only CPU, memory and thermal diagnostic. Recording starts only when you choose Start.")
            VStack(alignment: .leading, spacing: 5) {
                navigationHeading("LIVE")
                ForEach(LivePage.allCases) { page in
                    navigationItem(page.rawValue, icon: page.icon)
                }
                navigationHeading("INVESTIGATE").padding(.top, 9)
                navigationItem("Fans & heat", icon: "fan")
                navigationItem("App access", icon: "lock.shield")
                navigationItem("Configuration", icon: "doc.text.magnifyingglass")
                navigationItem("Diagnose", icon: "waveform.path.ecg")
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 7) {
                Text("On your Mac. Under your control.").font(.caption)
                Text("Nothing stops until you review it.").font(.caption)
            }
            .foregroundStyle(PerformanceTheme.secondaryInk)
        }
        .padding(.horizontal, 15).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private func navigationHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1)
            .foregroundStyle(PerformanceTheme.secondaryInk).padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func navigationItem(_ title: String, icon: String) -> some View {
        Button { destination = title } label: {
            HStack {
                Image(systemName: icon).frame(width: 20).foregroundStyle(PerformanceTheme.mintInk)
                Text(title)
                Spacer()
            }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(destination == title ? PerformanceTheme.mintInk.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityAddTraits(destination == title ? .isSelected : [])
    }

    @ViewBuilder
    private var diagnosisContent: some View {
        if model.isRecording {
            RecordingView(progress: model.progress, onCancel: model.cancelRecording)
        } else if let report = model.report {
            ReportView(
                report: report,
                baseline: model.baselineReport,
                comparison: model.comparison,
                comparisonFromSavedBaseline: model.comparisonFromSavedBaseline,
                savedBaseline: model.savedBaselineReport,
                onSaveBaseline: {
                    if model.savedBaselineReport == nil {
                        Task { await model.saveKnownGoodBaseline(report) }
                    } else {
                        showingReplaceBaseline = true
                    }
                },
                onVerify: model.performRecommendedAction,
                onNewCheck: model.clearReport
            )
        } else {
            StartDiagnosisView(
                selectedLength: $model.selectedLength,
                savedBaseline: model.savedBaselineReport,
                errorMessage: model.errorMessage,
                onStart: model.startRecording
            )
        }
    }
}

private struct StartDiagnosisView: View {
    @State private var showingShellDiagnosis = false
    @Binding var selectedLength: DiagnosisViewModel.CaptureLength
    let savedBaseline: DiagnosticReport?
    let errorMessage: String?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(PerformanceTheme.coralWash)
                    .frame(width: 92, height: 92)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(PerformanceTheme.coral)
            }

            VStack(spacing: 10) {
                Text("What is slowing your Mac?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(PerformanceTheme.ink)
                Text("Record while the slowdown is happening. This recording reads local system evidence and makes no changes.")
                    .font(.body)
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 590)
                    .lineSpacing(3)
            }

            Picker("Recording length", selection: $selectedLength) {
                ForEach(DiagnosisViewModel.CaptureLength.allCases) { length in
                    Text(length.rawValue).tag(length)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Button("Start \(selectedLength.rawValue) check", action: onStart)
                .buttonStyle(PrimaryActionButtonStyle())

            if let savedBaseline {
                Text("This check will compare with your saved baseline from \(savedBaseline.capture.startedAt.formatted(date: .abbreviated, time: .shortened)). Use a similar workload for a meaningful comparison.")
                    .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    .multilineTextAlignment(.center).frame(maxWidth: 590)
            }

            Button { showingShellDiagnosis = true } label: {
                Label("Diagnose terminal startup…", systemImage: "terminal")
            }
            .help("Review a separate zsh experiment. Your startup scripts run only with explicit consent.")
            .sheet(isPresented: $showingShellDiagnosis) { ShellDiagnosisView() }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { capabilities }
                VStack(alignment: .leading, spacing: 10) { capabilities }
            }
            .padding(.top, 18)
            Spacer()
        }
        .padding(48)
    }

    @ViewBuilder
    private var capabilities: some View {
        CapabilityLabel(icon: "cpu", text: "CPU and processes")
        CapabilityLabel(icon: "memorychip", text: "Memory and swap")
        CapabilityLabel(icon: "thermometer.medium", text: "Thermal state")
        CapabilityLabel(icon: "internaldrive", text: "Disk headroom")
    }
}

private struct CapabilityLabel: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PerformanceTheme.action)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordingView: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(PerformanceTheme.coral.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(PerformanceTheme.coral, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title.bold())
                    .foregroundStyle(PerformanceTheme.ink)
            }
            .frame(width: 150, height: 150)
            .accessibilityLabel("Recording progress")
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))

            Text("Watching what happens")
                .font(.largeTitle.bold())
                .foregroundStyle(PerformanceTheme.ink)
            Text("Sampling CPU, processes, memory, swap, disk headroom and thermal state. No changes are being made.")
                .font(.body)
                .foregroundStyle(PerformanceTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Button("Cancel recording", action: onCancel)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(48)
    }
}

private struct ReportView: View {
    let report: DiagnosticReport
    let baseline: DiagnosticReport?
    let comparison: DiagnosticComparison?
    let comparisonFromSavedBaseline: Bool
    let savedBaseline: DiagnosticReport?
    let onSaveBaseline: () -> Void
    let onVerify: () -> Void
    let onNewCheck: () -> Void

    private var finding: DiagnosticFinding { report.finding }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if report.capture.isFixture {
                    Label("Preview evidence — no live machine data", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PerformanceTheme.action)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                verdict

                Text("Recorded \(report.capture.startedAt.formatted(date: .abbreviated, time: .standard)) – \(report.capture.endedAt.formatted(date: .omitted, time: .standard)) · \(durationLabel) · saved capture")
                    .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let baseline, let comparison {
                    comparisonBand(baseline: baseline, comparison: comparison)
                }

                TriageBand(label: "NOW", subtitle: "During this recording") {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(finding.nowTitle)
                                .font(.title2.bold())
                                .foregroundStyle(PerformanceTheme.ink)
                            Spacer()
                            Text(durationLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Sparkline(values: report.cpuSeries)
                            .frame(height: 82)
                        Text(finding.nowDetail)
                            .font(.callout)
                            .foregroundStyle(PerformanceTheme.secondaryInk)
                    }
                }

                TriageBand(label: "WHY", subtitle: "Root-cause analysis") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Assessment across five evidence domains")
                            .font(.title2.bold())
                            .foregroundStyle(PerformanceTheme.ink)
                        Text(report.rootCauseAnalysis.coverage)
                            .font(.callout)
                            .foregroundStyle(PerformanceTheme.secondaryInk)
                        ForEach(report.rootCauseAnalysis.assessments) { assessment in
                            VStack(alignment: .leading, spacing: 6) {
                                ViewThatFits(in: .horizontal) {
                                    HStack { Text(assessment.title).font(.headline).accessibilityAddTraits(.isHeader); Spacer(); assessmentStatus(assessment) }
                                    VStack(alignment: .leading, spacing: 4) { Text(assessment.title).font(.headline).accessibilityAddTraits(.isHeader); assessmentStatus(assessment) }
                                }
                                Text(assessment.evidence).font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                                DisclosureGroup("\(assessment.title) · evidence limits") {
                                    Text(assessment.limitation).font(.callout).padding(.top, 4)
                                }.font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                        Text("Measured CPU contributors").font(.headline).accessibilityAddTraits(.isHeader)
                        if report.rootCauseAnalysis.contributors.isEmpty {
                            Text("No positive readable process CPU rows were captured. This does not prove that every process was idle.")
                                .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                        } else {
                            ForEach(report.rootCauseAnalysis.contributors, id: \.self) { contributor in
                                Text(contributor).font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Text(report.rootCauseAnalysis.limitations).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                    }
                }

                TriageBand(label: "NEXT", subtitle: "What you can safely do") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Next check to narrow the cause")
                            .font(.title2.bold())
                            .foregroundStyle(PerformanceTheme.ink)
                        Text(report.rootCauseAnalysis.nextCheck)
                            .font(.body)
                            .foregroundStyle(PerformanceTheme.secondaryInk)
                        HStack(spacing: 12) {
                            Button(recommendedActionLabel, action: onVerify)
                                .buttonStyle(PrimaryActionButtonStyle())
                            Button("New check", action: onNewCheck)
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                        }
                        Button(baselineButtonTitle, action: onSaveBaseline)
                            .disabled(report.capture.isFixture || isSavedBaseline)
                        Text("Save only a run you consider representative of good performance. New checks can compare with it; the capture stays on this Mac until you delete it.")
                            .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                        DisclosureGroup("Evidence limits and method") {
                            Text(methodNote)
                                .font(.callout)
                                .foregroundStyle(PerformanceTheme.secondaryInk)
                                .padding(.top, 6)
                        }
                        .font(.caption.weight(.medium))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var verdict: some View {
        HStack(alignment: .top, spacing: 18) {
            Circle()
                .fill(PerformanceTheme.coral)
                .frame(width: 28, height: 28)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 7) {
                Text(report.rootCauseAnalysis.headline)
                    .font(.largeTitle.bold())
                    .foregroundStyle(PerformanceTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(report.rootCauseAnalysis.conclusion)
                    .font(.body)
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                Label("Measured signals · root cause not confirmed", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
            }
            Spacer()
        }
        .padding(24)
        .background(PerformanceTheme.coralWash)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func assessmentStatus(_ assessment: CauseAssessment) -> some View {
        Text(assessment.status.rawValue).font(.caption.weight(.medium))
            .foregroundStyle(assessment.status == .observed ? PerformanceTheme.amber : PerformanceTheme.secondaryInk)
    }

    private func comparisonBand(baseline: DiagnosticReport, comparison: DiagnosticComparison) -> some View {
        TriageBand(label: "RESULT", subtitle: comparisonFromSavedBaseline ? "Against your saved baseline" : "What changed after your action") {
            VStack(alignment: .leading, spacing: 12) {
                Label(comparison.title, systemImage: comparisonIcon)
                    .font(.title2.bold())
                    .foregroundStyle(comparisonColor)
                    .accessibilityAddTraits(.isHeader)
                Text(comparison.detail)
                    .font(.body)
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                Text(comparisonFromSavedBaseline
                     ? "Compared with your saved \(durationLabel(for: baseline)) capture from \(baseline.capture.startedAt.formatted(date: .abbreviated, time: .shortened)). Different workloads can make this inconclusive."
                     : "Compared with the \(durationLabel(for: baseline)) baseline. Correlation does not prove that the action alone caused the change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isSavedBaseline: Bool {
        savedBaseline?.capture.startedAt == report.capture.startedAt &&
            savedBaseline?.capture.endedAt == report.capture.endedAt
    }

    private var baselineButtonTitle: String {
        if isSavedBaseline { return "Saved as known-good baseline" }
        return savedBaseline == nil ? "Save as known-good baseline" : "Replace known-good baseline"
    }

    private var comparisonIcon: String {
        switch comparison?.outcome {
        case .improved: "arrow.down.right.circle.fill"
        case .worsened: "arrow.up.right.circle.fill"
        case .unchanged: "equal.circle.fill"
        default: "questionmark.circle.fill"
        }
    }

    private var comparisonColor: Color {
        switch comparison?.outcome {
        case .improved: PerformanceTheme.mintInk
        case .worsened: PerformanceTheme.coral
        default: PerformanceTheme.action
        }
    }

    private var recommendedActionLabel: String {
        switch finding.kind {
        case .temporaryBuildLoad: "Verify after the build"
        case .memoryPressure: "Verify after closing an app"
        case .thermalPressure: "Verify after cooling"
        case .processLoad: "Verify after reviewing the app"
        case .healthy, .inconclusive: "Capture a longer check"
        }
    }

    private var methodNote: String {
        let unavailable = finding.evidence.filter { !$0.isAvailable }.map(\.label)
        let sampler = report.capture.samples.compactMap(\.samplerCPUCores).max()
        var notes = [
            "\(report.capture.samples.count) local samples over \(durationLabel.lowercased()).",
            "PerformanceDaddy reads system counters and does not change processes, files or settings."
        ]
        if let sampler {
            notes.append("Peak observed sampler load was \(sampler.formatted(.number.precision(.fractionLength(2)))) CPU cores.")
        }
        if !unavailable.isEmpty {
            notes.append("Unavailable in this check: \(unavailable.joined(separator: ", ")).")
        }
        notes.append("A repeated pattern raises confidence; a single comparison shows correlation, not proof of causation.")
        return notes.joined(separator: " ")
    }

    private var durationLabel: String {
        let seconds = Int(report.capture.duration.rounded())
        return seconds >= 60 ? "\(seconds / 60) min capture" : "\(seconds) sec capture"
    }

    private func durationLabel(for report: DiagnosticReport) -> String {
        let seconds = Int(report.capture.duration.rounded())
        return seconds >= 60 ? "\(seconds / 60)-minute" : "\(seconds)-second"
    }
}

private struct TriageBand<Content: View>: View {
    let label: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalBand
            VStack(alignment: .leading, spacing: 16) {
                bandHeading
                Divider()
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(PerformanceTheme.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PerformanceTheme.divider, lineWidth: 1)
        }
    }

    private var horizontalBand: some View {
        HStack(alignment: .top, spacing: 24) {
            bandHeading
                .frame(width: 124, alignment: .leading)
            Divider()
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bandHeading: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(values.max() ?? 1, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: values.count <= 1 ? 0 : geometry.size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: geometry.size.height * (1 - CGFloat(value / maximum) * 0.88)
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(PerformanceTheme.coral.opacity(0.12))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(PerformanceTheme.coral, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU use over the recording")
        .accessibilityValue("Peak \((values.max() ?? 0).formatted(.number.precision(.fractionLength(1)))) cores")
    }
}

private struct EvidenceStrip: View {
    let items: [EvidenceItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(items) { item in
            HStack(spacing: 7) {
                Image(systemName: item.isAvailable ? (item.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill") : "questionmark.circle")
                    .foregroundStyle(item.isAvailable ? (item.isHealthy ? PerformanceTheme.mintInk : PerformanceTheme.coral) : .secondary)
                    .accessibilityHidden(true)
                Text("\(item.label) \(item.value)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PerformanceTheme.ink)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(item.isAvailable ? (item.isHealthy ? PerformanceTheme.mint : PerformanceTheme.coralWash) : Color.secondary.opacity(0.1))
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.label), \(item.value), \(evidenceStatus(item))")
        }
    }

    private func evidenceStatus(_ item: EvidenceItem) -> String {
        guard item.isAvailable else { return "unavailable" }
        return item.isHealthy ? "healthy" : "needs attention"
    }
}
