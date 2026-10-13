import AppKit
import PerformanceCore
import Foundation

/// Native, bounded read-only qualification and diagnostic capture. No subprocesses.
enum PerformanceDiagnosticCommand {
    static func run(arguments: [String]) -> Never {
        guard arguments.count == 3, let duration = Double(arguments[1]), duration.isFinite, duration >= 3, duration <= 120 else {
            FileHandle.standardError.write(Data("Usage: --capture-diagnostic <3..120 seconds> <new output.json>\n".utf8)); exit(2)
        }
        let output = URL(fileURLWithPath: arguments[2])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            FileHandle.standardError.write(Data("Output already exists; choose a new path.\n".utf8)); exit(2)
        }
        let app = NSWorkspace.shared.frontmostApplication
        let foreground = app.flatMap { app in app.localizedName.map { ForegroundEvidence(name: $0, bundleID: app.bundleIdentifier, observedAt: Date()) } }
        Task.detached(priority: .utility) {
            do {
                let sampler = WorkloadSampler()
                var builder = SnapshotEvidenceBuilder()
                let startedAt = Date(), end = ContinuousClock.now.advanced(by: .seconds(duration))
                var samples: [SystemSample] = []
                repeat {
                    try Task.checkCancellation()
                    samples.append(builder.sample(await sampler.sample(includePorts: false), foreground: foreground))
                    if ContinuousClock.now >= end { break }
                    try await Task.sleep(for: .seconds(2))
                } while true
                let capture = DiagnosticCapture(startedAt: startedAt, endedAt: Date(), samples: samples)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(capture).write(to: output, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                let report = DiagnosticEngine().analyze(capture)
                print("PerformanceDaddy native diagnostic captured \(samples.count) observations")
                print(report.rootCauseAnalysis.headline)
                for contributor in report.rootCauseAnalysis.contributors { print(contributor) }
                if let hardware = samples.last?.incident?.hardware {
                    for fan in hardware.fans ?? [] {
                        print("\(fan.name): \(fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "unavailable"); fraction of maximum \(fan.fractionOfMaximum.map { String(format: "%.0f%%", $0 * 100) } ?? "unavailable")")
                    }
                    print("GPU device activity: \(hardware.gpuUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "unavailable")")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Capture failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        dispatchMain()
    }
}
