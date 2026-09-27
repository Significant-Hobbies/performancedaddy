import Foundation
import CryptoKit

/// A local equality key for events from the same provider session.
public enum AgentSessionKey {
    public static func make(_ sessionID: String) -> String? {
        guard !sessionID.isEmpty, sessionID.utf8.count <= 256 else { return nil }
        return SHA256.hash(data: Data(sessionID.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// Minimal local lifecycle evidence. A bounded task label can be derived from an
/// opted-in prompt hook; full prompts, transcripts, arguments and paths stay out.
public struct AgentWallSignal: Sendable, Equatable {
    public static let notification = Notification.Name("com.significanthobbies.performancedaddy.agent-status")
    public let process: ProcessIdentity
    public let provider: String
    public let event: String
    public let observedAt: Date
    public var workspace: String?
    public var sessionKey: String?
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
        self.sessionKey = (data["sessionKey"] as? String).flatMap { key in
            key.count == 64 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } ? key : nil
        }
        self.taskLabel = (data["taskLabel"] as? String).flatMap { $0.count <= 96 ? $0 : nil }
        self.taskObservedAt = taskLabel == nil ? nil : observedAt
    }

    public func carryingForward(from previous: Self) -> Self {
        var updated = self
        guard provider == previous.provider else { return updated }
        let sameSession = provider != "Codex" || (sessionKey != nil && sessionKey == previous.sessionKey)
        if sameSession { updated.workspace = workspace ?? previous.workspace }
        // A shared Codex app server can serve unrelated conversations. Never
        // display one session's request or workspace beside another's event.
        if sameSession {
            updated.taskLabel = taskLabel ?? previous.taskLabel
            updated.taskObservedAt = taskObservedAt ?? previous.taskObservedAt
        }
        return updated
    }

    public static let allowedEvents: Set<String> = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "PostToolUseFailure", "PreCompact", "PostCompact", "PostCompaction",
        "Elicitation", "ElicitationResult", "Stop", "StopFailure", "RateLimit",
        "Interrupt", "SessionEnd"
    ]
}

public enum AgentWallActivity: String, Sendable {
    case working = "Working"
    case waiting = "Needs input"
    case rateLimited = "Rate limited"
    case stopped = "Stopped"
    case failed = "Failed"
    case unavailable = "Status unavailable"

    public static func resolve(event: String?, age: TimeInterval) -> Self {
        guard let event, age >= 0 else { return .unavailable }
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PreCompact", "PostCompact", "PostCompaction", "ElicitationResult":
            return age <= 300 ? .working : .unavailable
        case "PermissionRequest", "Elicitation": return .waiting
        case "RateLimit": return .rateLimited
        case "StopFailure": return .failed
        case "Stop", "Interrupt", "SessionEnd": return .stopped
        case "SessionStart": return .unavailable
        default: return .unavailable
        }
    }
}
