import AppKit
import PerformanceCore
import SwiftUI
import UserNotifications

/// Posts sustained-load notifications. The only action that touches a process
/// is the owner pressing Quit on a fresh alert; nothing is quit automatically.
@MainActor
final class LoadAlertCenter: NSObject, ObservableObject {
    private enum Key {
        static let enabled = "loadAlerts.enabled"
        static let cpuPercent = "loadAlerts.cpuPercent"
        static let cpuSeconds = "loadAlerts.cpuSeconds"
        static let memorySeconds = "loadAlerts.memorySeconds"
        static let cooldownMinutes = "loadAlerts.cooldownMinutes"
        static let ignored = "loadAlerts.ignored"
        static let watchdog = "loadAlerts.watchdog"
    }
    private enum Category {
        static let quitApp = "performancedaddy.load.app"
        static let stopProcess = "performancedaddy.load.process"
        static let info = "performancedaddy.load.info"
    }
    private enum Action {
        static let quit = "quit"
        static let mute = "mute"
    }
    /// After this, a Quit tap opens the app instead: the evidence is stale.
    static let actionableSeconds: TimeInterval = 600

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Key.enabled)
            tracker.reset()
            live?.needsCloserMonitoring = false
            if enabled { requestAuthorization() }
        }
    }
    @Published var cpuPercent: Int { didSet { save(cpuPercent, Key.cpuPercent) } }
    @Published var cpuSeconds: Int { didSet { save(cpuSeconds, Key.cpuSeconds) } }
    @Published var memorySeconds: Int { didSet { save(memorySeconds, Key.memorySeconds) } }
    @Published var cooldownMinutes: Int { didSet { save(cooldownMinutes, Key.cooldownMinutes) } }
    /// Ignore key → display name.
    @Published private(set) var ignored: [String: String] {
        didSet { defaults.set(ignored, forKey: Key.ignored) }
    }
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published var watchdogPolicy: WatchdogPolicy {
        didSet {
            if let data = try? JSONEncoder().encode(watchdogPolicy) { defaults.set(data, forKey: Key.watchdog) }
            applyPolicy()
        }
    }
    @Published private(set) var snoozedUntil: Date?
    struct RecentAlert: Identifiable {
        let id = UUID()
        let date: Date
        let kind: LoadAlert.Kind
        let title: String
        let body: String
        let identity: ProcessIdentity?
    }
    /// Session-only summaries: no snapshots, process paths, or unbounded history.
    @Published private(set) var recent: [RecentAlert] = []

    private let defaults: UserDefaults
    private weak var live: LiveViewModel?
    private var openMainWindow: (() -> Void)?
    private var tracker = PerformanceWatchdog()
    private var pending: [String: LoadAlert] = [:]

    /// UNUserNotificationCenter requires a bundled app; tests and `swift run` have none.
    static var notificationsAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Key.enabled)
        cpuPercent = defaults.object(forKey: Key.cpuPercent) as? Int ?? 80
        cpuSeconds = defaults.object(forKey: Key.cpuSeconds) as? Int ?? 90
        memorySeconds = defaults.object(forKey: Key.memorySeconds) as? Int ?? 60
        cooldownMinutes = defaults.object(forKey: Key.cooldownMinutes) as? Int ?? 15
        ignored = defaults.dictionary(forKey: Key.ignored) as? [String: String] ?? [:]
        watchdogPolicy = defaults.data(forKey: Key.watchdog).flatMap { try? JSONDecoder().decode(WatchdogPolicy.self, from: $0) } ?? WatchdogPolicy()
        super.init()
        applyPolicy()
    }

    var policy: LoadAlertPolicy {
        LoadAlertPolicy(cpuFraction: Double(max(50, min(100, cpuPercent))) / 100,
                        cpuSeconds: TimeInterval(max(30, min(600, cpuSeconds))),
                        memorySeconds: TimeInterval(max(30, min(600, memorySeconds))),
                        cooldown: TimeInterval(max(5, min(120, cooldownMinutes)) * 60))
    }

    func attach(to live: LiveViewModel, openMainWindow: @escaping () -> Void) {
        guard self.live == nil else { return }
        self.live = live
        self.openMainWindow = openMainWindow
        live.sampleObserver = { [weak self] snapshot in self?.observe(snapshot) }
        live.measurementResetObserver = { [weak self] in
            self?.tracker.reset()
            self?.live?.needsCloserMonitoring = false
        }
        guard Self.notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.quitApp, actions: [
                UNNotificationAction(identifier: Action.quit, title: "Quit App", options: [.destructive]),
                UNNotificationAction(identifier: Action.mute, title: "Don't Alert for This App"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.stopProcess, actions: [
                UNNotificationAction(identifier: Action.quit, title: "Stop Process", options: [.destructive]),
                UNNotificationAction(identifier: Action.mute, title: "Don't Alert for This Process"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.info, actions: [], intentIdentifiers: []),
        ])
        refreshAuthorization()
    }

    func unignore(_ key: String) { ignored.removeValue(forKey: key); tracker.reset() }
    func snooze(minutes: Int) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(max(1, min(1_440, minutes)) * 60))
        tracker.reset(); live?.needsCloserMonitoring = false
    }
    func resumeAlerts() { snoozedUntil = nil; tracker.reset() }
    func clearRecent() { recent.removeAll() }
    func ignore(_ key: String, name: String) { ignored[key] = name; tracker.reset() }

    func refreshAuthorization() {
        guard Self.notificationsAvailable else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            authorization = status
        }
    }

    func requestAuthorization() {
        guard Self.notificationsAvailable else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            refreshAuthorization()
        }
    }

    private func save(_ value: Int, _ key: String) {
        defaults.set(value, forKey: key)
        applyPolicy()
    }

    private func applyPolicy() {
        tracker.loadPolicy = policy
        var advanced = watchdogPolicy
        advanced.cooldown = policy.cooldown
        tracker.policy = advanced
        tracker.reset()
        live?.needsCloserMonitoring = false
    }

    func observe(_ snapshot: LiveSnapshot) {
        guard enabled, snoozedUntil.map({ $0 > snapshot.date }) != true else {
            tracker.reset(); live?.needsCloserMonitoring = false; return
        }
        if snoozedUntil != nil { snoozedUntil = nil }
        let alerts = tracker.observe(snapshot, coreCount: ProcessInfo.processInfo.processorCount, ignored: Set(ignored.keys))
        live?.needsCloserMonitoring = tracker.needsCloserLook
        for alert in alerts {
            let text = Self.content(for: alert, actionable: alert.contributor?.owner.stopRestriction == nil)
            recent.insert(RecentAlert(date: alert.date, kind: alert.kind, title: text.title, body: text.body, identity: alert.contributor?.owner.id), at: 0)
            if recent.count > 50 { recent.removeLast(recent.count - 50) }
        }
        if authorization == .authorized || authorization == .provisional {
            var posted: Set<String> = []
            for alert in alerts.sorted(by: { Self.priority($0.kind) < Self.priority($1.kind) }) {
                let key: String
                if alert.kind == .fans || alert.kind == .thermal { key = "heat" }
                else if let owner = alert.contributor?.owner.id { key = "\(owner.pid):\(owner.started)" }
                else { key = alert.kind.rawValue }
                if posted.insert(key).inserted { post(alert) }
            }
        }
    }

    private static func priority(_ kind: LoadAlert.Kind) -> Int {
        switch kind {
        case .thermal: 0
        case .memory: 1
        case .fans: 2
        case .cpu: 3
        case .processCPU: 4
        case .memoryGrowth: 5
        case .largeMemory: 6
        }
    }

    // MARK: Content

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds < 120 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minutes"
    }

    static func content(for alert: LoadAlert, actionable: Bool) -> (title: String, body: String) {
        let span = duration(alert.duration)
        switch alert.kind {
        case .cpu:
            let used = alert.usedCores.map { String(format: "%.1f", $0) } ?? "most"
            let title = "Sustained CPU load"
            guard let leader = alert.contributor else {
                return (title, "\(used) of \(alert.coreCount) cores busy for \(span). No single app consistently led; open PerformanceDaddy to review.")
            }
            let scope = leader.kind == .app ? "\(leader.name) and its helpers" : leader.name
            return (title, "\(used) of \(alert.coreCount) cores busy for \(span). \(scope) used about \(String(format: "%.1f", leader.cpuCores)) cores."
                + (actionable ? "" : " It is protected and can't be quit from here."))
        case .memory:
            let title = "Memory pressure: \(alert.pressure)"
            guard let leader = alert.contributor else {
                return (title, "Pressure stayed elevated for \(span). No single app held most memory; open PerformanceDaddy to review.")
            }
            return (title, "Pressure stayed elevated for \(span). \(leader.name) holds the most memory (\(LiveViewModel.bytes(leader.memoryBytes)))."
                + (actionable ? "" : " It is protected and can't be quit from here."))
        case .processCPU, .largeMemory, .memoryGrowth:
            let name = alert.contributor.map { $0.kind == .app ? "\($0.name) and its helpers" : $0.name } ?? "Workload"
            let title = alert.kind == .processCPU ? "Sustained workload CPU" : alert.kind == .largeMemory ? "Workload memory limit" : "Growing workload memory"
            return (title, "\(name) · \(span). \(alert.detail ?? "Open PerformanceDaddy to review.")")
        case .thermal, .fans:
            return (alert.kind == .thermal ? "Sustained thermal pressure" : "Sustained high fan speed",
                    "\(span). \(alert.detail ?? "Open Fans & heat to investigate.")")
        }
    }

    private func post(_ alert: LoadAlert) {
        guard Self.notificationsAvailable else { return }
        let id = UUID().uuidString
        let actionable = alert.contributor.map { $0.owner.stopRestriction == nil } ?? false
        let text = Self.content(for: alert, actionable: actionable)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        // Kept in the local notification so "don't alert" works after a relaunch.
        content.userInfo = ["alert": id, "ignoreKey": alert.contributor?.ignoreKey ?? "", "name": alert.contributor?.name ?? "", "kind": alert.kind.rawValue]
        content.categoryIdentifier = !actionable ? Category.info
            : alert.contributor?.kind == .app ? Category.quitApp : Category.stopProcess
        pending = pending.filter { Date().timeIntervalSince($0.value.date) < Self.actionableSeconds }
        pending[id] = alert
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func postNote(_ title: String, _ body: String) {
        guard Self.notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Category.info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: Responses

    fileprivate func handle(action: String, alertID: String?, ignoreKey: String?, name: String?, kind: LoadAlert.Kind? = nil) async {
        let alert = alertID.flatMap { pending[$0] }
        switch action {
        case Action.quit:
            guard let alert, let target = alert.contributor, let live,
                  Date().timeIntervalSince(alert.date) < Self.actionableSeconds else {
                // Expired or unknown after relaunch: show current evidence instead.
                showApp()
                return
            }
            pending.removeValue(forKey: alertID ?? "")
            let quitAt = Date()
            let message = await live.quitFromLoadAlert(target)
            postNote(target.name, message)
            await followUp(alert, after: quitAt)
        case Action.mute:
            guard let ignoreKey, !ignoreKey.isEmpty else { return }
            ignored[ignoreKey] = name?.isEmpty == false ? name : ignoreKey
        case UNNotificationDefaultActionIdentifier:
            showApp(for: alert?.kind ?? kind, identity: alert?.contributor?.owner.id)
        default:
            break
        }
    }

    /// One later sample, reported as an observation rather than proof of cause.
    private func followUp(_ alert: LoadAlert, after date: Date) async {
        try? await Task.sleep(for: .seconds(40))
        guard let snapshot = live?.snapshot, snapshot.date > date.addingTimeInterval(5) else { return }
        let body: String
        switch alert.kind {
        case .cpu:
            guard let before = alert.usedCores, let after = snapshot.system.usedCPUCores else { return }
            body = String(format: "CPU in use: %.1f → %.1f cores.", before, after)
        case .memory:
            body = "Memory pressure: \(alert.pressure) → \(snapshot.pressure)."
        case .processCPU:
            guard let before = alert.usedCores, let after = snapshot.system.usedCPUCores else { return }
            body = String(format: "System CPU in use: %.1f → %.1f cores.", before, after)
        case .largeMemory, .memoryGrowth:
            body = "Memory pressure: \(alert.pressure) → \(snapshot.pressure)."
        case .thermal, .fans: return
        }
        postNote("After quitting", body + " One later sample, not a controlled comparison.")
    }

    func showApp(for kind: LoadAlert.Kind? = nil, identity: ProcessIdentity? = nil) {
        if let identity, live?.snapshot?.processes.contains(where: { $0.id == identity }) == true { live?.selection = [identity] }
        if kind == .fans || kind == .thermal { live?.requestedDestination = "Fans & heat" }
        else if kind == .memory || kind == .largeMemory || kind == .memoryGrowth { live?.requestedDestination = "Memory" }
        else { live?.requestedDestination = "Processes" }
        openMainWindow?()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

extension LoadAlertCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        await handle(action: action, alertID: info["alert"] as? String,
                     ignoreKey: info["ignoreKey"] as? String, name: info["name"] as? String,
                     kind: (info["kind"] as? String).flatMap(LoadAlert.Kind.init(rawValue:)))
    }
}

struct LoadAlertSettingsView: View {
    @ObservedObject var alerts: LoadAlertCenter
    @ObservedObject var live: LiveViewModel
    @State private var workloadSearch = ""

    var body: some View {
        TabView {
            rules.tabItem { Label("Alerts", systemImage: "bell") }
            workloads.tabItem { Label("Workload limits", systemImage: "app.badge") }
            activity.tabItem { Label("Recent alerts", systemImage: "clock") }
        }
        .padding(12)
        .frame(width: 600, height: 700)
        .onAppear { alerts.refreshAuthorization() }
    }

    private var rules: some View {
        Form {
            Section {
                Toggle("Notify me about sustained performance problems", isOn: $alerts.enabled)
                if live.paused {
                    Label("Monitoring is paused. Resume from the menu or main window.", systemImage: "pause.circle")
                } else {
                    Text(live.hasVisibleSurface ? "Watching live while a diagnostic window is visible." : "Watching in the background. Healthy captures are 30 seconds apart; sustained signals get a closer look.")
                        .foregroundStyle(.secondary)
                }
                if let until = alerts.snoozedUntil, until > Date() {
                    HStack {
                        Text("Alerts snoozed until \(until.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        Button("Resume alerts", action: alerts.resumeAlerts)
                    }
                } else {
                    Menu("Snooze alerts") {
                        Button("15 minutes") { alerts.snooze(minutes: 15) }
                        Button("1 hour") { alerts.snooze(minutes: 60) }
                    }.disabled(!alerts.enabled)
                }
                if alerts.enabled, alerts.authorization == .denied {
                    Text("System notifications are off. Findings still appear in Recent alerts.").foregroundStyle(.secondary)
                    Button("Open Notification Settings") {
                        if let id = Bundle.main.bundleIdentifier,
                           let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if alerts.enabled, alerts.authorization == .notDetermined, LoadAlertCenter.notificationsAvailable {
                    Button("Allow system notifications…", action: alerts.requestAuthorization)
                } else if !LoadAlertCenter.notificationsAvailable {
                    Text("System notifications need the bundled app.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Local and read-only. Alerts never change fan speeds or stop anything automatically. Short spikes are ignored; missing readings break a sustained window.")
            }
            Section("Whole Mac") {
                Stepper("CPU: \(alerts.cpuPercent)% of all cores", value: $alerts.cpuPercent, in: 50...100, step: 5)
                Stepper("CPU sustained for \(alerts.cpuSeconds) seconds", value: $alerts.cpuSeconds, in: 30...600, step: 30)
                Stepper("Memory pressure sustained for \(alerts.memorySeconds) seconds", value: $alerts.memorySeconds, in: 30...600, step: 30)
                Stepper("Repeat cooldown: \(alerts.cooldownMinutes) minutes", value: $alerts.cooldownMinutes, in: 5...120, step: 5)
            }
            Section {
                kindToggle("Sustained workload CPU", .processCPU)
                Stepper("CPU: \(alerts.watchdogPolicy.processCPUPercent)% (100% = one core)", value: $alerts.watchdogPolicy.processCPUPercent, in: 20...800, step: 10)
                Stepper("CPU / memory limit duration: \(Int(alerts.watchdogPolicy.processSeconds)) seconds", value: $alerts.watchdogPolicy.processSeconds, in: 60...900, step: 30)
                kindToggle("Resident memory above a limit", .largeMemory)
                Stepper("Resident memory: \(alerts.watchdogPolicy.memoryGB) GB", value: $alerts.watchdogPolicy.memoryGB, in: 1...128)
                kindToggle("Substantial memory growth", .memoryGrowth)
                Stepper("Growth: \(alerts.watchdogPolicy.growthMB) MB and at least 50%", value: $alerts.watchdogPolicy.growthMB, in: 128...8192, step: 128)
                Stepper("Growth window: \(Int(alerts.watchdogPolicy.growthSeconds / 60)) minutes", value: $alerts.watchdogPolicy.growthSeconds, in: 120...900, step: 60)
            } header: {
                Text("Individual workloads")
            } footer: {
                Text("Apps include their helpers. Resident memory can include shared pages; growth does not prove a leak. Per-workload limits override these thresholds.")
            }
            Section {
                kindToggle("Sustained serious or critical thermal pressure", .thermal)
                Stepper("Thermal duration: \(Int(alerts.watchdogPolicy.thermalSeconds)) seconds", value: $alerts.watchdogPolicy.thermalSeconds, in: 30...600, step: 30)
                kindToggle("Sustained high measured fan speed", .fans)
                Stepper("Fan speed: \(alerts.watchdogPolicy.fanPercent)% of reported maximum", value: $alerts.watchdogPolicy.fanPercent, in: 50...100, step: 5)
                Stepper("Fan duration: \(Int(alerts.watchdogPolicy.fanSeconds)) seconds", value: $alerts.watchdogPolicy.fanSeconds, in: 60...600, step: 30)
            } header: {
                Text("Fans & heat")
            } footer: {
                Text("Fan alerts need readable RPM and a reported maximum. Missing sensors remain unavailable. Thermal alerts identify macOS pressure, not a proven heating app or clock throttle.")
            }
        }.formStyle(.grouped)
    }

    private func kindToggle(_ title: String, _ kind: LoadAlert.Kind) -> some View {
        Toggle(title, isOn: Binding(get: { alerts.watchdogPolicy.kinds.contains(kind) }, set: { enabled in
            if enabled { alerts.watchdogPolicy.kinds.insert(kind) }
            else { alerts.watchdogPolicy.kinds.remove(kind) }
        }))
    }

    private var workloads: some View {
        Form {
            Section {
                TextField("Find a running app or process", text: $workloadSearch)
                Menu("Add a running workload") {
                    ForEach(runningWorkloads, id: \.ignoreKey) { workload in
                        Button(workload.name) {
                            alerts.watchdogPolicy.limits[workload.ignoreKey] = WorkloadAlertLimit(name: workload.name,
                                cpuPercent: alerts.watchdogPolicy.processCPUPercent, memoryGB: alerts.watchdogPolicy.memoryGB)
                        }
                    }
                }.disabled(live.snapshot == nil)
                ForEach(alerts.watchdogPolicy.limits.keys.sorted(), id: \.self) { key in
                    if let limit = alerts.watchdogPolicy.limits[key] {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(limit.name).font(.headline)
                                Spacer()
                                Button("Remove") { alerts.watchdogPolicy.limits.removeValue(forKey: key) }
                            }
                            Stepper("CPU: \(limit.cpuPercent)%", value: Binding(get: {
                                alerts.watchdogPolicy.limits[key]?.cpuPercent ?? 100
                            }, set: { alerts.watchdogPolicy.limits[key]?.cpuPercent = $0 }), in: 20...1600, step: 10)
                            Stepper("Resident memory: \(limit.memoryGB) GB", value: Binding(get: {
                                alerts.watchdogPolicy.limits[key]?.memoryGB ?? 4
                            }, set: { alerts.watchdogPolicy.limits[key]?.memoryGB = $0 }), in: 1...128)
                        }.padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Custom limits")
            } footer: {
                Text("Custom limits enable both CPU and resident-memory alerts using the duration on the Alerts tab. Limits and mutes follow the app, executable or agent provider across launches; sustained evidence always starts fresh.")
            }
            Section("Muted workloads") {
                Menu("Mute a running workload") {
                    ForEach(runningWorkloads, id: \.ignoreKey) { workload in
                        Button(workload.name) { alerts.ignore(workload.ignoreKey, name: workload.name) }
                    }
                }.disabled(live.snapshot == nil)
                if alerts.ignored.isEmpty { Text("Nothing muted").foregroundStyle(.secondary) }
                ForEach(alerts.ignored.sorted { $0.value < $1.value }, id: \.key) { key, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Unmute") { alerts.unignore(key) }
                    }
                }
            }
        }.formStyle(.grouped)
    }

    private var runningWorkloads: [LoadContributor] {
        var seen: Set<String> = []
        return Array(LoadContributors.group(live.snapshot?.processes ?? [])
            .filter { (workloadSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(workloadSearch)) && seen.insert($0.ignoreKey).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(80))
    }

    private var activity: some View {
        Form {
            Section {
                Text("Last 50 alerts from this session. Summaries stay in memory and disappear when the app quits.").foregroundStyle(.secondary)
                if alerts.recent.isEmpty { Text("No sustained problems detected while alerts were enabled.") }
                ForEach(alerts.recent) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            Text(item.date, style: .time).foregroundStyle(.secondary)
                        }
                        Text(item.body).fixedSize(horizontal: false, vertical: true)
                        Button(item.kind == .thermal || item.kind == .fans ? "Investigate Fans & heat" : "Inspect current readings") {
                            alerts.showApp(for: item.kind, identity: item.identity)
                        }
                    }.padding(.vertical, 6)
                }
                Button("Clear recent alerts", action: alerts.clearRecent).disabled(alerts.recent.isEmpty)
            }
        }.formStyle(.grouped)
    }
}
