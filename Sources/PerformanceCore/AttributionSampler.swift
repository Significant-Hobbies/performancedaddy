import CryptoKit
import Darwin
import Foundation
import NativeInspection

/// Bounded persisted attribution; no arguments, working directories or executable paths are saved.
public struct RecordedWorkload: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let association: String
    public let cpuCores: Double
    public let processCount: Int
    public init(id: String, name: String, association: String, cpuCores: Double, processCount: Int) {
        self.id = id; self.name = name; self.association = association
        self.cpuCores = cpuCores; self.processCount = processCount
    }

    public static func group(_ processes: [LiveProcess]) -> [Self] {
        let index = WorkloadIndex(processes)
        var groups: [String: (String, String, Double, Int)] = [:]
        var seen = Set<ProcessIdentity>()
        for process in processes where seen.insert(process.id).inserted {
            guard let cpu = process.cpu, cpu.isFinite, cpu >= 0 else { continue }
            let lineage = [process] + index.ancestors(of: process)
            let owner: LiveProcess
            let name: String
            let association: String
            if let agent = index.agentOwner(of: process) {
                owner = agent; name = "\(agent.agent ?? agent.name) · PID \(agent.id.pid)"
                association = "Agent and descendants, identified by executable metadata and parent links"
            } else if let app = lineage.first(where: { $0.appPath != nil }) {
                owner = app
                let title = URL(fileURLWithPath: app.appPath!).deletingPathExtension().lastPathComponent
                name = process.appPath == nil ? "\(title)-launched work" : "\(title) & helpers"
                association = process.appPath == nil ? "Launch ancestry; this does not identify the app's own code" : "App bundle path association; publisher identity not verified"
            } else {
                owner = process; name = "\(process.name) · PID \(process.id.pid)"
                association = "Individual process; app ownership unavailable"
            }
            // App paths only live in this transient grouping key, never in stored records.
            let key = owner.appPath != nil && owner.agent == nil && process.appPath != nil
                ? "app:\(owner.uid):\(owner.appPath!)"
                : "process:\(owner.id.pid):\(owner.id.started):\(name)"
            let existing = groups[key] ?? (name, association, 0, 0)
            groups[key] = (existing.0, existing.1, existing.2 + cpu / 100, existing.3 + 1)
        }
        return groups.map { key, value in
            // Bundle names + uid distinguish app families without persisting paths.
            let id = key.hasPrefix("app:") ? "app:" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() : key
            return Self(id: id, name: String(value.0.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(100)),
                        association: value.1, cpuCores: value.2, processCount: value.3)
        }.sorted { $0.cpuCores == $1.cpuCores ? $0.id < $1.id : $0.cpuCores > $1.cpuCores }
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}

struct AttributionSampler {
    private var counters: [ProcessIdentity: (UInt64, Double)] = [:]
    struct Reading {
        let processes: [ProcessObservation]
        let workloads: [RecordedWorkload]
        let observerCPU: Double?
    }
    mutating func read() -> Reading {
        let uptime = ProcessInfo.processInfo.systemUptime
        let capacity = max(1024, min(proc_listallpids(nil, 0) + 256, 65536))
        var pids = [Int32](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var inventory: [LiveProcess] = []
        var next: [ProcessIdentity: (UInt64, Double)] = [:]
        for pid in pids.prefix(max(0, min(Int(count), pids.count))) where pid > 0 {
            var raw = PDProcess()
            guard pd_process(pid, &raw) == 1 else { continue }
            let identity = ProcessIdentity(pid: pid, started: raw.started)
            let cpu: Double? = counters[identity].flatMap {
                let elapsed = uptime - $0.1
                guard elapsed >= 0.1, elapsed <= 6, raw.cpu >= $0.0 else { return nil }
                return Double(raw.cpu - $0.0) / 1_000_000_000 / elapsed * 100
            }
            next[identity] = (raw.cpu, uptime)
            inventory.append(LiveProcess(id: identity, parent: raw.parent, uid: raw.uid,
                name: Self.string(&raw.name), executable: Self.string(&raw.path), directory: "",
                cpu: cpu, memory: raw.memory, hasControllingTerminal: raw.has_terminal != 0))
        }
        counters = next
        let rows = inventory.filter { ($0.cpu ?? 0) >= 0.5 }.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(16).map {
            ProcessObservation(id: $0.id.pid, parentID: $0.parent, name: $0.name,
                               cpuCores: ($0.cpu ?? 0) / 100, residentBytes: $0.memory)
        }
        return Reading(processes: rows, workloads: Array(RecordedWorkload.group(inventory).prefix(32)),
                       observerCPU: inventory.first { $0.id.pid == getpid() }?.cpu.map { $0 / 100 })
    }
    private static func string<T>(_ value: inout T) -> String {
        withUnsafeBytes(of: &value) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
    }
}
