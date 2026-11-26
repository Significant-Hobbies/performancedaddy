import PerformanceCore
import SaaSMakerUI
import SwiftUI
import UserNotifications

/// Stable identifiers for links from a host's sidebar, overview and notifications.
public enum PerformanceRoute: String, CaseIterable, Identifiable, Sendable {
    case diagnose, processes, ports, agents, memory, thermals, access, configuration, alerts
    case followUp = "follow-up"
    case traces, culprits

    public var id: String { rawValue }

    var dashboardDestination: String {
        switch self {
        case .processes, .culprits: "Processes"
        case .ports: "Ports"
        case .agents: "Agent sessions"
        case .memory: "Memory"
        case .thermals: "Fans & heat"
        case .access: "App access"
        case .configuration: "Configuration"
        case .diagnose, .followUp, .traces: "Diagnose"
        case .alerts: "Performance alerts"
        }
    }
}

/// Keep one session for the lifetime of the app; closing a workspace must not end an investigation.
@MainActor public final class PerformanceWorkspaceSession: ObservableObject {
    let live: LiveViewModel
    let diagnosis: DiagnosisViewModel
    let alerts: LoadAlertCenter

    public init() {
        let preferences = UserDefaults(suiteName: "com.significanthobbies.performancedaddy") ?? .standard
        live = LiveViewModel(preferences: preferences)
        diagnosis = DiagnosisViewModel()
        alerts = LoadAlertCenter(defaults: preferences)
        diagnosis.attach(to: live)
    }

    /// The host owns the notification delegate. Supply an opener for reviewed alert actions.
    public func start(openPerformance: @escaping () -> Void) {
        alerts.attach(to: live, ownsNotificationCenter: false, openMainWindow: openPerformance)
        live.start()
    }

    public var notificationCategories: Set<UNNotificationCategory> {
        LoadAlertCenter.notificationCategories
    }

    public func handleNotification(_ delivery: PerformanceNotificationDelivery) async -> Bool {
        guard notificationCategories.contains(where: { $0.identifier == delivery.category }) else { return false }
        await alerts.deliver(delivery)
        return true
    }

    public var activeWorkDescription: String? {
        PerformanceActiveWork.description(isRecording: diagnosis.isRecording, performingAction: live.performingAction)
    }
}

public struct PerformanceWorkspaceView: View {
    let session: PerformanceWorkspaceSession
    let route: PerformanceRoute
    let onNavigate: (PerformanceRoute) -> Void

    public init(session: PerformanceWorkspaceSession, route: PerformanceRoute,
                onNavigate: @escaping (PerformanceRoute) -> Void) {
        self.session = session
        self.route = route
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Group {
            switch route {
            case .alerts:
                LoadAlertSettingsView(alerts: session.alerts, live: session.live, embedded: true)
            case .culprits:
                ResourceLeadersView(model: session.live, onDone: { onNavigate(.processes) })
            default:
                DashboardView(model: session.diagnosis, live: session.live,
                              initialDestination: route.dashboardDestination, embedded: true,
                              entryAction: route) { destination in
                    guard destination != route.dashboardDestination,
                          let next = PerformanceRoute.allCases.first(where: { $0.dashboardDestination == destination })
                    else { return }
                    onNavigate(next)
                }
                .id(route)
            }
        }
        .performanceTheme(PerformanceTheme.palette)
        .buttonStyle(SMMacButtonStyle())
        .background(MonitoringSurface(model: session.live))
        .task { session.live.start() }
    }
}

public struct PerformanceAgentWall: View {
    let session: PerformanceWorkspaceSession
    public init(session: PerformanceWorkspaceSession) { self.session = session }

    public var body: some View {
        AgentWallView(model: session.live)
            .performanceTheme(PerformanceTheme.palette)
            .buttonStyle(SMMacButtonStyle())
            .background(MonitoringSurface(model: session.live))
            .task { session.live.start() }
    }
}

/// Embeddable menu actions; the containing app owns the actual status item and quit/update controls.
public struct PerformanceWorkspaceMenu: View {
    let session: PerformanceWorkspaceSession
    let onNavigate: (PerformanceRoute) -> Void
    @ObservedObject private var live: LiveViewModel
    @Environment(\.openWindow) private var openWindow
    public init(session: PerformanceWorkspaceSession, onNavigate: @escaping (PerformanceRoute) -> Void) {
        self.session = session
        self.onNavigate = onNavigate
        _live = ObservedObject(wrappedValue: session.live)
    }
    public var body: some View {
        Button("Find CPU & RAM culprits") { onNavigate(.culprits) }
        Button("Feels slow now") {
            if !session.diagnosis.isRecording { session.diagnosis.markSlowMoment() }
            onNavigate(.diagnose)
        }
        Button("Agent sessions (\(live.agentCount))") { onNavigate(.agents) }
        Button(live.paused ? "Resume performance monitoring" : "Pause performance monitoring") {
            live.paused.toggle()
        }
        Button("Open agent wall") { openWindow(id: "agent-wall") }
        Button("Performance alerts…") { onNavigate(.alerts) }
        DaddyCompletionNoticeToggle(title: "Notify when diagnosis finishes")
    }
}

/// The agent-state indicator from the standalone menu bar, driven by the shared session.
public struct PerformanceAgentStatusIndicator: View {
    @StateObject private var status: AgentMenuStatus

    public init(session: PerformanceWorkspaceSession) {
        _status = StateObject(wrappedValue: AgentMenuStatus(model: session.live))
    }

    public var body: some View {
        AgentStatusSummaryLabel(summary: status.summary).equatable()
    }
}
