import Foundation
import Darwin

public struct StackObservation: Equatable, Sendable {
    public let frames: [String]
    public let weight: Double
}
public struct ImportedThread: Equatable, Sendable {
    public let name: String
    public let isMain: Bool
    public let unit: String
    public let stacks: [StackObservation]
    public var totalWeight: Double { stacks.reduce(0) { $0 + $1.weight } }
    public var interpretation: String {
        guard isMain else { return "Thread role not established; inspect its recorded stacks." }
        let waits = stacks.filter { stack in
            let leaf = stack.frames.last?.lowercased() ?? ""
            return ["unfair_lock", "mutex_lock", "semaphore_wait", "group_wait", "psynch", "pread", "kevent"].contains { leaf.contains($0) }
        }.reduce(0) { $0 + $1.weight }
        let idle = stacks.filter { stack in
            let text = stack.frames.joined(separator: " ").lowercased()
            return text.contains("cfrunloopservicemachport") && text.contains("mach_msg") && (text.contains("nextevent") || text.contains("nsapplication run"))
        }.reduce(0) { $0 + $1.weight }
        if totalWeight > 0, waits / totalWeight >= 0.5 { return "Main thread repeatedly sampled in a synchronization/I/O wait. The wait owner and its connection to your delay are unknown." }
        if totalWeight > 0, idle / totalWeight >= 0.5 { return "Main thread mostly sampled waiting for the next event. This is consistent with normal event-loop idling; it is not evidence of a hang." }
        return "Main-thread stacks were captured. Sampled locations alone do not establish whether it was running, blocked or causing a delay."
    }
}
public struct ImportedProfile: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let format: String
    public let unit: String
    public let threads: [ImportedThread]
    public let limitation: String
    public var recordedAtText: String? = nil
}
public enum ProfileImportError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum ProfileImporter {
    public static let maximumBytes = 8 * 1024 * 1024
    public static func read(_ url: URL) throws -> ImportedProfile {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProfileImportError.invalid("The selected report could not be opened.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes else {
            throw ProfileImportError.invalid("Choose a regular Sample Process text report or sampled speedscope JSON file smaller than 8 MiB.")
        }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try parse(data)
    }
    public static func parse(_ data: Data) throws -> ImportedProfile {
        guard !data.isEmpty, data.count <= maximumBytes else { throw ProfileImportError.invalid("The profile is empty or exceeds 8 MiB.") }
        guard let text = String(data: data, encoding: .utf8) else { throw ProfileImportError.invalid("This importer requires UTF-8 Sample Process text or sampled speedscope JSON.") }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return try speedscope(data) }
        return try appleSample(text)
    }
    private static func main(_ name: String) -> Bool { let name = name.lowercased(); return name.contains("main thread") || name.contains("com.apple.main-thread") }
    private static let limits = "This file is independent evidence; it is not attached to a live PID. Stack weights are sampled locations, not CPU percentages, continuous hang duration or measured input-response latency. Missing symbols and sampling gaps limit interpretation. Nothing is uploaded."
    private static func speedscope(_ data: Data) throws -> ImportedProfile {
        struct Frame: Decodable { let name: String? }
        struct Shared: Decodable { let frames: [Frame] }
        struct Profile: Decodable {
            let type: String; let name: String?; let unit: String
            let startValue: Double; let endValue: Double
            let samples: [[Int]]; let weights: [Double]
        }
        struct Input: Decodable { let shared: Shared; let profiles: [Profile] }
        guard let input = try? JSONDecoder().decode(Input.self, from: data),
              input.shared.frames.count <= 100000, input.profiles.count <= 128, !input.profiles.isEmpty else {
            throw ProfileImportError.invalid("Supported JSON is sampled speedscope format. Firefox/samply, Instruments and native Perfetto files require conversion; they are not silently approximated.")
        }
        let names = input.shared.frames.map { ForegroundEvidence.clean($0.name ?? "Symbol unavailable") }
        let profiles = input.profiles
        var threads: [ImportedThread] = []; var units = Set<String>(); var observations = 0
        for profile in profiles {
            let samples = profile.samples, weights = profile.weights
            let start = profile.startValue, end = profile.endValue, unit = profile.unit
            guard profile.type == "sampled", samples.count == weights.count,
                  start.isFinite, end.isFinite, end >= start,
                  ["none", "seconds", "milliseconds", "microseconds", "nanoseconds"].contains(unit) else {
                throw ProfileImportError.invalid("Each profile must contain valid sampled stacks and time/arbitrary weights. Allocation and evented profiles are not supported.")
            }
            observations += samples.count
            guard observations <= 200000 else { throw ProfileImportError.invalid("Too many stack observations.") }
            var stacks: [StackObservation] = []
            for (sample, weight) in zip(samples, weights) {
                guard weight.isFinite, weight >= 0, weight <= 1e15, sample.count <= 512,
                      sample.allSatisfy({ $0 >= 0 && $0 < names.count }) else { throw ProfileImportError.invalid("Invalid stack index, depth or weight.") }
                if weight > 0 { stacks.append(StackObservation(frames: sample.map { names[$0] }, weight: weight)) }
            }
            let name = ForegroundEvidence.clean(profile.name ?? "Thread role unavailable")
            threads.append(ImportedThread(name: name, isMain: main(name), unit: unit, stacks: stacks)); units.insert(unit)
        }
        return ImportedProfile(format: "Sampled speedscope", unit: units.sorted().joined(separator: ", "), threads: threads, limitation: limits)
    }
    private static func appleSample(_ text: String) throws -> ImportedProfile {
        guard text.contains("Call graph:"), text.contains("Thread_") else {
            throw ProfileImportError.invalid("No Apple Sample Process call graph found. Spindump, binary traces and arbitrary logs are not supported by this importer.")
        }
        struct Node { let depth: Int; let count: Double; let name: String; var children = 0.0 }
        let expression = try NSRegularExpression(pattern: "^([ +|:!]*)(([0-9]+)) +(.+)$")
        var threads: [ImportedThread] = []; var name: String?; var stack: [Node] = []; var leaves: [StackObservation] = []
        var inGraph = false; var lines = 0
        func pop() throws {
            guard let node = stack.last else { return }
            guard node.children <= node.count else { throw ProfileImportError.invalid("The call-tree counts are inconsistent.") }
            let residual = node.count - node.children
            if residual > 0 { leaves.append(StackObservation(frames: stack.map(\.name), weight: residual)) }
            stack.removeLast()
        }
        func finish() throws {
            while !stack.isEmpty { try pop() }
            if let name { threads.append(ImportedThread(name: name, isMain: main(name), unit: "observations", stacks: leaves)) }
            leaves.removeAll()
        }
        for line in text.components(separatedBy: .newlines) {
            lines += 1; guard lines <= 200000 else { throw ProfileImportError.invalid("Too many report lines.") }
            if line == "Call graph:" { inGraph = true; continue }
            guard inGraph else { continue }
            if line.hasPrefix("Total number in stack") || line.hasPrefix("Binary Images:") { break }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range),
                  let countRange = Range(match.range(at: 3), in: line),
                  let valueRange = Range(match.range(at: 4), in: line) else { continue }
            guard let count = Double(line[countRange]), count.isFinite, count > 0, count <= 1e15 else {
                throw ProfileImportError.invalid("The call-tree observation count is invalid.")
            }
            let value = String(line[valueRange])
            if value.hasPrefix("Thread_") {
                try finish(); name = ForegroundEvidence.clean(value); guard threads.count < 128 else { throw ProfileImportError.invalid("Too many threads.") }; continue
            }
            guard name != nil else { continue }
            let depth = match.range(at: 3).location
            while let node = stack.last, node.depth >= depth { try pop() }
            guard stack.count < 512 else { throw ProfileImportError.invalid("The call tree is too deep.") }
            if !stack.isEmpty { stack[stack.count - 1].children += count }
            let symbol = value.components(separatedBy: "  (in ").first ?? value
            stack.append(Node(depth: depth, count: count, name: ForegroundEvidence.clean(symbol)))
        }
        try finish()
        guard threads.contains(where: { !$0.stacks.isEmpty }) else { throw ProfileImportError.invalid("No readable stacks found.") }
        var profile = ImportedProfile(format: "Apple Sample Process", unit: "observations", threads: threads, limitation: limits)
        profile.recordedAtText = text.components(separatedBy: .newlines).first { $0.hasPrefix("Date/Time:") }.map { ForegroundEvidence.clean(String($0.dropFirst("Date/Time:".count)).trimmingCharacters(in: .whitespaces)) }
        return profile
    }
}

public enum IncidentTraceExport {
    public static func data(_ capture: DiagnosticCapture) throws -> Data {
        var events: [[String: Any]] = []
        func counter(_ name: String, _ value: Double?, _ date: Date) {
            guard let value, value.isFinite, date.timeIntervalSince1970.isFinite else { return }
            events.append(["name": name, "ph": "C", "pid": 1, "tid": 1,
                           "ts": date.timeIntervalSince1970 * 1e6, "args": ["value": value]])
        }
        let workloadIDs = Set(capture.samples.flatMap { $0.incident?.workloads.map(\.id) ?? [] }).sorted()
        let tracks = Dictionary(uniqueKeysWithValues: workloadIDs.enumerated().map { ($0.element, $0.offset + 10) })
        var named = Set<String>()
        for sample in capture.samples {
            counter("System CPU cores", sample.usedCPUCores, sample.timestamp)
            counter("Estimated memory headroom", sample.memoryHeadroomRatio, sample.timestamp)
            counter("Swap-out bytes/sec", sample.memory?.swapOutBytesPerSecond, sample.timestamp)
            counter("GPU device utilization percent", sample.incident?.hardware?.gpuUtilizationPercent, sample.timestamp)
            counter("CPU sensor maximum Celsius", sample.incident?.hardware?.cpuSensorMaximumCelsius, sample.timestamp)
            counter("Observer CPU cores", sample.samplerCPUCores, sample.timestamp)
            for fan in sample.incident?.hardware?.fans ?? [] { counter(fan.name + " RPM", fan.rpm, sample.timestamp) }
            for workload in sample.incident?.workloads ?? [] {
                guard let track = tracks[workload.id] else { continue }
                if named.insert(workload.id).inserted {
                    events.append(["name": "process_name", "ph": "M", "pid": track, "tid": 1, "args": ["name": workload.name + (workload.project.map { " · " + $0 } ?? "")]])
                }
                if let cpu = workload.cpuCores, cpu.isFinite, sample.timestamp.timeIntervalSince1970.isFinite {
                    events.append(["name": "CPU cores", "ph": "C", "pid": track, "tid": 1, "ts": sample.timestamp.timeIntervalSince1970 * 1e6, "args": ["value": cpu]])
                }
            }
        }
        if let marker = capture.marker {
            events.append(["name": marker.symptom, "ph": "i", "s": "g", "pid": 1, "tid": 1, "ts": marker.date.timeIntervalSince1970 * 1e6])
        }
        return try JSONSerialization.data(withJSONObject: ["traceEvents": events, "displayTimeUnit": "ms", "metadata": ["source": "PerformanceDaddy native observations", "clock": "Unix epoch microseconds", "limitations": "Sampled counters; no scheduler trace or measured input latency. Missing readings remain omitted."]], options: [.sortedKeys])
    }
}
