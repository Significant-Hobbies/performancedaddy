import Foundation
import CryptoKit
import Darwin

public struct ForegroundEvidence: Codable, Equatable, Sendable {
    public let name: String
    public let bundleID: String?
    public let observedAt: Date
    public init(name: String, bundleID: String?, observedAt: Date) {
        self.name = Self.clean(name); self.bundleID = bundleID.map(Self.clean); self.observedAt = observedAt
    }
    static func clean(_ text: String) -> String { String(text.filter { !$0.isNewline && !$0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }.prefix(120)) }
}

public struct IncidentMarker: Codable, Equatable, Sendable {
    public let date: Date
    public let symptom: String
    public let foreground: ForegroundEvidence?
    public init(date: Date, symptom: String, foreground: ForegroundEvidence?) {
        self.date = date; self.symptom = ForegroundEvidence.clean(symptom); self.foreground = foreground
    }
}

public struct WorkloadEvidence: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let project: String?
    public let association: String
    public let cpuCores: Double?
    public let residentBytes: UInt64
    public let footprintBytes: UInt64?
    public let readBytesPerSecond: Double?
    public let writtenBytesPerSecond: Double?
    public let processCount: Int
    public let cpuReadableCount: Int
    public let resourceReadableCount: Int
}

public struct IncidentSampleEvidence: Codable, Equatable, Sendable {
    public let logicalCPUs: Int
    public let pressure: String
    public let foreground: ForegroundEvidence?
    public let workloads: [WorkloadEvidence]
    public let readableProcesses: Int
    public let unavailableProcesses: Int
    public let scanSeconds: Double
    public let hardware: HardwareEvidence?
    public let newlyObservedProcesses: Int
    public let noLongerObservedProcesses: Int
}

/// Cumulative I/O counters are rates only across the same instance and a valid interval.
public struct ProcessIORateTracker: Sendable {
    public struct Rates: Sendable { public let read: Double?; public let written: Double? }
    private struct Counter: Sendable { let time: Double; let read: UInt64?; let written: UInt64? }
    private var previous: [ProcessIdentity: Counter] = [:]
    public init() {}
    public mutating func update(_ processes: [LiveProcess], at time: Double) -> [ProcessIdentity: Rates] {
        var next: [ProcessIdentity: Counter] = [:]
        var result: [ProcessIdentity: Rates] = [:]
        for process in processes {
            let counter = Counter(time: time, read: process.diskReadBytes, written: process.diskWrittenBytes)
            next[process.id] = counter
            let old = previous[process.id]
            let interval = old.map { time - $0.time }
            func rate(_ current: UInt64?, _ prior: UInt64?) -> Double? {
                guard time.isFinite, let interval, interval.isFinite, interval >= 0.1, interval <= 30,
                      let current, let prior, current >= prior else { return nil }
                let value = Double(current - prior) / interval
                return value.isFinite ? value : nil
            }
            result[process.id] = Rates(read: rate(counter.read, old?.read), written: rate(counter.written, old?.written))
        }
        previous = next
        return result
    }
    public mutating func reset() { previous.removeAll() }
}

public struct SnapshotEvidenceBuilder: Sendable {
    private var rates = ProcessIORateTracker()
    private var previousIdentities: Set<ProcessIdentity>?
    private var recordingIDs: [String: String] = [:]
    public init() {}
    public mutating func reset() { rates.reset(); previousIdentities = nil; recordingIDs.removeAll() }

    public mutating func sample(_ snapshot: LiveSnapshot, foreground: ForegroundEvidence? = nil,
                                hardware: HardwareEvidence? = nil, monotonicTime: Double = ProcessInfo.processInfo.systemUptime) -> SystemSample {
        let io = rates.update(snapshot.processes, at: monotonicTime)
        let index = WorkloadIndex(snapshot.processes)
        struct Group {
            let name: String; let project: String?; let association: String
            var cpu = 0.0; var resident: UInt64 = 0; var footprint: UInt64 = 0
            var read = 0.0; var written = 0.0; var count = 0; var cpuCount = 0; var resourceCount = 0
            var readCount = 0; var writtenCount = 0
        }
        var groups: [String: Group] = [:]
        var seen = Set<ProcessIdentity>()
        for process in snapshot.processes where seen.insert(process.id).inserted {
            let lineage = [process] + index.ancestors(of: process)
            let agent = index.agentOwner(of: process)
            let app = lineage.first { $0.appPath != nil }
            let projectOwner = agent ?? process
            let isProjectContext = (agent != nil || app == nil) && !projectOwner.directory.isEmpty && projectOwner.directory != "/" && projectOwner.directory != NSHomeDirectory()
            let project = isProjectContext ? ForegroundEvidence.clean(URL(fileURLWithPath: projectOwner.directory).lastPathComponent) : nil
            let name: String
            let association: String
            let key: String
            if let agent {
                name = "\(agent.agent ?? agent.name) · PID \(agent.id.pid)"
                association = "Observed agent ancestry; project is working-directory context"
                key = "process:\(agent.id.pid):\(agent.id.started)"
            } else if let app, process.appPath != nil {
                name = "\(URL(fileURLWithPath: app.appPath!).deletingPathExtension().lastPathComponent) & helpers"
                association = "App bundle path association; publisher identity not verified"
                key = "app:\(app.uid):\(app.appPath!)"
            } else {
                name = "\(process.name) · PID \(process.id.pid)"
                association = app == nil ? "Individual process; ownership unavailable" : "Observed launch ancestry from \(app!.name)"
                key = "process:\(process.id.pid):\(process.id.started)"
            }
            var group = groups[key] ?? Group(name: ForegroundEvidence.clean(name), project: project, association: association)
            group.count += 1
            if let cpu = process.cpu, cpu.isFinite, cpu >= 0 { group.cpu += cpu / 100; group.cpuCount += 1 }
            func add(_ a: UInt64, _ b: UInt64) -> UInt64 { let v = a.addingReportingOverflow(b); return v.overflow ? .max : v.partialValue }
            group.resident = add(group.resident, process.memory)
            if let footprint = process.footprint { group.footprint = add(group.footprint, footprint); group.resourceCount += 1 }
            if let value = io[process.id]?.read { group.read += value; group.readCount += 1 }
            if let value = io[process.id]?.written { group.written += value; group.writtenCount += 1 }
            groups[key] = group
        }
        recordingIDs = recordingIDs.filter { groups[$0.key] != nil }
        for key in groups.keys where recordingIDs[key] == nil {
            recordingIDs[key] = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let all = groups.map { key, value in
            WorkloadEvidence(id: recordingIDs[key]!,
                             name: value.name, project: value.project, association: value.association,
                             cpuCores: value.cpuCount > 0 ? value.cpu : nil, residentBytes: value.resident,
                             footprintBytes: value.resourceCount > 0 ? value.footprint : nil,
                             readBytesPerSecond: value.readCount > 0 ? value.read : nil,
                             writtenBytesPerSecond: value.writtenCount > 0 ? value.written : nil,
                             processCount: value.count, cpuReadableCount: value.cpuCount, resourceReadableCount: value.resourceCount)
        }
        var retained: [WorkloadEvidence] = []; var ids = Set<String>()
        let byCPU = all.sorted { ($0.cpuCores ?? -1) == ($1.cpuCores ?? -1) ? $0.id < $1.id : ($0.cpuCores ?? -1) > ($1.cpuCores ?? -1) }
        let byMemory = all.sorted { ($0.footprintBytes ?? $0.residentBytes) > ($1.footprintBytes ?? $1.residentBytes) }
        let byIO = all.sorted { ($0.readBytesPerSecond ?? 0) + ($0.writtenBytesPerSecond ?? 0) > ($1.readBytesPerSecond ?? 0) + ($1.writtenBytesPerSecond ?? 0) }
        for item in Array(byCPU.prefix(16)) + Array(byMemory.prefix(8)) + Array(byIO.prefix(8)) where ids.insert(item.id).inserted { retained.append(item) }
        let identities = Set(snapshot.processes.map(\.id))
        let started = previousIdentities.map { identities.subtracting($0).count } ?? 0
        let missing = previousIdentities.map { $0.subtracting(identities).count } ?? 0
        previousIdentities = identities
        let base = snapshot.system
        let processes = snapshot.processes.filter { ($0.cpu ?? 0) >= 0.5 }.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(16).map {
            ProcessObservation(id: $0.id.pid, parentID: $0.parent, name: $0.name, cpuCores: ($0.cpu ?? 0) / 100, residentBytes: $0.memory)
        }
        return SystemSample(timestamp: base.timestamp, usedCPUCores: base.usedCPUCores,
                            memoryHeadroomRatio: base.memoryHeadroomRatio, swapUsedBytes: base.swapUsedBytes,
                            diskFreeBytes: base.diskFreeBytes, thermal: base.thermal, processes: processes,
                            samplerCPUCores: snapshot.processes.first { $0.id.pid == getpid() }?.cpu.map { $0 / 100 },
                            memory: base.memory, power: base.power, workloads: retained.compactMap { item in item.cpuCores.map {
                                RecordedWorkload(id: item.id, name: item.name + (item.project.map { " · " + $0 } ?? ""), association: item.association, cpuCores: $0, processCount: item.processCount)
                            } },
                            incident: IncidentSampleEvidence(logicalCPUs: ProcessInfo.processInfo.activeProcessorCount,
                                pressure: snapshot.pressure, foreground: foreground, workloads: retained,
                                readableProcesses: snapshot.processes.count, unavailableProcesses: snapshot.unavailableProcesses,
                                scanSeconds: snapshot.scanSeconds, hardware: hardware ?? snapshot.hardware,
                                newlyObservedProcesses: started, noLongerObservedProcesses: missing))
    }
}

/// In-memory only until the owner saves a marked incident. No claims about unseen history.
public struct IncidentBuffer: Sendable {
    public private(set) var samples: [SystemSample] = []
    public let maximumAge: TimeInterval
    public let maximumCount: Int
    public init(maximumAge: TimeInterval = 1800, maximumCount: Int = 400) {
        self.maximumAge = min(1800, max(1, maximumAge)); self.maximumCount = min(600, max(1, maximumCount))
    }
    public mutating func append(_ sample: SystemSample) {
        guard sample.timestamp.timeIntervalSince1970.isFinite else { return }
        if let last = samples.last, sample.timestamp <= last.timestamp { return }
        samples.append(sample)
        samples.removeAll { $0.timestamp < sample.timestamp.addingTimeInterval(-maximumAge) }
        if samples.count > maximumCount { samples.removeFirst(samples.count - maximumCount) }
    }
    public func preceding(_ marker: Date, seconds: TimeInterval = 120) -> [SystemSample] {
        samples.filter { $0.timestamp >= marker.addingTimeInterval(-seconds) && $0.timestamp <= marker }
    }
    public mutating func reset() { samples.removeAll() }
}
