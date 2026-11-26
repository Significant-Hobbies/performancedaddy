import Darwin
import Foundation

/// Retained only for explicitly selected PIDs. Full captures keep their normal bounded workload summaries.
public struct SelectedCPUTrace: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        let identity: ProcessIdentity
        let cpuCores: Double?
    }
    struct Sample: Codable, Equatable, Sendable {
        let uptime: Double
        let rows: [Row]
    }

    let bootSession: UUID?
    let selectedPIDs: [Int32]
    var samples: [Sample] = []

    public init(selectedPIDs: [Int32]) {
        self.init(selectedPIDs: selectedPIDs, bootSession: Self.currentBootSession())
    }

    init(selectedPIDs: [Int32], bootSession: UUID?) {
        self.selectedPIDs = selectedPIDs
        self.bootSession = bootSession
    }

    private static func currentBootSession() -> UUID? {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = buffer.count
        return sysctlbyname("kern.bootsessionuuid", &buffer, &length, nil, 0) == 0
            ? UUID(uuidString: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) : nil
    }

    public mutating func append(_ processes: [LiveProcess], uptime: Double) {
        samples.append(Sample(uptime: uptime, rows: processes.filter { selectedPIDs.contains($0.id.pid) }.map {
            Row(identity: $0.id, cpuCores: $0.cpu.map { $0 / 100 })
        }))
    }
}

public struct ProcessCPUComparison: Encodable {
    public enum Status: String, Encodable {
        case compared, incompleteIntervals, insufficientObservations, targetUnobserved, pidReused
    }
    public struct Window: Encodable {
        let observations: Int
        let matchingObservations: Int
        let measuredIntervals: Int
        let meanObservedCPUCores: Double?
    }
    public let status: Status
    public let target: ProcessIdentity
    public let before: Window
    public let after: Window
    public let changeInMeanCPUCores: Double?
    public let scope = "Selected process CPU in cores. Other workloads and whole-Mac responsiveness are outside this comparison."

    public enum Failure: String, Error, LocalizedError {
        case missingTrace = "Both files must be native selected-PID captures made with process comparison support."
        case differentBoot = "These captures could not be verified as belonging to the same Mac boot."
        case invalidOrder = "Follow-up must begin after the baseline ends on the same boot."
        case notSelected = "Both captures must explicitly select the requested PID."
        case missingIdentity = "Baseline did not observe one consistent process start identity for this PID."
        case malformed = "Capture contains inconsistent or duplicate observations."

        public var errorDescription: String? { rawValue }
    }

    public init(before baseline: DiagnosticCapture, after followUp: DiagnosticCapture, pid: Int32) throws {
        guard !baseline.isFixture, !followUp.isFixture,
              baseline.processScope?.coverage == .selectedSameUserPIDs, followUp.processScope?.coverage == .selectedSameUserPIDs,
              let a = baseline.selectedCPUTrace, let b = followUp.selectedCPUTrace else { throw Failure.missingTrace }
        guard let session = a.bootSession, session == b.bootSession else { throw Failure.differentBoot }
        guard a.selectedPIDs.contains(pid), b.selectedPIDs.contains(pid) else { throw Failure.notSelected }
        guard a.samples.count == baseline.samples.count, b.samples.count == followUp.samples.count,
              !a.samples.isEmpty, !b.samples.isEmpty else { throw Failure.malformed }
        guard let aEnd = a.samples.last, let bStart = b.samples.first, aEnd.uptime < bStart.uptime else { throw Failure.invalidOrder }
        let identities = Set(a.samples.flatMap(\.rows).map(\.identity).filter { $0.pid == pid })
        guard identities.count == 1, let identity = identities.first, identity.started > 0 else { throw Failure.missingIdentity }
        target = identity
        before = try Self.measure(a, samples: baseline.samples, identity: identity)
        after = try Self.measure(b, samples: followUp.samples, identity: identity)
        if b.samples.flatMap(\.rows).contains(where: { $0.identity.pid == pid && $0.identity != identity }) {
            status = .pidReused
        } else if after.matchingObservations == 0 {
            status = .targetUnobserved
        } else if min(before.observations, after.observations) < 3 {
            status = .insufficientObservations
        } else if before.measuredIntervals == before.observations - 1, after.measuredIntervals == after.observations - 1 {
            status = .compared
        } else { status = .incompleteIntervals }
        if status == .compared, let start = before.meanObservedCPUCores, let end = after.meanObservedCPUCores {
            changeInMeanCPUCores = end - start
        } else { changeInMeanCPUCores = nil }
    }

    private static func measure(_ trace: SelectedCPUTrace, samples: [SystemSample], identity: ProcessIdentity) throws -> Window {
        var observed = 0, intervals = 0
        var coreSeconds = 0.0, seconds = 0.0
        var last: Double?, previousMatched = false
        for (index, sample) in trace.samples.enumerated() {
            let matchingPID = sample.rows.filter { $0.identity.pid == identity.pid }
            guard matchingPID.count <= 1, sample.uptime.isFinite, sample.uptime >= 0 else { throw Failure.malformed }
            let row = matchingPID.first
            let matches = row?.identity == identity
            if matches { observed += 1 }
            if let last {
                let elapsed = sample.uptime - last
                guard elapsed > 0 else { throw Failure.malformed }
                // The two-second timer begins after the previous scan completed.
                let scanDuration = samples[index - 1].incident?.scanSeconds ?? 0
                guard scanDuration.isFinite, scanDuration >= 0, scanDuration <= elapsed else { throw Failure.malformed }
                if matches, previousMatched, elapsed - scanDuration < 4, let cpu = row?.cpuCores, cpu.isFinite, cpu >= 0 {
                    coreSeconds += cpu * elapsed
                    seconds += elapsed
                    intervals += 1
                }
            }
            last = sample.uptime
            previousMatched = matches
        }
        return Window(observations: trace.samples.count, matchingObservations: observed, measuredIntervals: intervals,
                      meanObservedCPUCores: seconds > 0 ? coreSeconds / seconds : nil)
    }
}
