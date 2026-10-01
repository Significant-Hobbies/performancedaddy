import AppKit
import Combine
import PerformanceCore
import UniformTypeIdentifiers

enum LivePage: String, CaseIterable, Identifiable {
    case workloads = "Processes", ports = "Ports", agents = "Agent sessions", memory = "Memory"
    var id: Self { self }
    var icon: String {
        switch self {
        case .workloads: "list.bullet.indent"
        case .ports: "network"
        case .agents: "terminal"
        case .memory: "memorychip"
        }
    }
    var subtitle: String {
        switch self {
        case .workloads: "See what is running. Follow its children, inspect its footprint, or stop it."
        case .ports: "Find a local listener and the process keeping its port occupied."
        case .agents: "Local coding-agent families, their projects and resource use."
        case .memory: "Watch memory pressure, RAM headroom and the largest resident processes."
        }
    }
}

@MainActor
final class LiveViewModel: ObservableObject {
    static let minimumRefreshInterval: Double = 10
    static let maximumRefreshInterval: Double = 15

    enum ProcessGrouping: String, CaseIterable, Identifiable {
        case none = "Off", kind = "Kind", app = "App", category = "Category"
        var id: Self { self }
    }

    struct ProcessGroup: Identifiable {
        let title: String
        let rows: [LiveProcess]
        var id: String { title }
    }

    enum ToolbarMetric: String, CaseIterable, Identifiable {
        case ram, pressure, swap, sockets
        var id: Self { self }
    }

    static func refreshInterval(after scanSeconds: Double?) -> Double {
        guard let scanSeconds, scanSeconds.isFinite, scanSeconds >= 0 else {
            return minimumRefreshInterval
        }
        return max(minimumRefreshInterval, min(maximumRefreshInterval, scanSeconds * 20))
    }

    struct MemoryPoint: Identifiable { let id = UUID(); let date: Date; let used: Double }
    struct Review: Identifiable { let id = UUID(); let targets: [LiveProcess] }
    @Published var snapshot: LiveSnapshot? {
        didSet { index = WorkloadIndex(snapshot?.processes ?? []); rowCache.removeAll(); agentRows = nil; cachedRoots = nil }
    }
    @Published var search = "" { didSet { rowCache.removeAll() } }
    @Published var sortOrder = [KeyPathComparator(\LiveProcess.sortCPU, order: .reverse)] { didSet { rowCache.removeAll() } }
    @Published var selection: Set<ProcessIdentity> = []
    @Published var paused = false { didSet { if paused != oldValue { needsNewMeasurementWindow = true } } }
    @Published var includeSystem = false { didSet { rowCache.removeAll() } }
    @Published var grouping: ProcessGrouping = .none
    @Published var memoryHistory: [MemoryPoint] = []
    @Published var review: Review?
    @Published var outcomes: [StopResult] = []
    @Published var performingAction = false
    @Published var refreshing = false
    @Published var exportNotice: String?
    @Published private(set) var agentSignals: [ProcessIdentity: AgentWallSignal] = [:]
    @Published private(set) var sharedCodexSignals: [String: AgentWallSignal] = [:]
    @Published private(set) var codexSessionLinks: [ProcessIdentity: String] = [:]
    @Published private(set) var absentAgentProcesses: Set<ProcessIdentity> = [] {
        didSet { rowCache.removeValue(forKey: .agents) }
    }
    private var lastAgentActivities: [ProcessIdentity: AgentWallActivity] = [:]
    private let sampler = WorkloadSampler()
    private var task: Task<Void, Never>?
    private var agentPresenceTask: Task<Void, Never>?
    private var index = WorkloadIndex([])
    private var rowCache: [LivePage: [LiveProcess]] = [:]
    private var agentRows: [LiveProcess]?
    private var cachedRoots: [LiveProcess]?
    private var agentRoots: [LiveProcess] {
        if let cachedRoots { return cachedRoots }
        let roots = index.agentRoots
        cachedRoots = roots
        return roots
    }
    private static func sessionFamily(of root: LiveProcess, index: WorkloadIndex) -> [LiveProcess] {
        index.descendants(of: root).filter { member in
            guard root.agent == "Codex", !root.hasControllingTerminal else { return true }
            // Terminal Codex clients below a shared host are separate tiles.
            return !([member] + index.ancestors(of: member)).contains {
                $0.agent == "Codex" && $0.hasControllingTerminal
            }
        }
    }
    private var needsNewMeasurementWindow = false
    private var processHistory = ProcessMemoryHistory()
    private let historyOrigin = ContinuousClock.now
    private(set) var lifecycle = ProcessLifecycleJournal()
    private let lifecycleStore: LifecycleHistoryStore
    private var lifecycleSaveTask: Task<Void, Never>?
    private var lifecycleLoaded = false
    private var confirmedExits: Set<ProcessIdentity> = []
    private var wakeObserver: NSObjectProtocol?
    private var agentSignalObserver: NSObjectProtocol?

    init(lifecycleStore: LifecycleHistoryStore = LifecycleHistoryStore()) {
        self.lifecycleStore = lifecycleStore
    }

    func start() {
        guard task == nil else { return }
        agentPresenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkAgentPresence()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        if agentSignalObserver == nil {
            agentSignalObserver = DistributedNotificationCenter.default().addObserver(
                forName: AgentWallSignal.notification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let signal = AgentWallSignal(userInfo: notification.userInfo) else { return }
                Task { @MainActor in self?.recordAgentSignal(signal) }
            }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemWake() }
            }
        }
        task = Task { [weak self] in
            await self?.restoreLifecycle()
            while !Task.isCancelled {
                guard let self else { return }
                let previousEventCount = lifecycle.events.count
                lifecycle.expire(at: Date())
                if lifecycle.events.count != previousEventCount {
                    objectWillChange.send()
                    persistLifecycle()
                }
                if !paused && review == nil && !performingAction { await refresh() }
                let interval = Self.refreshInterval(after: snapshot?.scanSeconds)
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    func recordAgentSignal(_ signal: AgentWallSignal) {
        if signal.provider == "Codex", let key = signal.sessionKey,
           let source = snapshot?.processes.first(where: { $0.id == signal.process }),
           source.agent == "Codex", !source.hasControllingTerminal {
            var sessionSignal = signal
            if let previous = sharedCodexSignals[key] {
                guard signal.observedAt >= previous.observedAt else { return }
                sessionSignal = signal.carryingForward(from: previous)
            }
            sharedCodexSignals[key] = sessionSignal
        }
        var updated = signal
        if let previous = agentSignals[signal.process] {
            guard signal.observedAt >= previous.observedAt else { return }
            updated = signal.carryingForward(from: previous)
        }
        agentSignals[signal.process] = updated
        rowCache.removeValue(forKey: .agents)
    }

    func linkCodexSession(_ sessionID: String, to process: ProcessIdentity) -> String? {
        let normalized = sessionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalized) != nil,
              let key = AgentSessionKey.make(normalized) else {
            return "Enter the full session ID shown by this Codex terminal."
        }
        guard snapshot?.processes.contains(where: {
            $0.id == process && $0.agent == "Codex" && $0.hasControllingTerminal
        }) == true else { return "This Codex terminal is no longer running." }
        let live = Set(snapshot?.processes.map(\.id) ?? [])
        codexSessionLinks = codexSessionLinks.filter { live.contains($0.key) }
        guard !codexSessionLinks.contains(where: { $0.key != process && $0.value == key }) else {
            return "This session is already linked to another terminal."
        }
        codexSessionLinks[process] = key
        return nil
    }

    func unlinkCodexSession(from process: ProcessIdentity) {
        codexSessionLinks.removeValue(forKey: process)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        if needsNewMeasurementWindow {
            needsNewMeasurementWindow = false
            processHistory.reset()
            await sampler.resetMeasurementWindow()
        }
        let result = await sampler.sample()
        let previousEventCount = lifecycle.events.count
        lifecycle.observe(result.processes, at: result.date)
        let checks = Set(lifecycle.pendingExitChecks + outcomes.filter(\.signalSent).map { $0.process.id }).subtracting(confirmedExits)
        let gone = await Task.detached(priority: .utility) {
            checks.filter { ProcessPresence.inspect($0) == .gone }
        }.value
        let checkedAt = Date()
        for identity in gone { lifecycle.confirmExit(identity, presence: .gone, at: checkedAt) }
        confirmedExits.formUnion(gone)
        confirmedExits.formIntersection(Set(lifecycle.pendingExitChecks + outcomes.map { $0.process.id }))
        let elapsed = historyOrigin.duration(to: .now).components
        processHistory.observe(result.processes, at: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        snapshot = result
        let liveIdentities = Set(result.processes.map(\.id))
        agentSignals = agentSignals.filter { liveIdentities.contains($0.key) }
        sharedCodexSignals = sharedCodexSignals.filter {
            liveIdentities.contains($0.value.process) &&
                result.date.timeIntervalSince($0.value.observedAt) < 86_400
        }
        codexSessionLinks = codexSessionLinks.filter { liveIdentities.contains($0.key) }
        absentAgentProcesses.formIntersection(liveIdentities)
        selection.formIntersection(Set(result.processes.map(\.id)))
        if let headroom = result.system.memoryHeadroomRatio, headroom.isFinite, (0...1).contains(headroom) {
            memoryHistory.append(MemoryPoint(date: result.date, used: 1 - headroom))
            memoryHistory.removeAll { $0.date < result.date.addingTimeInterval(-300) }
        }
        refreshing = false
        if lifecycle.events.count != previousEventCount { persistLifecycle() }
    }

    func rows(for page: LivePage) -> [LiveProcess] {
        if let cached = rowCache[page] { return cached }
        let all = snapshot?.processes ?? []
        if page == .agents && agentRows == nil {
            agentRows = agentRoots.map { root in
            let family = Self.sessionFamily(of: root, index: index)
            return LiveProcess(id: root.id, parent: root.parent, uid: root.uid, name: root.name,
                               executable: root.executable, directory: root.directory,
                               cpu: family.contains(where: { $0.cpu != nil }) ? family.reduce(0) { $0 + ($1.cpu ?? 0) } : nil,
                               memory: family.reduce(0) { total, process in
                                   let sum = total.addingReportingOverflow(process.memory)
                                   return sum.overflow ? UInt64.max : sum.partialValue
                               }, hasControllingTerminal: root.hasControllingTerminal,
                               ports: Array(Set(family.flatMap(\.ports))).sorted { $0.id < $1.id },
                               portsIncomplete: family.contains(where: \.portsIncomplete))
            }
        }
        let candidates = page == .agents ? (agentRows ?? []).filter(isObservedAgentSession) : all
        let result = candidates.filter { process in
            guard includeSystem || process.isUserProcess else { return false }
            if page == .ports && process.ports.isEmpty { return false }
            if page == .agents && process.agent == nil { return false }
            if !search.isEmpty {
                let haystack = "\(process.sortName) \(process.name) \(process.id.pid) \(process.directory) \(process.appPath ?? "") \(ancestorApp(of: process)?.appPath ?? "") \(process.catalog?.category ?? "") \(process.catalog?.role ?? "") \(process.ports.map(\.endpoint).joined(separator: " "))"
                if !haystack.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }.sorted(using: sortOrder + [KeyPathComparator(\LiveProcess.id.pid)])
        rowCache[page] = result
        return result
    }

    /// Presentation-only partition of the filtered rows; group evidence is a hint, not verified ownership.
    func groupedRows(for page: LivePage) -> [ProcessGroup] {
        let rows = rows(for: page)
        switch grouping {
        case .none:
            return [ProcessGroup(title: "", rows: rows)]
        case .kind:
            var buckets: [String: [LiveProcess]] = [:]
            for row in rows { buckets[kindTitle(of: row), default: []].append(row) }
            return Self.kindOrder.compactMap { title in
                buckets[title].map { ProcessGroup(title: title, rows: $0) }
            }
        case .app, .category:
            var order: [String] = []
            var buckets: [String: [LiveProcess]] = [:]
            for row in rows {
                let title = grouping == .app ? appTitle(of: row) : categoryTitle(of: row)
                if buckets[title] == nil { order.append(title) }
                buckets[title, default: []].append(row)
            }
            return order.map { ProcessGroup(title: $0, rows: buckets[$0] ?? []) }
        }
    }

    private static let kindOrder = ["Agents", "Apps", "System services", "Other"]

    private func kindTitle(of process: LiveProcess) -> String {
        if process.agent != nil { return "Agents" }
        if process.appPath != nil || ancestorApp(of: process) != nil { return "Apps" }
        if process.catalog != nil || !process.isUserProcess ||
            ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains(where: { process.executable.hasPrefix($0) }) {
            return "System services"
        }
        return "Other"
    }

    private func appTitle(of process: LiveProcess) -> String {
        guard let path = process.appPath ?? ancestorApp(of: process)?.appPath else { return "No app context" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func categoryTitle(of process: LiveProcess) -> String {
        if let category = process.catalog?.category { return category }
        if process.agent != nil { return "Agent tools" }
        if process.appPath != nil || ancestorApp(of: process) != nil { return "Applications" }
        return "Other processes"
    }

    /// Highest observed contributors across the whole snapshot, not just the filtered rows.
    func topContributors(for metric: ToolbarMetric, limit: Int = 8) -> [LiveProcess] {
        let processes = snapshot?.processes ?? []
        switch metric {
        case .ram, .pressure, .swap:
            return processes
                .sorted { $0.memory == $1.memory ? $0.id.pid < $1.id.pid : $0.memory > $1.memory }
                .prefix(limit).map { $0 }
        case .sockets:
            return processes.filter { !$0.ports.isEmpty }
                .sorted { $0.ports.count == $1.ports.count ? $0.id.pid < $1.id.pid : $0.ports.count > $1.ports.count }
                .prefix(limit).map { $0 }
        }
    }

    func family(of process: LiveProcess) -> [LiveProcess] { index.descendants(of: process) }
    func ancestorApp(of process: LiveProcess) -> LiveProcess? {
        index.ancestors(of: process).first { $0.appPath != nil }
    }
    func processSubtitle(_ process: LiveProcess) -> String {
        if let catalog = process.catalog { return "\(catalog.category) · \(process.id.pid)" }
        if let path = process.appPath { return "\(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) · \(process.id.pid)" }
        return process.directory.isEmpty || process.directory == "/" ? "PID \(process.id.pid)" : "\(URL(fileURLWithPath: process.directory).lastPathComponent) · \(process.id.pid)"
    }
    func memoryTrend(for process: LiveProcess) -> ProcessMemoryTrend? { processHistory.trend(for: process.id) }
    func observedProcess(_ process: LiveProcess) -> LiveProcess? { snapshot?.processes.first { $0.id == process.id } }

    var selected: LiveProcess? { snapshot?.processes.first { selection.contains($0.id) } }
    var portCount: Int { snapshot?.processes.reduce(0) { $0 + $1.ports.count } ?? 0 }
    var agentCount: Int { agentRoots.filter { $0.isUserProcess && isObservedAgentSession($0) }.count }
    private func isObservedAgentSession(_ root: LiveProcess) -> Bool {
        guard !absentAgentProcesses.contains(root.id) else { return false }
        // A different provider in the ancestor chain owns this nested agent
        // workload. A PTY (including its own foreground group) does not make
        // an embedded tool an additional top-level user session. Idle roots
        // remain sessions; same-provider shared Codex clients stay separate.
        guard !index.ancestors(of: root).contains(where: {
            $0.agent != nil && $0.agent != root.agent
        }) else { return false }
        let direct = Self.directAgentSignal(for: root, index: index, signals: agentSignals)
        let signal = direct ?? codexSessionLinks[root.id].flatMap { sharedCodexSignals[$0] }
        // SessionEnd closes a session; Stop merely completes a turn in an open one.
        guard signal?.event != "SessionEnd" else { return false }
        // A shared Codex app server can report activity for several sessions.
        // It is not an additional agent session or battery mark.
        if root.agent == "Codex" && !root.hasControllingTerminal { return false }
        return root.hasControllingTerminal || agentSignals[root.id]?.provider == root.agent ||
            Self.sessionFamily(of: root, index: index).contains { member in
                agentSignals[member.id]?.provider == root.agent
        }
    }
    struct AgentWallTile: Identifiable {
        let process: LiveProcess
        let activity: AgentWallActivity
        let workspace: String?
        let host: String?
        let runningFor: String?
        let taskLabel: String?
        let taskObservedAt: Date?
        let lastEvent: String?
        let lastEventAt: Date?
        let sharedHostHookSeen: Bool
        let allowsSessionLink: Bool
        let isSessionLinked: Bool
        var id: ProcessIdentity { process.id }
        var displayName: String { process.agent ?? process.name }
        var evidenceSummary: String {
            if let lastEvent {
                if activity == .unavailable {
                    return lastEvent == "SessionStart" ? "Session start observed; awaiting work event" :
                        "Last work event expired; awaiting a new hook"
                }
                return "Last observed hook: \(lastEvent)"
            }
            if process.agent == "Codex" && process.hasControllingTerminal {
                if isSessionLinked { return "Linked; waiting for this session's next hook" }
                return sharedHostHookSeen ? "Shared Codex server; link this session" :
                    "No hook linked to this terminal"
            }
            return "No hook from this session since app opened"
        }
    }

    static func directAgentSignal(for root: LiveProcess, index: WorkloadIndex,
                                  signals: [ProcessIdentity: AgentWallSignal]) -> AgentWallSignal? {
        ([root] + sessionFamily(of: root, index: index)).compactMap { signals[$0.id] }
            .filter { $0.provider == root.agent }
            .max { $0.observedAt < $1.observedAt }
    }

    var agentWallTiles: [AgentWallTile] {
        _ = rows(for: .agents) // Populate the unfiltered family summaries.
        let all = snapshot?.processes ?? []
        let liveByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sharedCodexHookSeen = agentSignals.values.contains { signal in
            guard signal.provider == "Codex", (0...300).contains(Date().timeIntervalSince(signal.observedAt)),
                  let source = liveByID[signal.process] else { return false }
            return source.agent == "Codex" && !source.hasControllingTerminal
        }
        return (agentRows ?? []).filter { $0.isUserProcess && !absentAgentProcesses.contains($0.id) }.compactMap { root in
            let rawRoot = all.first(where: { $0.id == root.id }) ?? root
            let directSignal = Self.directAgentSignal(for: rawRoot, index: index, signals: agentSignals)
            let linkedKey = codexSessionLinks[rawRoot.id]
            let signal = directSignal ?? linkedKey.flatMap { sharedCodexSignals[$0] }
            // An uninstrumented, detached host is a process, not evidence of
            // a visible agent session. Keep it in the process list, off the wall.
            guard isObservedAgentSession(rawRoot) else { return nil }
            let hostProcess = index.ancestors(of: rawRoot).first { $0.agent == nil && $0.appPath != nil }
                ?? index.ancestors(of: rawRoot).first { $0.agent == nil && $0.name != "launchd" }
            let host = hostProcess.map { process in
                process.appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? process.name
            }
            let directory = signal?.workspace ?? (root.directory.isEmpty || root.directory == "/"
                ? nil : URL(fileURLWithPath: root.directory).lastPathComponent)
            let runningFor = ProcessUnderstanding.duration(root.id, at: snapshot?.date ?? Date()).flatMap { duration -> String? in
                guard duration.isFinite, duration >= 0, duration < Double(Int.max) else { return nil }
                let seconds = Int(duration)
                if seconds >= 86_400 { return "\(seconds / 86_400)d \(seconds % 86_400 / 3_600)h" }
                if seconds >= 3_600 { return "\(seconds / 3_600)h \(seconds % 3_600 / 60)m" }
                return "\(seconds / 60)m"
            }
            return AgentWallTile(process: root, activity: AgentWallActivity.resolve(
                event: signal?.event, age: Date().timeIntervalSince(signal?.observedAt ?? .distantPast)),
                workspace: directory, host: host, runningFor: runningFor,
                taskLabel: signal?.taskLabel, taskObservedAt: signal?.taskObservedAt,
                lastEvent: signal?.event, lastEventAt: signal?.observedAt,
                sharedHostHookSeen: root.agent == "Codex" && signal == nil && sharedCodexHookSeen,
                allowsSessionLink: root.agent == "Codex" && root.hasControllingTerminal && directSignal == nil,
                isSessionLinked: linkedKey != nil)
        }
        .sorted { $0.process.memory == $1.process.memory ? $0.id.pid < $1.id.pid : $0.process.memory > $1.process.memory }
    }

    func checkAgentPresence() async {
        _ = rows(for: .agents)
        let identities = (agentRows ?? []).map(\.id)
        let gone = await Task.detached(priority: .utility) {
            Set(identities.filter { ProcessPresence.inspect($0) == .gone })
        }.value
        if gone != absentAgentProcesses { absentAgentProcesses = gone }
        // Hook expiry must also redraw while process sampling is paused.
        let activities = Dictionary(agentWallTiles.map { ($0.id, $0.activity) }, uniquingKeysWith: { first, _ in first })
        if activities != lastAgentActivities {
            lastAgentActivities = activities
            rowCache.removeValue(forKey: .agents)
            objectWillChange.send()
        }
    }
    var observerSummary: String {
        guard let snapshot, let own = snapshot.processes.first(where: { $0.id.pid == ProcessInfo.processInfo.processIdentifier }) else { return "Monitor measuring" }
        let cpu = own.cpu.map { String(format: "%.1f%% CPU", $0) } ?? "CPU measuring"
        let duration = snapshot.scanSeconds * 1_000
        let scan = duration.isFinite && duration >= 0 && duration < Double(Int.max) ? "\(Int(duration)) ms" : "unavailable"
        return "Monitor \(cpu) · \(Self.bytes(own.memory)) · scan \(scan)"
    }
    var usedMemory: String {
        guard let headroom = snapshot?.system.memoryHeadroomRatio, headroom.isFinite, (0...1).contains(headroom) else { return "—" }
        return Self.bytes(UInt64(Double(ProcessInfo.processInfo.physicalMemory) * (1 - headroom)))
    }
    // MainActor confinement permits reuse without cross-thread formatter access.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()
    static func bytes(_ bytes: UInt64) -> String { byteFormatter.string(fromByteCount: Int64(clamping: bytes)) }

    func exportSnapshot() {
        guard let captured = snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "performancedaddy-snapshot.json"
        panel.message = "Save all sampled processes, not just the filtered rows. Names, paths, raw PIDs and bind addresses are omitted. Agent types, resource measurements and port numbers remain."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try SnapshotExport.data(for: captured, physicalMemory: ProcessInfo.processInfo.physicalMemory)
                try data.write(to: url, options: .atomic)
                self.exportNotice = "Redacted snapshot saved."
            } catch {
                self.exportNotice = "Could not save the snapshot. Choose another writable location and try again."
            }
        }
    }

    func prepare(_ targets: [LiveProcess]) {
        let eligible = targets.filter { $0.stopRestriction == nil }
        guard !eligible.isEmpty else { return }
        review = Review(targets: eligible)
    }
    func prepareSelected() {
        prepare((snapshot?.processes ?? []).filter { selection.contains($0.id) })
    }
    func prepareTree(_ process: LiveProcess) {
        prepare(index.descendants(of: process))
    }
    func prepareFamilies(_ roots: [LiveProcess]) {
        var seen: Set<ProcessIdentity> = []
        prepare(roots.flatMap { index.descendants(of: $0) }.filter { seen.insert($0.id).inserted })
    }
    func confirmStop(force: Bool) async {
        guard let reviewed = review else { return }
        performingAction = true
        review = nil
        let beforeStop = snapshot?.processes ?? []
        outcomes = await Task.detached {
            ProcessControl.stop(reviewed.targets.reversed(), force: force)
        }.value
        for outcome in outcomes {
            guard let date = outcome.signalDate else { continue }
            lifecycle.record(outcome.process, at: date, force: force,
                signalSent: outcome.signalSent, observed: beforeStop)
        }
        persistLifecycle()
        try? await Task.sleep(for: .seconds(1))
        await refresh()
        performingAction = false
    }
    func outcomeText(_ result: StopResult) -> String {
        guard result.signalSent else { return result.message }
        if confirmedExits.contains(result.process.id) { return "Exit confirmed; original process identity is gone" }
        let live = snapshot?.processes.contains { $0.id == result.process.id } ?? false
        return live ? "Signal sent; process still observed" : "Signal sent; exit not confirmed (inspection unavailable)"
    }

    func handleSystemWake() {
        needsNewMeasurementWindow = true
    }

    func restoreLifecycle() async {
        guard !lifecycleLoaded else { return }
        lifecycleLoaded = true
        let events = await lifecycleStore.load()
        lifecycle = ProcessLifecycleJournal(events: events)
        objectWillChange.send()
    }

    func waitForLifecyclePersistence() async {
        await lifecycleSaveTask?.value
    }

    private func persistLifecycle() {
        let events = lifecycle.events
        let previous = lifecycleSaveTask
        let store = lifecycleStore
        lifecycleSaveTask = Task {
            await previous?.value
            try? await store.save(events)
        }
    }
}

// Presentation keys keep native column sorting aligned with the displayed values.
extension LiveProcess {
    var sortRunning: Double { ProcessUnderstanding.duration(id, at: Date()) == nil ? -Double.greatestFiniteMagnitude : -Double(id.started) }
    var sortName: String { agent ?? name }
    var sortCPU: Double { cpu ?? -1 }
    var sortPort: Int { ports.map { Int($0.port) }.min() ?? 65_536 }
    var portLabel: String { Set(ports.map(\.port)).sorted().map(String.init).joined(separator: ", ") }
}
