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

    private let defaults: UserDefaults
    private weak var live: LiveViewModel?
    private var openMainWindow: (() -> Void)?
    private var tracker = SustainedLoadTracker()
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
        super.init()
        applyPolicy()
    }

    var policy: LoadAlertPolicy {
        LoadAlertPolicy(cpuFraction: Double(cpuPercent) / 100, cpuSeconds: TimeInterval(cpuSeconds),
                        memorySeconds: TimeInterval(memorySeconds), cooldown: TimeInterval(cooldownMinutes * 60))
    }

    func attach(to live: LiveViewModel, openMainWindow: @escaping () -> Void) {
        guard self.live == nil else { return }
        self.live = live
        self.openMainWindow = openMainWindow
        live.sampleObserver = { [weak self] snapshot in self?.observe(snapshot) }
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

    func unignore(_ key: String) { ignored.removeValue(forKey: key) }

    func refreshAuthorization() {
        guard Self.notificationsAvailable else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            authorization = status
        }
    }

    private func requestAuthorization() {
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
        tracker.policy = policy
        tracker.reset()
    }

    func observe(_ snapshot: LiveSnapshot) {
        guard enabled, authorization == .authorized || authorization == .provisional else { tracker.reset(); return }
        guard let alert = tracker.observe(snapshot, coreCount: ProcessInfo.processInfo.processorCount,
                                          ignored: Set(ignored.keys)) else { return }
        post(alert)
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
        content.userInfo = ["alert": id, "ignoreKey": alert.contributor?.ignoreKey ?? "", "name": alert.contributor?.name ?? ""]
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

    fileprivate func handle(action: String, alertID: String?, ignoreKey: String?, name: String?) async {
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
            showApp()
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
        }
        postNote("After quitting", body + " One later sample, not a controlled comparison.")
    }

    private func showApp() {
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
                      ignoreKey: info["ignoreKey"] as? String, name: info["name"] as? String)
    }
}

struct LoadAlertSettingsView: View {
    @ObservedObject var alerts: LoadAlertCenter

    var body: some View {
        Form {
            Section {
                Toggle("Notify me about sustained load", isOn: $alerts.enabled)
                if alerts.enabled, alerts.authorization == .denied {
                    HStack {
                        Text("Notifications are turned off for PerformanceDaddy in System Settings.")
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let id = Bundle.main.bundleIdentifier,
                               let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else if !LoadAlertCenter.notificationsAvailable {
                    Text("Notifications need the bundled app.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Alerts never quit anything on their own. Quit only runs when you press it on an alert from the last 10 minutes; apps get a normal quit request and may ask you to save.")
                    .foregroundStyle(.secondary)
            }
            Section("Thresholds") {
                Stepper("CPU: \(alerts.cpuPercent)% of all cores", value: $alerts.cpuPercent, in: 50...100, step: 5)
                Stepper("CPU sustained for \(alerts.cpuSeconds) seconds", value: $alerts.cpuSeconds, in: 30...600, step: 30)
                Stepper("Memory pressure sustained for \(alerts.memorySeconds) seconds", value: $alerts.memorySeconds, in: 30...600, step: 30)
                Stepper("Wait \(alerts.cooldownMinutes) minutes between alerts", value: $alerts.cooldownMinutes, in: 5...120, step: 5)
            }
            Section("Not alerting for") {
                if alerts.ignored.isEmpty {
                    Text("Nothing ignored").foregroundStyle(.secondary)
                } else {
                    ForEach(alerts.ignored.sorted { $0.value < $1.value }, id: \.key) { key, name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Remove") { alerts.unignore(key) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { alerts.refreshAuthorization() }
    }
}
