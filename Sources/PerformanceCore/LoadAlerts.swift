import Foundation

/// Thresholds for a sustained-load alert. An alert is evidence for the owner
/// to review; it never acts on a process by itself.
public struct LoadAlertPolicy: Equatable, Sendable {
    public var cpuFraction: Double
    public var cpuSeconds: TimeInterval
    public var memorySeconds: TimeInterval
    public var cooldown: TimeInterval
    /// Share of used CPU (or resident memory) a contributor needs to be named.
    public var minimumShare: Double
    /// A longer gap between readings breaks continuity; missing evidence is not idle.
    public var maximumGap: TimeInterval
    public init(cpuFraction: Double = 0.8, cpuSeconds: TimeInterval = 90, memorySeconds: TimeInterval = 60,
                cooldown: TimeInterval = 900, minimumShare: Double = 0.3, maximumGap: TimeInterval = 65) {
        self.cpuFraction = cpuFraction; self.cpuSeconds = cpuSeconds; self.memorySeconds = memorySeconds
        self.cooldown = cooldown; self.minimumShare = minimumShare; self.maximumGap = maximumGap
    }
}

/// The workload a load alert names: an app with its helpers, an agent session,
/// or an individual process. `targets` is the exact reviewed scope captured at
/// alert time; identities are re-validated when the owner acts.
public struct LoadContributor: Sendable {
    public enum Kind: String, Sendable { case app, agent, process }
    public let kind: Kind
    public let name: String
    /// Stable across launches; used for the owner's "don't alert" list.
    public let ignoreKey: String
    public let owner: LiveProcess
    public let targets: [LiveProcess]
    public let cpuCores: Double
    public let memoryBytes: UInt64
    public var appPath: String? { kind == .app ? owner.appPath : nil }
}

public struct LoadAlert: Sendable {
    public enum Kind: String, Sendable { case cpu, memory }
    public let kind: Kind
    public let since: Date
    public let date: Date
    public let usedCores: Double?
    public let coreCount: Int
    public let pressure: String
    /// Nil when no single workload consistently led the load.
    public let contributor: LoadContributor?
    public var duration: TimeInterval { date.timeIntervalSince(since) }
}

public enum LoadContributors {
    /// Groups helpers under their outermost app process, agent descendants under
    /// the agent, and leaves everything else individual. App-launched command-line
    /// work is not attributed to the launching app: quitting it would be wrong.
    public static func group(_ processes: [LiveProcess]) -> [LoadContributor] {
        let index = WorkloadIndex(processes)
        var members: [ProcessIdentity: (LoadContributor.Kind, LiveProcess, [LiveProcess])] = [:]
        for process in processes {
            let kind: LoadContributor.Kind
            let owner: LiveProcess
            if let agent = index.agentOwner(of: process) {
                kind = .agent; owner = agent
            } else if let path = process.appPath {
                kind = .app
                owner = index.ancestors(of: process).last { $0.appPath == path && $0.uid == process.uid } ?? process
            } else {
                kind = .process; owner = process
            }
            members[owner.id, default: (kind, owner, [])].2.append(process)
        }
        return members.values.map { kind, owner, group in
            let name: String
            let key: String
            switch kind {
            case .app:
                name = URL(fileURLWithPath: owner.appPath ?? owner.executable).deletingPathExtension().lastPathComponent
                key = "app:\(owner.appPath ?? owner.executable)"
            case .agent:
                name = "\(owner.agent ?? owner.name) session"
                key = "agent:\(owner.agent ?? owner.name)"
            case .process:
                name = owner.name
                key = "process:\(owner.executable.isEmpty ? owner.name : owner.executable)"
            }
            let targets = kind == .app ? [owner] : index.descendants(of: owner)
            return LoadContributor(kind: kind, name: name, ignoreKey: key, owner: owner,
                                   targets: targets.isEmpty ? [owner] : targets,
                                   cpuCores: group.reduce(0) { $0 + ($1.cpu.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0) / 100 },
                                   memoryBytes: group.reduce(0) { $0 &+ $1.memory })
        }
    }
}

/// Rolling detector fed once per live sample. A reading that is below the
/// threshold, unreadable, or separated by a long gap restarts the window.
public struct SustainedLoadTracker: Sendable {
    private struct Reading: Sendable {
        let date: Date
        let leader: String?
    }
    public var policy: LoadAlertPolicy
    private var cpuRun: [Reading] = []
    private var memoryRun: [Reading] = []
    private var lastAlert: Date?

    public init(policy: LoadAlertPolicy = LoadAlertPolicy()) { self.policy = policy }

    public mutating func reset() { cpuRun.removeAll(); memoryRun.removeAll() }

    public mutating func observe(_ snapshot: LiveSnapshot, coreCount: Int,
                                 ignored: Set<String> = []) -> LoadAlert? {
        let date = snapshot.date
        guard date.timeIntervalSince1970.isFinite, coreCount > 0 else { reset(); return nil }
        let contributors = LoadContributors.group(snapshot.processes)
        let used = snapshot.system.usedCPUCores.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

        let cpuOver = used.map { $0 >= policy.cpuFraction * Double(coreCount) } ?? false
        let cpuLeader = contributors.max { $0.cpuCores < $1.cpuCores }
            .flatMap { leader in used.flatMap { $0 > 0 && leader.cpuCores / $0 >= policy.minimumShare ? leader : nil } }
        Self.extend(&cpuRun, cpuOver, Reading(date: date, leader: cpuLeader?.ignoreKey), policy.maximumGap)

        let memoryOver = snapshot.pressure == "Warning" || snapshot.pressure == "Critical"
        let resident = contributors.reduce(UInt64(0)) { $0 &+ $1.memoryBytes }
        let memoryLeader = contributors.max { $0.memoryBytes < $1.memoryBytes }
            .flatMap { resident > 0 && Double($0.memoryBytes) / Double(resident) >= policy.minimumShare ? $0 : nil }
        Self.extend(&memoryRun, memoryOver, Reading(date: date, leader: memoryLeader?.ignoreKey), policy.maximumGap)

        if let lastAlert, date.timeIntervalSince(lastAlert) < policy.cooldown, date >= lastAlert { return nil }
        let candidates: [(LoadAlert.Kind, [Reading], TimeInterval, LoadContributor?)] = [
            (.cpu, cpuRun, policy.cpuSeconds, cpuLeader),
            (.memory, memoryRun, policy.memorySeconds, memoryLeader),
        ]
        for (kind, run, seconds, leader) in candidates {
            guard let first = run.first, date.timeIntervalSince(first.date) >= seconds else { continue }
            let named = leader.flatMap { Self.consistent($0.ignoreKey, in: run) ? $0 : nil }
            // The owner asked not to hear about this workload; stay quiet rather
            // than name a weaker contributor.
            if let named, ignored.contains(named.ignoreKey) { continue }
            lastAlert = date
            reset()
            return LoadAlert(kind: kind, since: first.date, date: date, usedCores: used, coreCount: coreCount,
                             pressure: snapshot.pressure, contributor: named)
        }
        return nil
    }

    private static func extend(_ run: inout [Reading], _ over: Bool, _ reading: Reading, _ maximumGap: TimeInterval) {
        guard over else { run.removeAll(); return }
        if let last = run.last, !(0...maximumGap).contains(reading.date.timeIntervalSince(last.date)) { run.removeAll() }
        run.append(reading)
    }

    /// The same workload led at least 80% of readings, including the latest.
    private static func consistent(_ key: String, in run: [Reading]) -> Bool {
        guard run.last?.leader == key else { return false }
        return run.filter { $0.leader == key }.count * 5 >= run.count * 4
    }
}
