import Darwin
import Foundation
import NativeInspection

public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let started: UInt64
    public init(pid: Int32, started: UInt64) { self.pid = pid; self.started = started }
}

public struct ListeningPort: Hashable, Sendable, Identifiable {
    public let port: UInt16
    public let transport: String
    public let address: String
    public let loopback: Bool
    public var id: String { "\(transport):\(address):\(port)" }
    public var endpoint: String { address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)" }
    public var scope: String { loopback ? "Localhost" : "Non-loopback bind" }
    public init(port: UInt16, transport: String, address: String, loopback: Bool) {
        self.port = port; self.transport = transport; self.address = address; self.loopback = loopback
    }
}

public struct LiveProcess: Identifiable, Sendable {
    public let id: ProcessIdentity
    public let parent: Int32
    public let uid: UInt32
    public let name: String
    public let executable: String
    public let directory: String
    public let hasControllingTerminal: Bool
    public let cpu: Double?
    public let memory: UInt64
    public let footprint: UInt64?
    public let diskReadBytes: UInt64?
    public let diskWrittenBytes: UInt64?
    public var ports: [ListeningPort]
    public var portsIncomplete: Bool
    // Immutable metadata: resolve once, not during every sort and ancestry walk.
    public let agent: String?
    public let catalog: ProcessCatalog.Entry?
    public let appPath: String?
    public init(id: ProcessIdentity, parent: Int32, uid: UInt32, name: String,
                executable: String, directory: String, cpu: Double?, memory: UInt64,
                hasControllingTerminal: Bool = false,
                ports: [ListeningPort] = [], portsIncomplete: Bool = false,
                footprint: UInt64? = nil, diskReadBytes: UInt64? = nil, diskWrittenBytes: UInt64? = nil) {
        self.id = id; self.parent = parent; self.uid = uid; self.name = name
        self.executable = executable; self.directory = directory; self.cpu = cpu
        self.hasControllingTerminal = hasControllingTerminal
        self.agent = AgentIdentity.label(executable: executable, processName: name)
        self.catalog = ProcessCatalog.match(executable: executable)
        self.appPath = ProcessUnderstanding.appPath(for: executable)
        self.memory = memory; self.ports = ports; self.portsIncomplete = portsIncomplete
        self.footprint = footprint; self.diskReadBytes = diskReadBytes; self.diskWrittenBytes = diskWrittenBytes
    }
    public var isUserProcess: Bool { uid == getuid() }
    public var stopRestriction: String? {
        if id.pid <= 1 || !isUserProcess { return "System or another user's process" }
        if id.pid == getpid() { return "PerformanceDaddy is monitoring this process" }
        if executable.isEmpty || executable.hasPrefix("/System/") || executable.hasPrefix("/usr/libexec/") || executable.hasPrefix("/usr/sbin/") {
            return "Protected system process"
        }
        return nil
    }
}

/// Identification is metadata evidence, not authentication or conversation state.
/// Generic interpreters, desktop shells and substring matches are deliberately
/// excluded. Wrapped tools may be unavailable without inspecting private argv.
public enum AgentIdentity {
    public static let supportedNames = ["Codex", "Claude", "Devin", "Hermes", "Aider", "Gemini CLI", "OpenCode", "Cursor CLI"]
    private static let executables = [
        "codex": "Codex", "claude": "Claude", "devin": "Devin",
        "hermes": "Hermes", "aider": "Aider", "gemini": "Gemini CLI",
        "opencode": "OpenCode", "cursor-agent": "Cursor CLI",
    ]
    public static func label(executable: String, processName: String) -> String? {
        let basename = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if let known = executables[basename] ?? executables[processName.lowercased()] { return known }
        // Claude's native installer runs the versioned target of ~/.local/bin/claude.
        let versions = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions").path + "/"
        let parts = basename.split(separator: ".", omittingEmptySubsequences: false)
        if executable.hasPrefix(versions), parts.count == 3,
           parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return "Claude"
        }
        return nil
    }
}

public struct LiveSnapshot: Sendable {
    public let date: Date
    public let processes: [LiveProcess]
    public let system: SystemSample
    public let pressure: String
    public let compressed: UInt64?
    public let unavailableProcesses: Int
    public let portsDate: Date
    public let scanSeconds: Double
}

public enum WorkloadGrouping {
    /// Select the nearest actual agent ancestor; siblings in a shared terminal stay separate.
    public static func agentOwner(of process: LiveProcess, in processes: [LiveProcess]) -> LiveProcess? {
        WorkloadIndex(processes).agentOwner(of: process)
    }
    public static func descendants(of process: LiveProcess, in processes: [LiveProcess]) -> [LiveProcess] {
        WorkloadIndex(processes).descendants(of: process)
    }
}

/// One immutable index per snapshot. Start times reject parent-PID reuse;
/// visited identities make corrupt/cyclic metadata safe to inspect.
public struct WorkloadIndex: Sendable {
    private let processes: [LiveProcess]
    private let byPID: [Int32: LiveProcess]
    private let children: [Int32: [LiveProcess]]

    public init(_ processes: [LiveProcess]) {
        let byPID = Dictionary(processes.map { ($0.id.pid, $0) }, uniquingKeysWith: { a, _ in a })
        self.byPID = byPID
        self.processes = processes
        self.children = Dictionary(grouping: processes.filter { child in
            guard let parent = byPID[child.parent] else { return false }
            return parent.id != child.id && parent.id.started <= child.id.started
        }, by: \.parent)
    }

    private func parent(of child: LiveProcess) -> LiveProcess? {
        guard let parent = byPID[child.parent], parent.id != child.id,
              parent.id.started <= child.id.started else { return nil }
        return parent
    }

    /// Nearest first; a reused PID or a cycle must not invent app ownership.
    public func ancestors(of process: LiveProcess) -> [LiveProcess] {
        guard byPID[process.id.pid]?.id == process.id else { return [] }
        var result: [LiveProcess] = []
        var seen: Set<ProcessIdentity> = [process.id]
        var current = process
        while result.count < 256, let next = parent(of: current), seen.insert(next.id).inserted {
            result.append(next)
            current = next
        }
        return result
    }

    public func descendants(of process: LiveProcess) -> [LiveProcess] {
        guard let root = byPID[process.id.pid], root.id == process.id else { return [] }
        var result = [root]
        var visited: Set<ProcessIdentity> = [root.id]
        var cursor = 0
        while cursor < result.count {
            for child in children[result[cursor].id.pid] ?? [] where visited.insert(child.id).inserted {
                result.append(child)
            }
            cursor += 1
        }
        return result
    }

    public func agentOwner(of process: LiveProcess) -> LiveProcess? {
        guard byPID[process.id.pid]?.id == process.id else { return nil }
        var current: LiveProcess? = process
        var visited: Set<ProcessIdentity> = []
        while let item = current, visited.insert(item.id).inserted {
            if item.agent != nil { return item }
            current = parent(of: item)
        }
        return nil
    }

    /// Same-provider wrappers collapse; sibling launches and different providers
    /// stay independently inspectable. This is workload grouping, not chat counting.
    public var agentRoots: [LiveProcess] {
        processes.filter { process in
            guard let provider = process.agent else { return false }
            var current = parent(of: process)
            var visited: Set<ProcessIdentity> = [process.id]
            var matching = [process.id.pid]
            while let item = current {
                guard visited.insert(item.id).inserted else { return process.id.pid == matching.min() }
                if let agent = item.agent {
                    if agent != provider { break }
                    // A terminal client below a detached shared host is its
                    // own session, not part of the host's resource tile.
                    if item.hasControllingTerminal != process.hasControllingTerminal { break }
                    matching.append(item.id.pid)
                }
                current = parent(of: item)
            }
            return matching.count == 1
        }
    }
}

public actor WorkloadSampler {
    static let portRefreshInterval: TimeInterval = 30
    private let systemSampler = LiveSystemSampler()
    private var counters: [ProcessIdentity: (UInt64, Double)] = [:]
    private var sockets: [ProcessIdentity: ([ListeningPort], Bool)] = [:]
    private var portsDate = Date.distantPast
    public init() {}

    public func resetMeasurementWindow() async {
        counters.removeAll()
        await systemSampler.resetMeasurementWindow()
    }

    public func sample(includePorts: Bool = true) async -> LiveSnapshot {
        let began = ProcessInfo.processInfo.systemUptime
        let now = Date()
        let system = await systemSampler.sample(includeProcesses: false)
        let requested = max(1024, min(proc_listallpids(nil, 0) + 256, 65536))
        var pids = [Int32](repeating: 0, count: Int(requested))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var processes: [LiveProcess] = []
        var next: [ProcessIdentity: (UInt64, Double)] = [:]
        var missing = count <= 0 || count >= requested ? 1 : 0
        if !includePorts {
            sockets.removeAll()
            portsDate = .distantPast
        }
        let scanPorts = includePorts && now.timeIntervalSince(portsDate) >= Self.portRefreshInterval
        // Reuse one output buffer throughout the census instead of allocating
        // 512 port slots for each PID, including processes with no sockets.
        var portBuffer = scanPorts ? [PDPort](repeating: PDPort(), count: 512) : []
        for pid in pids.prefix(max(0, min(Int(count), pids.count))) where pid > 0 {
            var raw = PDProcess()
            guard pd_process(pid, &raw) == 1 else { missing += 1; continue }
            let identity = ProcessIdentity(pid: pid, started: raw.started)
            let previous = counters[identity]
            let cpu: Double? = previous.flatMap {
                guard raw.cpu >= $0.0, began > $0.1 else { return nil }
                return Double(raw.cpu - $0.0) / 1_000_000_000 / (began - $0.1) * 100
            }
            next[identity] = (raw.cpu, began)
            if scanPorts {
                var incomplete: Int32 = 0
                let portCount = portBuffer.withUnsafeMutableBufferPointer {
                    pd_ports(pid, $0.baseAddress, Int32($0.count), &incomplete)
                }
                let values = portBuffer.prefix(Int(portCount)).map { value in
                    var value = value
                    return ListeningPort(port: value.port, transport: value.protocol == IPPROTO_TCP ? "TCP" : "UDP",
                                         address: Self.string(&value.address), loopback: value.loopback != 0)
                }
                sockets[identity] = (Array(Set(values)).sorted { $0.id < $1.id }, incomplete != 0)
            }
            let name = Self.string(&raw.name)
            processes.append(LiveProcess(id: identity, parent: raw.parent, uid: raw.uid,
                                         name: name.isEmpty ? "Process \(pid)" : name,
                                         executable: Self.string(&raw.path), directory: Self.string(&raw.cwd),
                                         cpu: cpu, memory: raw.memory,
                                         hasControllingTerminal: raw.has_terminal != 0,
                                         ports: sockets[identity]?.0 ?? [],
                                         portsIncomplete: sockets[identity]?.1 ?? true,
                                         footprint: raw.resource_available != 0 ? raw.footprint : nil,
                                         diskReadBytes: raw.resource_available != 0 ? raw.read_bytes : nil,
                                         diskWrittenBytes: raw.resource_available != 0 ? raw.written_bytes : nil))
        }
        counters = next
        sockets = sockets.filter { next[$0.key] != nil }
        if scanPorts { portsDate = now }
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure = result != 0 ? "Unavailable" : level == 1 ? "Normal" : level == 2 ? "Warning" : level == 4 ? "Critical" : "Unknown"
        return LiveSnapshot(date: now, processes: processes, system: system, pressure: pressure,
                            compressed: system.memory?.compressedBytes,
                            unavailableProcesses: missing, portsDate: portsDate,
                            scanSeconds: ProcessInfo.processInfo.systemUptime - began)
    }

    private static func string<T>(_ value: inout T) -> String {
        withUnsafeBytes(of: &value) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

public struct StopResult: Sendable {
    public let process: LiveProcess
    public let message: String
    public let signalSent: Bool
    public let signalDate: Date?
    public init(process: LiveProcess, message: String, signalSent: Bool = false, signalDate: Date? = nil) {
        self.process = process; self.message = message; self.signalSent = signalSent; self.signalDate = signalDate
    }
}

public enum ProcessControl {
    /// The immutable reviewed list is the entire scope; never use process-group or wildcard signals.
    public static func stop(_ targets: [LiveProcess], force: Bool) -> [StopResult] {
        targets.map { target in
            if let reason = target.stopRestriction { return StopResult(process: target, message: "Skipped: \(reason)") }
            let date = Date()
            let code = pd_signal(target.id.pid, target.id.started, target.uid, force ? 1 : 0)
            let message: String
            switch code {
            case 0: message = force ? "Force-stop sent; checking exit" : "Stop requested; checking exit"
            case ESRCH: message = "Already exited"
            case ESTALE: message = "Skipped: process identity changed"
            default: message = "Could not stop: \(String(cString: strerror(code)))"
            }
            return StopResult(process: target, message: message, signalSent: code == 0, signalDate: code == 0 ? date : nil)
        }
    }
}
