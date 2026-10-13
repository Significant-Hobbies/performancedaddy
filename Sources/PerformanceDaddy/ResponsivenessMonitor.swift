import AppKit
@preconcurrency import ApplicationServices
import PerformanceCore

/// One pending dispatch at most. The probe does not read global input or another app's UI contents.
final class MainQueueHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "PerformanceDaddy.responsiveness", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var pending = false
    private var startedAt = Date()
    private var count = 0
    private var peak: Double?
    private var eventCount = 0
    private var eventPeak: Double?

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.requestHeartbeat() }
        lock.withLock { self.timer = timer }
        timer.resume()
    }
    func stop() {
        let old = lock.withLock { () -> DispatchSourceTimer? in
            let old = timer; timer = nil; generation = UUID(); pending = false
            count = 0; peak = nil; eventCount = 0; eventPeak = nil; startedAt = Date()
            return old
        }
        old?.cancel()
    }
    func requestHeartbeat() {
        let token = lock.withLock { () -> UUID? in
            guard timer != nil, !pending else { return nil }
            pending = true; return generation
        }
        guard let token else { return }
        let enqueued = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            self?.complete(generation: token, delay: (ProcessInfo.processInfo.systemUptime - enqueued) * 1000)
        }
    }
    private func complete(generation token: UUID, delay: Double) {
        lock.withLock {
            guard generation == token else { return }
            pending = false
            guard delay.isFinite, (0...60_000).contains(delay) else { return }
            count += 1; peak = max(peak ?? 0, delay)
        }
    }
    func recordLocalEvent(timestamp: TimeInterval) {
        let delay = (ProcessInfo.processInfo.systemUptime - timestamp) * 1000
        guard timestamp.isFinite, timestamp > 0, delay.isFinite, (0...60_000).contains(delay) else { return }
        lock.withLock { eventCount += 1; eventPeak = max(eventPeak ?? 0, delay) }
    }
    func drain(appProbe: AppResponseProbe?) -> ResponsivenessEvidence {
        lock.withLock {
            let end = Date()
            let evidence = ResponsivenessEvidence(windowStartedAt: startedAt, windowEndedAt: end,
                heartbeatCount: count, heartbeatMaximumMilliseconds: peak, localEventCount: eventCount,
                localEventMaximumMilliseconds: eventPeak, appProbe: appProbe)
            startedAt = end; count = 0; peak = nil; eventCount = 0; eventPeak = nil
            return evidence
        }
    }
    deinit { timer?.cancel() }
}

struct AppProbeTarget: Sendable {
    let identity: ProcessIdentity
    let name: String
    let bundleID: String?
    let version: String?
}

/// Read-only request for the application's role; returned attribute contents are discarded.
actor AppResponseReader {
    private var cadence = AppProbeCadence()

    func sample(target: AppProbeTarget?, enabled: Bool) -> AppResponseProbe? {
        let now = ProcessInfo.processInfo.systemUptime
        guard cadence.take(at: now) else { return nil }
        func result(_ status: AppResponseProbe.Status, _ milliseconds: Double? = nil) -> AppResponseProbe {
            AppResponseProbe(date: Date(), app: target?.name ?? "Last-used app", bundleID: target?.bundleID,
                             version: target?.version, status: status, milliseconds: milliseconds)
        }
        guard enabled else { return result(.disabled) }
        guard AXIsProcessTrusted() else { return result(.permissionMissing) }
        guard let target, ProcessPresence.inspect(target.identity) == .observed else { return result(.targetChanged) }
        let element = AXUIElementCreateApplication(target.identity.pid)
        guard AXUIElementSetMessagingTimeout(element, 0.25) == .success else { return result(.unsupported) }
        var discarded: CFTypeRef?
        let start = ProcessInfo.processInfo.systemUptime
        let status = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &discarded)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        guard ProcessPresence.inspect(target.identity) == .observed else { return result(.targetChanged) }
        switch status {
        case .success: return result(.replied, elapsed)
        case .cannotComplete: return result(.didNotReply)
        case .apiDisabled: return result(.permissionMissing)
        default: return result(.unsupported)
        }
    }
}

@MainActor
enum AppProbePermission {
    static var available: Bool { AXIsProcessTrusted() }
    static func request() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
