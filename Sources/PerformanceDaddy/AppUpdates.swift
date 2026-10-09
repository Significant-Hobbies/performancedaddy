import Combine

@MainActor final class AppUpdates: DaddyAppUpdates {
    init() {
        super.init(appName: "PerformanceDaddy", busyMessage: "Finish the current recording or reviewed process action before checking for updates.")
    }

    func start(live: LiveViewModel, diagnosis: DiagnosisViewModel) {
        start(observing: live.objectWillChange.merge(with: diagnosis.objectWillChange).eraseToAnyPublisher()) { [weak live, weak diagnosis] in
            guard let live, let diagnosis else { return false }
            return !diagnosis.isRecording && !live.performingAction && live.review == nil
        }
    }
}
