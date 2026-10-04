import Foundation

public enum ProcessUnderstanding {
    public static func catalogDescription(executable: String) -> String? {
        ProcessCatalog.match(executable: executable).map { "\($0.category): \($0.role) Source: \($0.source)." }
    }
    public static func duration(_ identity: ProcessIdentity, at date: Date) -> TimeInterval? {
        let start = Double(identity.started) / 1_000_000
        let now = date.timeIntervalSince1970
        guard identity.started > 0, now.isFinite, start <= now else { return nil }
        return now - start
    }

    /// Path association, not verified publisher identity. Outermost app owns nested helpers.
    public static func appPath(for executable: String) -> String? {
        guard executable.hasPrefix("/"), !executable.split(separator: "/").contains("..") else { return nil }
        let parts = executable.split(separator: "/")
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }), index + 1 < parts.count else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }

    public static func explanation(for process: LiveProcess) -> String {
        if let description = catalogDescription(executable: process.executable) {
            return "\(description) Catalog match by exact executable name in a system location; not verified publisher identity. Leave system services running unless investigating a specific problem."
        }
        if let path = appPath(for: process.executable) {
            return "Located inside \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent). It may be the app itself or one of its helpers. Quit the app normally before stopping individual helpers."
        }
        if process.executable.hasPrefix("/System/") || process.executable.hasPrefix("/usr/libexec/") || process.executable.hasPrefix("/usr/sbin/") {
            return "Located in a macOS service directory. Its specific purpose is not identified here; do not stop it solely because its name is unfamiliar."
        }
        if let agent = process.agent {
            return "Executable-name match for \(agent), a local coding agent. This is a classification hint, not verified publisher identity or conversation activity."
        }
        return "Ownership is not established. The executable, parent and project below are evidence to investigate, not proof that this process is unnecessary."
    }
}

/// Ephemeral journal. Only explicitly successful signals establish a watched stop.
/// Missing rows are not exit proof; a new matching executable is not restart proof.
public struct ProcessLifecycleJournal: Sendable {
    public struct Event: Codable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let executable: String
        public let uid: UInt32
        public let text: String

        public init(id: UUID = UUID(), date: Date, executable: String, uid: UInt32, text: String) {
            self.id = id
            self.date = date
            self.executable = executable
            self.uid = uid
            self.text = text
        }
    }
    private struct Watch: Sendable {
        let process: LiveProcess
        let date: Date
        var missingReported = false
        var exitConfirmed = false
        var seen: Set<ProcessIdentity>
    }
    public private(set) var events: [Event] = []
    private var watches: [Watch] = []
    public init(events: [Event] = [], at date: Date = Date()) {
        self.events = Self.validPersistedEvents(events, at: date)
    }
    public var pendingExitChecks: [ProcessIdentity] {
        watches.filter { !$0.exitConfirmed }.map { $0.process.id }
    }
    public mutating func confirmExit(_ identity: ProcessIdentity, presence: ProcessPresence, at date: Date) {
        guard presence == .gone, date.timeIntervalSince1970.isFinite else { return }
        prune(at: date)
        guard let index = watches.firstIndex(where: { $0.process.id == identity && !$0.exitConfirmed }) else { return }
        watches[index].exitConfirmed = true
        append(watches[index].process, date, "Exit confirmed for PID \(identity.pid): the original process identity is no longer present. This does not establish why it exited.")
    }
    public mutating func expire(at date: Date) { prune(at: date) }

    public mutating func record(_ process: LiveProcess, at date: Date, force: Bool, signalSent: Bool, observed: [LiveProcess],
                                request: String? = nil) {
        guard signalSent, !process.executable.isEmpty, date.timeIntervalSince1970.isFinite else { return }
        prune(at: date)
        watches.removeAll { $0.process.id == process.id }
        watches.append(Watch(process: process, date: date, seen: Set(observed.filter {
            $0.uid == process.uid && $0.executable == process.executable
        }.prefix(8_192).map(\.id))))
        if watches.count > 100 { watches.removeFirst(watches.count - 100) }
        append(process, date, "\(request ?? (force ? "Force-stop signal" : "Stop signal")) sent to PID \(process.id.pid); exit not yet confirmed.")
    }

    public mutating func observe(_ processes: [LiveProcess], at date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        prune(at: date)
        let ids = Set(processes.map(\.id))
        for index in watches.indices {
            let watch = watches[index]
            if !ids.contains(watch.process.id), !watch.missingReported, !watch.exitConfirmed {
                watches[index].missingReported = true
                append(watch.process, date, "PID \(watch.process.id.pid) no longer observed. Exit is not confirmed by a missing sample.")
            }
            let candidates = processes.filter {
                $0.uid == watch.process.uid && $0.executable == watch.process.executable &&
                $0.id != watch.process.id && !watch.seen.contains($0.id) &&
                Double($0.id.started) / 1_000_000 > watch.date.timeIntervalSince1970 &&
                ProcessUnderstanding.duration($0.id, at: date) != nil
            }
            for candidate in candidates {
                // Bound per-watch identities; once exhausted stop matching rather than repeat events.
                guard watches[index].seen.count < 8_192 else { break }
                watches[index].seen.insert(candidate.id)
                append(watch.process, date, "Matching executable observed as PID \(candidate.id.pid) after the stop request for PID \(watch.process.id.pid). \(candidates.count > 1 ? "Multiple candidates; association is ambiguous. " : "")Launch cause unknown; this does not prove an automatic restart.")
            }
        }
    }
    public func events(for process: LiveProcess) -> [Event] {
        events.filter { $0.uid == process.uid && $0.executable == process.executable }
    }
    private mutating func append(_ process: LiveProcess, _ date: Date, _ text: String) {
        events.append(Event(date: date, executable: process.executable, uid: process.uid, text: text))
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }
    private mutating func prune(at date: Date) {
        events.removeAll { date.timeIntervalSince($0.date) > 86_400 || $0.date > date }
        watches.removeAll { date.timeIntervalSince($0.date) > 86_400 || $0.date > date }
    }

    public static func validPersistedEvents(_ events: [Event], at date: Date) -> [Event] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        return Array(events.filter {
            let timestamp = $0.date.timeIntervalSince1970
            return timestamp.isFinite && $0.date <= date && date.timeIntervalSince($0.date) <= 86_400
                && $0.executable.hasPrefix("/") && $0.executable.utf8.count <= 4_096
                && !$0.executable.contains("\n") && !$0.executable.contains("\r")
                && !$0.text.isEmpty && $0.text.utf8.count <= 2_048
                && !$0.text.contains("\n") && !$0.text.contains("\r")
        }.suffix(500))
    }
}
