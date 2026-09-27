import Darwin
import Foundation
import NativeInspection
import PerformanceCore

enum AgentHookCommand {
    static func run() {
        // Hook JSON may contain private conversation data. Derive only a short,
        // bounded label from an opted-in prompt; never persist or forward the prompt.
        guard CommandLine.arguments.count == 3,
              let provider = AgentIdentity.supportedNames.first(where: {
                  $0.caseInsensitiveCompare(CommandLine.arguments[2]) == .orderedSame
              }) else { return }
        let input = FileHandle.standardInput.readData(ofLength: 262_144)
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let event = statusEvent(provider: provider, payload: object) else { return }
        let rawEvent = object["hook_event_name"] as? String
        // Codex requires JSON from a successful Stop hook, even if this local
        // process cannot be linked to a visible session.
        defer {
            if provider == "Codex", rawEvent == "Stop" {
                FileHandle.standardOutput.write(Data("{}".utf8))
            }
        }

        var pid = getppid()
        var found: PDProcess?
        for _ in 0..<32 where pid > 1 {
            var info = PDProcess()
            guard pd_process(pid, &info) == 1 else { break }
            let path = withUnsafePointer(to: &info.path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
            }
            let name = withUnsafePointer(to: &info.name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            // The nearest matching process owns this hook. A terminal Codex
            // client can sit below a shared Codex app server in the ancestry.
            if AgentIdentity.label(executable: path, processName: name) == provider {
                found = info
                break
            }
            pid = info.parent
        }
        guard let found else { return }
        var payload: [String: Any] = ["pid": found.pid, "started": found.started,
                                      "provider": provider, "event": event,
                                      "timestamp": Date().timeIntervalSince1970]
        let observedCWD = withUnsafeBytes(of: found.cwd) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        if let cwd = (object["cwd"] as? String) ?? (observedCWD.isEmpty ? nil : observedCWD) {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty && name != "/" { payload["workspace"] = String(name.prefix(64)) }
            if let key = AgentWorkspaceKey.make(cwd) { payload["workspaceKey"] = key }
        }
        if rawEvent == "UserPromptSubmit", let prompt = object["prompt"] as? String,
           let label = shortTaskLabel(prompt) {
            payload["taskLabel"] = label
        }
        DistributedNotificationCenter.default().postNotificationName(
            AgentWallSignal.notification,
            object: nil,
            userInfo: payload,
            deliverImmediately: true
        )
    }

    static func statusEvent(provider: String, payload: [String: Any]) -> String? {
        guard let rawEvent = payload["hook_event_name"] as? String else { return nil }
        let event: String
        if rawEvent == "StopFailure", provider == "Claude",
           payload["error"] as? String == "rate_limit" {
            event = "RateLimit"
        } else if rawEvent == "Notification" {
            switch payload["notification_type"] as? String {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                event = "PermissionRequest"
            case "idle_prompt", "agent_completed":
                event = "Stop"
            default: return nil
            }
        } else {
            // RateLimit is an internal normalized status, not a provider event.
            if rawEvent == "RateLimit" { return nil }
            event = rawEvent
        }
        return AgentWallSignal.allowedEvents.contains(event) ? event : nil
    }

    static func shortTaskLabel(_ prompt: String) -> String? {
        // Claude can submit an internal completion notification as a prompt.
        // It is not a new user request and must not replace the last label.
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("<task-notification>") else { return nil }
        let line = prompt.split(whereSeparator: \.isNewline).prefix(12)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("<pasted_content") && !$0.hasPrefix("```") }
        guard var line else { return nil }
        line = line.replacingOccurrences(of: #"https?://\S+"#, with: "[link]", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\b[A-Za-z0-9_/-]{28,}\b"#, with: "[private]", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let prefix = String(line.prefix(88))
        return prefix.count < line.count ? prefix + "…" : prefix
    }
}
