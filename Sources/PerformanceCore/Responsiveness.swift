import Foundation

/// These measure service/dispatch latency, not pixels presented or keyboard-to-display latency.
public struct AppResponseProbe: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case replied, didNotReply, permissionMissing, unsupported, targetChanged, disabled }
    public let date: Date
    public let app: String
    public let bundleID: String?
    public let version: String?
    public let status: Status
    public let milliseconds: Double?
    public let timeoutMilliseconds: Double
    public init(date: Date, app: String, bundleID: String?, version: String? = nil, status: Status,
                milliseconds: Double?, timeoutMilliseconds: Double = 250) {
        self.date = date; self.app = ForegroundEvidence.clean(app); self.bundleID = bundleID
        self.version = version; self.status = status
        self.milliseconds = milliseconds.flatMap { $0.isFinite && $0 >= 0 && $0 <= 60_000 ? $0 : nil }
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}

public struct ResponsivenessEvidence: Codable, Equatable, Sendable {
    public let windowStartedAt: Date
    public let windowEndedAt: Date
    public let heartbeatCount: Int
    public let heartbeatMaximumMilliseconds: Double?
    public let localEventCount: Int
    public let localEventMaximumMilliseconds: Double?
    public let appProbe: AppResponseProbe?
    public init(windowStartedAt: Date, windowEndedAt: Date, heartbeatCount: Int,
                heartbeatMaximumMilliseconds: Double?, localEventCount: Int = 0,
                localEventMaximumMilliseconds: Double? = nil, appProbe: AppResponseProbe? = nil) {
        self.windowStartedAt = windowStartedAt; self.windowEndedAt = windowEndedAt
        self.heartbeatCount = max(0, heartbeatCount); self.localEventCount = max(0, localEventCount)
        self.heartbeatMaximumMilliseconds = Self.valid(heartbeatMaximumMilliseconds)
        self.localEventMaximumMilliseconds = Self.valid(localEventMaximumMilliseconds)
        self.appProbe = appProbe
    }
    private static func valid(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 && $0 <= 60_000 ? $0 : nil }
    }
}

public struct ResponsivenessSummary: Equatable, Sendable {
    public let probeCount: Int
    public let replyCount: Int
    public let noReplyCount: Int
    public let p95Milliseconds: Double?
    public let bundleIDs: Set<String>
    public let versions: Set<String>
    public let timeouts: Set<Double>
    public let monitorPeakMilliseconds: Double?
    public let localEventPeakMilliseconds: Double?
    public let monitorCount: Int
    public let eventCount: Int
    public let unavailableProbeCount: Int
    public let probeSpan: TimeInterval
    public let details: String
    public static func analyze(_ capture: DiagnosticCapture) -> Self {
        var sampleDates = Set<Date>()
        let evidence = capture.samples.filter { $0.timestamp >= capture.startedAt && $0.timestamp <= capture.endedAt && sampleDates.insert($0.timestamp).inserted }.compactMap(\.responsiveness)
        // A single observation must not manufacture a repeated probe through duplicate samples.
        var dates = Set<Date>()
        let probes = evidence.compactMap(\.appProbe).filter {
            $0.date >= capture.startedAt && $0.date <= capture.endedAt && dates.insert($0.date).inserted
        }
        let attempts = probes.filter { $0.status == .replied || $0.status == .didNotReply }
        let replies = attempts.filter { $0.status == .replied }.compactMap(\.milliseconds).filter { $0.isFinite && $0 >= 0 }
        let noReply = attempts.filter { $0.status == .didNotReply }.count
        let sorted = replies.sorted()
        let targets = Set(attempts.map { ($0.bundleID ?? $0.app) + ":" + ($0.version ?? "unknown") })
        let p95 = sorted.isEmpty || targets.count != 1 ? nil : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        let peak = evidence.compactMap(\.heartbeatMaximumMilliseconds).max()
        let eventPeak = evidence.compactMap(\.localEventMaximumMilliseconds).max()
        let counts = evidence.reduce(0) { $0 + $1.heartbeatCount }
        let events = evidence.reduce(0) { $0 + $1.localEventCount }
        let app = targets.count > 1 ? "Multiple app services (mixed targets/versions)" : attempts.last?.app ?? probes.last?.app ?? "Last-used app"
        let availability: String
        if attempts.isEmpty {
            availability = probes.last?.status == .permissionMissing ? "App response unavailable: Accessibility access is off." :
                probes.last?.status == .disabled || probes.isEmpty ? "App response probe is off or was not recorded." : "App response unavailable: the target changed or does not support this request."
        } else {
            availability = "\(app): \(replies.count)/\(attempts.count) accessibility-service replies; \(noReply) requests did not reply. Reply p95 \(p95.map { String(format: "%.1f ms", $0) } ?? "unavailable")."
        }
        return Self(probeCount: attempts.count, replyCount: replies.count, noReplyCount: noReply, p95Milliseconds: p95,
                    bundleIDs: Set(attempts.compactMap(\.bundleID)), versions: Set(attempts.compactMap(\.version)),
                    timeouts: Set(attempts.map(\.timeoutMilliseconds)), monitorPeakMilliseconds: peak,
                    localEventPeakMilliseconds: eventPeak, monitorCount: counts, eventCount: events,
                    unavailableProbeCount: probes.filter { $0.status != .replied && $0.status != .didNotReply }.count,
                    probeSpan: attempts.map(\.date).max().flatMap { last in attempts.map(\.date).min().map { last.timeIntervalSince($0) } } ?? 0,
                    details: availability + " PerformanceDaddy main-queue peak \(peak.map { String(format: "%.1f ms", $0) } ?? "unavailable") across \(counts) heartbeats; local input dispatch peak \(eventPeak.map { String(format: "%.1f ms", $0) } ?? "unavailable") across \(events) events. Input contents are never collected.")
    }
}

public enum ReportedSymptom: String, Codable, CaseIterable, Sendable {
    case wholeMac = "Whole Mac felt slow", typing = "Typing lag", switching = "App switching lag"
    case scrolling = "Scrolling stalls", beachball = "Beachballs", fans = "Loud fans"
}

public enum ReportedChange: String, Codable, CaseIterable, Sendable {
    case none = "No change — repeat the task", waited = "Waited for background work"
    case paused = "Paused a workload myself", quit = "Quit an app myself"
    case cooled = "Let the Mac cool", other = "Another change"
}

public enum ReportedOutcome: String, Codable, CaseIterable, Sendable {
    case notAssessed = "Not assessed", better = "Felt better", same = "Felt the same"
    case worse = "Felt worse", notReproduced = "Could not repeat the symptom"
}

/// One flat baseline, not a recursive capture chain. Retains its relationship after history rotates.
public struct FollowUpBaseline: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let samples: [SystemSample]
    public let isFixture: Bool
    public init(_ capture: DiagnosticCapture) {
        let start = max(capture.startedAt, capture.marker?.date ?? capture.startedAt)
        startedAt = start; endedAt = capture.endedAt; isFixture = capture.isFixture
        var dates = Set<Date>()
        let window = capture.samples.filter { $0.timestamp >= start && $0.timestamp <= capture.endedAt && dates.insert($0.timestamp).inserted }.sorted { $0.timestamp < $1.timestamp }
        samples = window.count <= 64 ? window : (0..<64).map { window[Int(Double($0) * Double(window.count - 1) / 63)] }
    }
    public var capture: DiagnosticCapture {
        DiagnosticCapture(startedAt: startedAt, endedAt: endedAt, samples: samples, isFixture: isFixture)
    }
}

public struct FollowUpEvidence: Codable, Equatable, Sendable {
    public let baseline: FollowUpBaseline
    public let task: String
    public let change: ReportedChange
    public let changeDetail: String
    public let sameTaskConfirmed: Bool
    public let outcome: ReportedOutcome
    public init(baseline: FollowUpBaseline, task: String, change: ReportedChange, changeDetail: String,
                sameTaskConfirmed: Bool, outcome: ReportedOutcome = .notAssessed) {
        self.baseline = baseline; self.task = ForegroundEvidence.clean(task)
        self.change = change; self.changeDetail = ForegroundEvidence.clean(changeDetail)
        self.sameTaskConfirmed = sameTaskConfirmed; self.outcome = outcome
    }
    public func reporting(_ outcome: ReportedOutcome) -> Self {
        Self(baseline: baseline, task: task, change: change, changeDetail: changeDetail,
             sameTaskConfirmed: sameTaskConfirmed, outcome: outcome)
    }
    public func compareResponsiveness(_ after: DiagnosticCapture) -> DiagnosticComparison {
        let a = ResponsivenessSummary.analyze(baseline.capture), b = ResponsivenessSummary.analyze(after)
        func result(_ outcome: ComparisonOutcome, _ title: String, _ detail: String) -> DiagnosticComparison {
            .init(outcome: outcome, title: title, detail: detail, cpuDelta: nil, memoryHeadroomDelta: nil)
        }
        let beforePower = Set(baseline.samples.compactMap { $0.power?.lowPowerMode })
        let afterPower = Set(after.samples.compactMap { $0.power?.lowPowerMode })
        guard sameTaskConfirmed, !task.isEmpty, baseline.capture.duration >= 3, after.duration >= 3,
              max(baseline.capture.duration, after.duration) / min(baseline.capture.duration, after.duration) <= 1.25,
              baseline.isFixture == after.isFixture, beforePower.count == 1, afterPower.count == 1,
              beforePower == afterPower, a.bundleIDs.count == 1, a.bundleIDs == b.bundleIDs,
              a.versions.count == 1, a.versions == b.versions, a.timeouts.count == 1, a.timeouts == b.timeouts,
              a.probeCount >= 5, b.probeCount >= 5,
              a.unavailableProbeCount == 0, b.unavailableProbeCount == 0,
              a.probeSpan >= baseline.capture.duration * 0.75, b.probeSpan >= after.duration * 0.75 else {
            return result(.inconclusive, "Responsiveness comparison needs matching evidence.", "Repeat the same task and app/version for the same duration and power mode, with at least five enabled app probes in each capture. Resource load and PerformanceDaddy's own dispatch delay cannot stand in for the other app's response.")
        }
        guard a.noReplyCount == 0, b.noReplyCount == 0,
              a.replyCount == a.probeCount, b.replyCount == b.probeCount,
              let before = a.p95Milliseconds, let afterValue = b.p95Milliseconds else {
            return result(.inconclusive, "Some app requests did not reply.", "Before: \(a.noReplyCount)/\(a.probeCount); after: \(b.noReplyCount)/\(b.probeCount). Missing replies are censored evidence, not zero-latency measurements or proof of a hang. Repeat the task or import the app's stacks.")
        }
        let delta = afterValue - before
        let threshold = max(20, before * 0.3)
        let outcome: ComparisonOutcome = delta <= -threshold ? .improved : delta >= threshold ? .worsened : .unchanged
        return result(outcome, outcome == .improved ? "The app service replied faster." : outcome == .worsened ? "The app service replied more slowly." : "App service response was broadly unchanged.",
                      String(format: "Reply p95 %.1f → %.1f ms. ", before, afterValue) + "This measures a read-only accessibility request. It does not measure pixels, typing or scrolling latency, or prove that the declared change caused the difference.")
    }
}

/// A target change never grants another read inside the global request budget.
public struct AppProbeCadence: Sendable {
    private var lastAttempt: Double?
    public init() {}
    public mutating func take(at time: Double) -> Bool {
        guard time.isFinite, time >= 0, lastAttempt.map({ time - $0 >= 5 }) ?? true else { return false }
        lastAttempt = time
        return true
    }
}

extension DiagnosticCapture {
    public func withFollowUp(_ followUp: FollowUpEvidence?) -> Self {
        Self(startedAt: startedAt, endedAt: endedAt, samples: samples, isFixture: isFixture, marker: marker, followUp: followUp)
    }
}

extension SystemSample {
    public func withResponsiveness(_ evidence: ResponsivenessEvidence) -> Self {
        Self(timestamp: timestamp, usedCPUCores: usedCPUCores, memoryHeadroomRatio: memoryHeadroomRatio,
             swapUsedBytes: swapUsedBytes, diskFreeBytes: diskFreeBytes, thermal: thermal, processes: processes,
             samplerCPUCores: samplerCPUCores, memory: memory, power: power, workloads: workloads,
             incident: incident, responsiveness: evidence)
    }
}
