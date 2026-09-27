import Foundation
import CryptoKit

/// A stable equality key for a local workspace path. The path itself never
/// leaves the hook process through the status notification.
public enum AgentWorkspaceKey {
    public static func make(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalized != "/" else { return nil }
        return SHA256.hash(data: Data(normalized.utf8))
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
    public var workspaceKey: String?
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
        self.workspaceKey = (data["workspaceKey"] as? String).flatMap { key in
            key.count == 64 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } ? key : nil
        }
        self.taskLabel = (data["taskLabel"] as? String).flatMap { $0.count <= 96 ? $0 : nil }
        self.taskObservedAt = taskLabel == nil ? nil : observedAt
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
