import AppKit
import PerformanceCore
import Foundation

/// Native, bounded read-only qualification and diagnostic capture. No subprocesses.
enum PerformanceDiagnosticCommand {
    static func run(arguments: [String]) -> Never {
        if arguments == ["--capture-diagnostic", "--help"] {
            FileHandle.standardOutput.write(Data(DiagnosticCaptureOptions.usage.utf8))
            exit(0)
        }
        guard let options = DiagnosticCaptureOptions.parse(arguments: arguments) else {
            FileHandle.standardError.write(Data(DiagnosticCaptureOptions.usage.utf8)); exit(2)
        }
        let output = URL(fileURLWithPath: options.outputPath)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            FileHandle.standardError.write(Data("Output already exists; choose a new path.\n".utf8)); exit(2)
        }
        let foreground: ForegroundEvidence?
        if options.includesForegroundEvidence {
            let app = NSWorkspace.shared.frontmostApplication
            foreground = app.flatMap { app in app.localizedName.map { ForegroundEvidence(name: $0, bundleID: app.bundleIdentifier, observedAt: Date()) } }
        } else {
            foreground = nil
        }
        Task.detached(priority: .utility) {
            do {
                let sampler = WorkloadSampler()
                var builder = SnapshotEvidenceBuilder()
                let startedAt = Date(), end = ContinuousClock.now.advanced(by: .seconds(options.duration))
                var samples: [SystemSample] = []
                var readableProcessSamples = 0
                var unavailableProcessSamples = 0
                repeat {
                    try Task.checkCancellation()
                    let snapshot: LiveSnapshot
                    if let selectedPIDs = options.selectedSameUserPIDs {
                        snapshot = await sampler.sample(selectedSameUserPIDs: selectedPIDs)
                    } else {
                        snapshot = await sampler.sample(includePorts: false)
                    }
                    readableProcessSamples += snapshot.processes.count
                    unavailableProcessSamples += snapshot.unavailableProcesses
                    samples.append(builder.sample(snapshot, foreground: foreground))
                    if ContinuousClock.now >= end { break }
                    try await Task.sleep(for: .seconds(2))
                } while true
                let selectedPIDs = options.selectedSameUserPIDs
                let scopeStatement = selectedPIDs == nil
                    ? "System metrics are system-wide. Process evidence comes from the system process enumeration and may omit inaccessible processes."
                    : "System metrics are system-wide. Process evidence is limited to the explicitly selected same-user PIDs; all other processes are unobserved. This is not whole-Mac process coverage."
                let processScope = DiagnosticProcessScope(
                    coverage: selectedPIDs == nil ? .systemProcessEnumeration : .selectedSameUserPIDs,
                    selectedPIDCount: selectedPIDs?.count,
                    readableProcessSamples: readableProcessSamples,
                    unavailableProcessSamples: unavailableProcessSamples,
                    statement: scopeStatement)
                let capture = DiagnosticCapture(startedAt: startedAt, endedAt: Date(), samples: samples,
                                                processScope: processScope)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(capture).write(to: output, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                let report = DiagnosticEngine().analyze(capture)
                print("PerformanceDaddy native diagnostic captured \(samples.count) observations")
                print(scopeStatement)
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
