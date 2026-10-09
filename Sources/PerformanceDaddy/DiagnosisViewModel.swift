import Combine
import Foundation
import PerformanceCore

@MainActor
final class DiagnosisViewModel: ObservableObject {
    enum CaptureLength: String, CaseIterable, Identifiable {
        case quick = "15 sec"
        case standard = "2 min"

        var id: Self { self }
        var seconds: TimeInterval {
            switch self {
            case .quick: 15
            case .standard: 120
            }
        }
    }

    @Published var selectedLength: CaptureLength = .quick
    @Published private(set) var report: DiagnosticReport?
    @Published private(set) var baselineReport: DiagnosticReport?
    @Published private(set) var comparison: DiagnosticComparison?
    @Published private(set) var comparisonFromSavedBaseline = false
    @Published private(set) var savedBaselineReport: DiagnosticReport?
    @Published private(set) var isRecording = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var recentReports: [DiagnosticReport] = []
    @Published private(set) var historyStorageError: String?
    @Published private(set) var baselineStorageError: String?

    private let recorder: DiagnosticRecorder
    private let engine = DiagnosticEngine()
    private let historyStore: DiagnosticHistoryStore
    private let baselineStore: KnownGoodBaselineStore
    private var recordingTask: Task<Void, Never>?
    private var historySaveTask: Task<Void, Never>?
    private var historyLoaded = false

    init(recorder: DiagnosticRecorder = DiagnosticRecorder(),
         historyStore: DiagnosticHistoryStore = DiagnosticHistoryStore(),
         baselineStore: KnownGoodBaselineStore = KnownGoodBaselineStore()) {
        self.recorder = recorder
        self.historyStore = historyStore
        self.baselineStore = baselineStore
        if CommandLine.arguments.contains("--preview-fixture") {
            let before = engine.analyze(DiagnosticFixtures.temporaryBuildCapture())
            let after = engine.analyze(DiagnosticFixtures.settledCapture())
            baselineReport = before
            report = after
            comparison = engine.compare(before: before, after: after)
            historyLoaded = true
        }
    }

    /// Menu wording keeps never-run, running, failed and finished states distinct.
    var menuStatus: String {
        if isRecording { return "Recording diagnosis · \(Int(progress * 100))%" }
        if errorMessage != nil { return "Last diagnosis needs attention" }
        if let report {
            return "Last diagnosis \(report.capture.endedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No diagnosis recorded yet"
    }

    func loadHistory() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        let captures = await historyStore.load()
        recentReports = captures.map(engine.analyze)
        if let baseline = await baselineStore.load() {
            savedBaselineReport = engine.analyze(baseline)
        }
    }

    func startRecording() {
        beginRecording(comparingTo: savedBaselineReport, fromSavedBaseline: savedBaselineReport != nil)
    }

    /// A fan check compares only with the open recording, not a potentially
    /// unrelated saved slowdown baseline. Recaptures preserve recording length.
    func recordFanCheck() {
        guard !isRecording else { return }
        if let report {
            selectedLength = report.capture.duration >= 60 ? .standard : .quick
        }
        beginRecording(comparingTo: report, fromSavedBaseline: false)
    }

    func performRecommendedAction() {
        if report?.finding.kind == .healthy || report?.finding.kind == .inconclusive {
            selectedLength = .standard
        }
        beginRecording(comparingTo: report, fromSavedBaseline: false)
    }

    private func beginRecording(comparingTo baseline: DiagnosticReport?, fromSavedBaseline: Bool) {
        recordingTask?.cancel()
        let previousReport = report
        baselineReport = baseline
        comparisonFromSavedBaseline = fromSavedBaseline
        comparison = nil
        isRecording = true
        progress = 0
        errorMessage = nil
        report = nil
        let duration = selectedLength.seconds

        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let capture = try await recorder.record(duration: duration) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                let nextReport = engine.analyze(capture)
                accept(nextReport)
                if let baseline {
                    comparison = engine.compare(before: baseline, after: nextReport)
                }
                DaddyCompletionNotices.postIfWindowHidden(
                    title: "Performance diagnosis complete",
                    body: "Open PerformanceDaddy to review the report."
                )
            } catch is CancellationError {
                errorMessage = "The recording was cancelled. No changes were made."
                report = previousReport
                baselineReport = nil
                comparisonFromSavedBaseline = false
            } catch {
                errorMessage = "The recording could not finish: \(error.localizedDescription)"
                report = previousReport
                baselineReport = nil
                comparisonFromSavedBaseline = false
            }
            isRecording = false
        }
    }

    func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
    }

    func clearReport() {
        report = nil
        baselineReport = nil
        comparison = nil
        comparisonFromSavedBaseline = false
        errorMessage = nil
        progress = 0
    }

    func accept(_ completed: DiagnosticReport) {
        report = completed
        recentReports.insert(completed, at: 0)
        if recentReports.count > 10 { recentReports.removeLast(recentReports.count - 10) }
        persistHistory()
    }

    func review(_ previous: DiagnosticReport) {
        guard !isRecording else { return }
        report = previous
        baselineReport = nil
        comparison = nil
        comparisonFromSavedBaseline = false
        errorMessage = nil
    }

    func saveKnownGoodBaseline(_ selected: DiagnosticReport) async {
        guard !isRecording, !selected.capture.isFixture else { return }
        do {
            try await baselineStore.save(selected.capture)
            savedBaselineReport = selected
            if comparisonFromSavedBaseline {
                baselineReport = nil
                comparison = nil
                comparisonFromSavedBaseline = false
            }
            baselineStorageError = nil
        } catch {
            baselineStorageError = "The known-good baseline could not be saved locally."
        }
    }

    func deleteKnownGoodBaseline() async {
        do {
            try await baselineStore.delete()
            savedBaselineReport = nil
            if comparisonFromSavedBaseline {
                baselineReport = nil
                comparison = nil
                comparisonFromSavedBaseline = false
            }
            baselineStorageError = nil
        } catch {
            baselineStorageError = "The known-good baseline could not be removed."
        }
    }

    func deleteRecentRuns() async {
        await historySaveTask?.value
        do {
            try await historyStore.deleteAll()
            recentReports = []
            clearReport()
            historyStorageError = nil
        } catch {
            historyStorageError = "Recent runs could not be removed locally."
        }
    }

    func waitForHistoryPersistence() async {
        await historySaveTask?.value
    }

    private func persistHistory() {
        let captures = recentReports.map(\.capture)
        let previous = historySaveTask
        let store = historyStore
        historySaveTask = Task { [weak self] in
            await previous?.value
            do {
                try await store.save(captures)
                await MainActor.run { self?.historyStorageError = nil }
            } catch {
                await MainActor.run {
                    self?.historyStorageError = "Recent runs could not be saved locally."
                }
            }
        }
    }
}
