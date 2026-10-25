import Foundation

public struct WorkloadAlertLimit: Codable, Equatable, Sendable {
    public var name: String
    public var cpuPercent: Int
    public var memoryGB: Int
    public init(name: String, cpuPercent: Int = 100, memoryGB: Int = 4) {
        self.name = name; self.cpuPercent = cpuPercent; self.memoryGB = memoryGB
    }
}

public struct WatchdogPolicy: Codable, Equatable, Sendable {
    public var kinds: Set<LoadAlert.Kind> = [.processCPU, .memoryGrowth, .thermal, .fans]
    /// Process percentages use one core as 100%, independently of system capacity.
    public var processCPUPercent = 80
    public var processSeconds: TimeInterval = 180
    public var memoryGB = 4
    public var growthMB = 512
    public var growthSeconds: TimeInterval = 300
    public var thermalSeconds: TimeInterval = 60
    public var fanPercent = 85
    public var fanSeconds: TimeInterval = 120
    public var cooldown: TimeInterval = 900
    public var maximumGap: TimeInterval = 65
    public var limits: [String: WorkloadAlertLimit] = [:]
    public init() {}
}

/// All rules share one workload census. Windows and cooldowns are bounded, local,
/// and scoped by exact owner identity: a restarted process cannot inherit a run.
public struct PerformanceWatchdog: Sendable {
    private struct Key: Hashable, Sendable {
        let kind: LoadAlert.Kind
        let owner: ProcessIdentity?
    }
    private struct Window: Sendable {
        var since: Date
        var last: Date
        var samples: Int
        var initialBytes: UInt64
        var lastBytes: UInt64
        var memory: [MemoryPoint] = []
        var members: Set<ProcessIdentity> = []
    }
    private struct MemoryPoint: Sendable { let date: Date; let bytes: UInt64 }
    public var policy = WatchdogPolicy()
    public var loadPolicy = LoadAlertPolicy()
    public private(set) var needsCloserLook = false
    private var load = SustainedLoadTracker()
    private var windows: [Key: Window] = [:]
    private var cooldowns: [Key: Date] = [:]
    private var lastDate: Date?
    public init() {}

    public mutating func reset() {
        windows.removeAll(); load.reset(); lastDate = nil; needsCloserLook = false
    }

    public mutating func observe(_ snapshot: LiveSnapshot, coreCount: Int, ignored: Set<String> = []) -> [LoadAlert] {
        let now = snapshot.date
        guard now.timeIntervalSince1970.isFinite, coreCount > 0 else { reset(); return [] }
        if let lastDate, now <= lastDate || now.timeIntervalSince(lastDate) > policy.maximumGap { reset() }
        lastDate = now
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) >= 0 && now.timeIntervalSince($0.value) < max(0, policy.cooldown) }
        let contributors = LoadContributors.group(snapshot.processes)
        load.policy = loadPolicy
        var alerts = load.observeAll(snapshot, coreCount: coreCount, ignored: ignored, contributors: contributors)
        needsCloserLook = snapshot.pressure == "Warning" || snapshot.pressure == "Critical"
            || (snapshot.system.usedCPUCores ?? 0) >= loadPolicy.cpuFraction * Double(coreCount)
        var seen: Set<Key> = []

        func alert(_ kind: LoadAlert.Kind, _ window: Window, _ contributor: LoadContributor?, _ detail: String) -> LoadAlert {
            LoadAlert(kind: kind, since: window.since, date: now, usedCores: snapshot.system.usedCPUCores,
                      coreCount: coreCount, pressure: snapshot.pressure, contributor: contributor, detail: detail)
        }

        // Rank by CPU and resident memory, plus up to 128 configured groups,
        // so a busy small process cannot be hidden by large idle apps.
        let configured = contributors.filter { policy.limits[$0.ignoreKey] != nil }.sorted { $0.owner.id.pid < $1.owner.id.pid }.prefix(128)
        let trackedIDs = Set(contributors.sorted { $0.cpuCores > $1.cpuCores }.prefix(64).map(\.owner.id))
            .union(contributors.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(64).map(\.owner.id))
            .union(configured.map(\.owner.id))
        for contributor in contributors where trackedIDs.contains(contributor.owner.id) && !ignored.contains(contributor.ignoreKey) {
            let limit = policy.limits[contributor.ignoreKey]
            let cpuLimit = Double(max(1, limit?.cpuPercent ?? policy.processCPUPercent)) / 100
            let memoryLimit = UInt64(max(1, min(1_024, limit?.memoryGB ?? policy.memoryGB))) * 1_073_741_824
            for kind in [LoadAlert.Kind.processCPU, .largeMemory, .memoryGrowth] {
                guard policy.kinds.contains(kind) || (limit != nil && kind != .memoryGrowth) else { continue }
                let key = Key(kind: kind, owner: contributor.owner.id)
                seen.insert(key)
                let over: Bool
                let seconds: TimeInterval
                switch kind {
                case .processCPU:
                    // The grouped value is a lower bound of finite, positive
                    // readings. A busy helper can meet the limit even when the
                    // app's idle parent is unreadable; all-unreadable sums to 0.
                    over = contributor.cpuCores >= cpuLimit; seconds = policy.processSeconds
                case .largeMemory:
                    over = contributor.memoryBytes >= memoryLimit; seconds = policy.processSeconds
                default:
                    over = true; seconds = policy.growthSeconds
                }
                guard over else { windows.removeValue(forKey: key); continue }
                if kind != .memoryGrowth { needsCloserLook = true }
                var window = windows[key] ?? Window(since: now, last: now, samples: 0,
                                                    initialBytes: contributor.memoryBytes, lastBytes: contributor.memoryBytes)
                // Drops and changing helper coverage start a new growth window.
                // Returning or new processes are not measured memory growth.
                if kind == .memoryGrowth && (contributor.memoryBytes < window.lastBytes / 2 || window.members != contributor.memberIdentities) {
                    window = Window(since: now, last: now, samples: 0, initialBytes: contributor.memoryBytes, lastBytes: contributor.memoryBytes)
                }
                window.last = now; window.samples += 1; window.lastBytes = contributor.memoryBytes
                if kind == .memoryGrowth {
                    window.members = contributor.memberIdentities
                    window.memory.removeAll { now.timeIntervalSince($0.date) > max(60, policy.growthSeconds) + policy.maximumGap }
                    window.memory.append(MemoryPoint(date: now, bytes: contributor.memoryBytes))
                    if window.memory.count > 512 { window.memory.removeFirst(window.memory.count - 512) }
                    // Include one predecessor of the requested interval so
                    // jitter never prevents a full-duration comparison.
                    let cutoff = now.addingTimeInterval(-seconds)
                    if let baseline = window.memory.last(where: { $0.date <= cutoff }) {
                        window.since = baseline.date; window.initialBytes = baseline.bytes
                    } else if let first = window.memory.first {
                        window.since = first.date; window.initialBytes = first.bytes
                    }
                }
                windows[key] = window
                guard window.samples >= 3, now.timeIntervalSince(window.since) >= seconds else { continue }
                if kind == .memoryGrowth {
                    let increase = contributor.memoryBytes > window.initialBytes ? contributor.memoryBytes - window.initialBytes : 0
                    guard increase >= UInt64(max(1, min(65_536, policy.growthMB))) * 1_048_576,
                          Double(contributor.memoryBytes) >= Double(window.initialBytes) * 1.5 else {
                        continue
                    }
                }
                guard cooldowns[key] == nil else { continue }
                let detail: String
                switch kind {
                case .processCPU:
                    detail = String(format: "%.1f cores now; threshold %.1f cores. 100%% process CPU means one core.", contributor.cpuCores, cpuLimit)
                        + (contributor.owner.name == "kernel_task" ? " kernel_task can be responding to thermal conditions rather than causing them." : "")
                case .largeMemory:
                    detail = "Resident memory is above your \(limit?.memoryGB ?? policy.memoryGB) GB limit. Memory pressure: \(snapshot.pressure). Large memory use alone is not a fault."
                default:
                    detail = "Resident memory grew from \(Self.bytes(window.initialBytes)) to \(Self.bytes(contributor.memoryBytes)). Growth is observed, not proof of a memory leak."
                }
                alerts.append(alert(kind, window, contributor, detail))
                cooldowns[key] = now
                windows.removeValue(forKey: key)
            }
        }

        for kind in [LoadAlert.Kind.thermal, .fans] where policy.kinds.contains(kind) {
            let key = Key(kind: kind, owner: nil)
            seen.insert(key)
            let hot = snapshot.system.thermal == .serious || snapshot.system.thermal == .critical
            let fastFans = snapshot.hardware?.fans?.filter {
                guard let ratio = $0.fractionOfMaximum else { return false }
                return ratio >= Double(policy.fanPercent) / 100
            } ?? []
            let over = kind == .thermal ? hot : !fastFans.isEmpty
            guard over else { windows.removeValue(forKey: key); continue }
            needsCloserLook = true
            var window = windows[key] ?? Window(since: now, last: now, samples: 0, initialBytes: 0, lastBytes: 0)
            window.last = now; window.samples += 1; windows[key] = window
            let seconds = kind == .thermal ? policy.thermalSeconds : policy.fanSeconds
            guard window.samples >= 3, now.timeIntervalSince(window.since) >= seconds, cooldowns[key] == nil else { continue }
            let measured = kind == .thermal ? "Latest macOS thermal state: \(snapshot.system.thermal.rawValue)." : "Latest fan readings: " + fastFans.map {
                "\($0.name): \(Int($0.rpm ?? 0)) RPM (\(Int(($0.fractionOfMaximum ?? 0) * 100))% of reported maximum)."
            }.joined(separator: " ")
            let leaders = contributors.filter { $0.cpuCores >= 0.2 && $0.owner.name != "kernel_task" }
                .sorted { $0.cpuCores > $1.cpuCores }.prefix(3)
            let work = leaders.isEmpty ? "No substantial CPU workload was observed in the latest reading." :
                "CPU workloads now: " + leaders.map { "\($0.name) \(String(format: "%.1f", $0.cpuCores)) cores" }.joined(separator: ", ") + "."
            // Context is not a quit target or a claim of causal fan ownership.
            alerts.append(alert(kind, window, nil, measured + " " + work + " This does not identify fan-control ownership or prove which app caused heat or throttling. Open Fans & heat for a comparable recording."))
            cooldowns[key] = now
            windows.removeValue(forKey: key)
        }
        windows = windows.filter { seen.contains($0.key) }
        if cooldowns.count > 1_024 {
            cooldowns = Dictionary(uniqueKeysWithValues: cooldowns.sorted { $0.value > $1.value }.prefix(1_024).map { ($0.key, $0.value) })
        }
        return alerts
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }
}
