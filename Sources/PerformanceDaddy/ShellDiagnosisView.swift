import PerformanceCore
import SwiftUI
import SaaSMakerUI

/// A protected-focus review: executing startup scripts is not passive monitoring.
struct ShellDiagnosisView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var consent = false
    @State private var running = false
    @State private var report: ShellDiagnosisReport?
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    private let diagnoser = ShellDiagnoser()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label {
                    SMDisplay("Terminal startup", size: 22).accessibilityLabel("Terminal startup")
                } icon: { Image(systemName: "terminal") }
                Spacer()
                Button("done") { dismiss() }.accessibilityLabel("Done").disabled(running).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Measure zsh startup, then inspect the functions that took time.")
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                    Text("A separate interactive login shell runs in a pseudo-terminal. This is an experiment—not a sandbox. Your startup scripts can write files, access credentials, use the network or launch background programs. PerformanceDaddy does not edit your configuration.")
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    SMDisplay("Choose what to run", size: 17).accessibilityLabel("Choose what to run").accessibilityAddTraits(.isHeader)
                    Text("The minimal baseline skips personal startup files. The system zshenv file can still execute. Profiling runs one baseline and one configured shell, with a 10-second limit per shell.")
                        .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    Toggle("I allow one run of my zsh startup scripts", isOn: $consent)
                        .toggleStyle(.checkbox).disabled(running)
                    HStack {
                        Button("measure minimal shell") { start(profile: false) }.accessibilityLabel("Measure minimal shell").disabled(running)
                        Button("profile my startup") { start(profile: true) }.accessibilityLabel("Profile my startup")
                            .buttonStyle(DaddyButtonStyle(prominent: true)).disabled(!consent || running)
                    }
                    if running {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Measuring in a separate shell…")
                            Spacer()
                            Button("cancel probe") { task?.cancel() }.accessibilityLabel("Cancel probe")
                        }
                    }
                    if let message { Text(message).foregroundStyle(PerformanceTheme.amber) }
                    if let report {
                        Divider()
                        SMDisplay("Measured evidence", size: 17).accessibilityLabel("Measured evidence").accessibilityAddTraits(.isHeader)
                        trial("Minimal shell", report.baseline)
                        if let configured = report.configured {
                            trial("Configured · profiler enabled", configured)
                            if configured.profileAvailable {
                                if configured.functions.isEmpty {
                                    Text("No supported function timings were returned. Top-level commands are not attributed by this profiler.")
                                } else {
                                    SMDisplay("Functions · longest self time first", size: 17).accessibilityLabel("Functions · longest self time first")
                                    HStack {
                                        Text("FUNCTION").frame(maxWidth: .infinity, alignment: .leading)
                                        Text("SELF").frame(width: 75, alignment: .trailing)
                                        Text("INCLUSIVE").frame(width: 85, alignment: .trailing)
                                    }.font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                                    ForEach(configured.functions) { function in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(function.name).textSelection(.enabled)
                                                Text("\(function.calls) calls").font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                            Text(milliseconds(function.selfMilliseconds)).frame(width: 75, alignment: .trailing)
                                                .foregroundStyle(PerformanceTheme.mintInk)
                                            Text(milliseconds(function.totalMilliseconds)).frame(width: 85, alignment: .trailing)
                                        }.monospacedDigit().accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(function.name), \(function.calls) calls, self time \(milliseconds(function.selfMilliseconds)), inclusive time \(milliseconds(function.totalMilliseconds))")
                                    }
                                }
                            } else {
                                Text("Function attribution unavailable. Startup may have exited, changed the profiler, or exceeded the diagnostic limits.")
                                    .foregroundStyle(PerformanceTheme.amber)
                            }
                        }
                    }
                    Divider()
                    SMDisplay("How to read this", size: 17).accessibilityLabel("How to read this")
                    Text("One trial is a clue, not proof. Timings have roughly 5 ms polling resolution and include diagnostic overhead. Self time excludes nested functions; inclusive time includes them—do not add inclusive rows together. This does not measure the first rendered prompt, typing latency, asynchronous work, or your terminal app itself.")
                    Text("The probe uses a minimal environment and starts from your home directory. Terminal-specific environment settings and externally supplied ZDOTDIR values are not reproduced. Ordinary shell output is discarded; only elapsed times and validated function-name rows are shown, in memory only. No command tracing or automatic export.")
                    Text("Cancel stops the diagnostic shell and its original process group. Independently launched or detached background programs may remain. Startup side effects cannot be undone by cancelling.")
                }.font(.callout)
            }
        }
        .padding(24).frame(width: 650, height: 650)
        .background(PerformanceTheme.fog).foregroundStyle(PerformanceTheme.ink)
        .onDisappear { task?.cancel() }
    }

    private func trial(_ title: String, _ trial: ShellTrial) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(outcome(trial)).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }
            Spacer()
            Text(milliseconds(trial.elapsedMilliseconds)).font(.title3.weight(.semibold))
                .monospacedDigit().foregroundStyle(trial.outcome == .completed ? PerformanceTheme.mintInk : PerformanceTheme.amber)
        }.accessibilityElement(children: .combine)
    }

    private func outcome(_ trial: ShellTrial) -> String {
        switch trial.outcome {
        case .completed: "Startup reached diagnostic command"
        case .timedOut: "Timed out · duration is not a completed startup"
        case .outputLimit: "Stopped at output limit · incomplete"
        case .exitedEarly: "No complete marker · exit \(trial.exitCode.map(String.init) ?? "unknown")"
        }
    }
    private func milliseconds(_ value: Double) -> String { String(format: "%.0f ms", value) }

    private func start(profile: Bool) {
        guard !running, !profile || consent else { return }
        running = true; report = nil; message = nil
        consent = false // A new configured run always needs fresh consent.
        task = Task {
            defer { running = false }
            do { report = try await diagnoser.run(profileStartup: profile, consent: profile) }
            catch is CancellationError { message = "Probe cancelled. Startup-script side effects may remain." }
            catch { message = "Could not start the diagnostic shell. No result is available; try the minimal baseline again." }
        }
    }
}
