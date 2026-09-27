import Foundation

/// Minimal local lifecycle evidence. A bounded task label can be derived from an
/// opted-in prompt hook; full prompts, transcripts, arguments and paths stay out.
public struct AgentWallSignal: Sendable, Equatable {
    public static let notification = Notification.Name("com.significanthobbies.performancedaddy.agent-status")
    public let process: ProcessIdentity
    public let provider: String
    public let event: String
    public let observedAt: Date
    public var workspace: String?
    public var taskLabel: String?
    public var taskObservedAt: Date?

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let data = userInfo,
              let pid = (data["pid"] as? NSNumber)?.int32Value,
              let started = (data["started"] as? NSNumber)?.uint64Value,
              let provider = data["provider"] as? String,
              let event = data["event"] as? String,
              let timestamp = (data["timestamp"] as? NSNumber)?.doubleValue,
              pid > 1, started > 0,
              AgentIdentity.supportedNames.contains(provider),
              Self.allowedEvents.contains(event),
              timestamp.isFinite,
              abs(Date().timeIntervalSince1970 - timestamp) < 120 else { return nil }
        self.process = ProcessIdentity(pid: pid, started: started)
        self.provider = provider
        self.event = event
        self.observedAt = Date(timeIntervalSince1970: timestamp)
        self.workspace = (data["workspace"] as? String).flatMap { $0.count <= 64 ? $0 : nil }
        self.taskLabel = (data["taskLabel"] as? String).flatMap { $0.count <= 96 ? $0 : nil }
        self.taskObservedAt = taskLabel == nil ? nil : observedAt
    }

    public static let allowedEvents: Set<String> = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "Stop", "StopFailure", "Interrupt", "SessionEnd"
    ]
}

public enum AgentWallActivity: String, Sendable {
    case working = "Working"
    case waiting = "Needs input"
    case stopped = "Stopped"
    case failed = "Failed"
    case unavailable = "Status unavailable"

    public static func resolve(event: String?, age: TimeInterval) -> Self {
        guard let event, age >= 0 else { return .unavailable }
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return age <= 300 ? .working : .unavailable
        case "PermissionRequest": return .waiting
        case "StopFailure": return .failed
        case "Stop", "Interrupt", "SessionEnd": return .stopped
        case "SessionStart": return .unavailable
        default: return .unavailable
        }
    }
}
