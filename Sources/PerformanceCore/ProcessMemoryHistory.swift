import Foundation

public struct ProcessMemoryTrend: Sendable {
    public let first: UInt64
    public let latest: UInt64
    public let peak: UInt64
    public let seconds: Double
    public let samples: Int
    public var delta: Int64 { Int64(clamping: latest) - Int64(clamping: first) }
    public var growing: Bool {
        samples >= 3 && seconds >= 60 && latest > first && latest - first >= 256 * 1_024 * 1_024 && Double(latest) >= Double(first) * 1.25
    }
}

/// At most 512 processes × 150 samples, in memory only. Identity includes start
/// time; missing processes and gaps break continuity rather than inventing a trend.
public struct ProcessMemoryHistory: Sendable {
    private struct Point: Sendable { let time: Double; let bytes: UInt64 }
    private var history: [ProcessIdentity: [Point]] = [:]
    public init() {}
    public mutating func reset() { history.removeAll(keepingCapacity: true) }
    public mutating func observe(_ processes: [LiveProcess], at time: Double, maximumGap: Double = 30) {
        guard time.isFinite else { reset(); return }
        let tracked = processes.sorted {
            if $0.memory == $1.memory { return $0.id.pid < $1.id.pid }
            return $0.memory > $1.memory
        }.prefix(512)
        let identities = Set(tracked.map(\.id))
        history = history.filter { identities.contains($0.key) }
        for process in tracked {
            var points = history[process.id] ?? []
            if let previous = points.last, time <= previous.time || time - previous.time > maximumGap { points.removeAll(keepingCapacity: true) }
            points.removeAll { time - $0.time > 300 }
            points.append(Point(time: time, bytes: process.memory))
            if points.count > 150 { points.removeFirst(points.count - 150) }
            history[process.id] = points
        }
    }
    public func trend(for identity: ProcessIdentity) -> ProcessMemoryTrend? {
        guard let points = history[identity], points.count >= 2,
              let first = points.first, let latest = points.last else { return nil }
        return ProcessMemoryTrend(first: first.bytes, latest: latest.bytes,
            peak: points.map(\.bytes).max() ?? latest.bytes, seconds: latest.time - first.time, samples: points.count)
    }
}
