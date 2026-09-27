import AppKit
import PerformanceCore
import SwiftUI

struct AgentWallView: View {
    @ObservedObject var model: LiveViewModel

    var body: some View {
        GeometryReader { geometry in
            let tiles = model.agentWallTiles
            ScrollView {
                AgentTileMap(weights: weights(for: tiles), spacing: 12) {
                    ForEach(tiles) { tile in tileView(tile) }
                }
                .frame(width: max(1, geometry.size.width - 40),
                       height: max(geometry.size.height - 40,
                                   geometry.size.height - 40 + CGFloat(max(0, tiles.count - 8)) * 120))
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .background(PerformanceTheme.fog)
        .background(AgentWallFullScreenRequest())
        .preferredColorScheme(.dark)
    }

    private func tileView(_ tile: LiveViewModel.AgentWallTile) -> some View {
        let color = switch tile.activity {
        case .working: PerformanceTheme.mintInk
        case .waiting, .rateLimited, .stopped, .unavailable: PerformanceTheme.amber
        case .failed: PerformanceTheme.coral
        }
        return GeometryReader { geometry in
            let scale = min(2.8, max(1, min(geometry.size.width / 320, geometry.size.height / 200)))
            VStack(alignment: .leading, spacing: 10 * scale) {
                HStack(spacing: 8 * scale) {
                    Circle().fill(color).frame(width: 10 * scale, height: 10 * scale)
                    Text(tile.activity.rawValue.uppercased())
                        .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(color)
                    Spacer(minLength: 0)
                    if let path = tile.process.appPath {
                        AppBundleIcon(path: path, size: 28 * scale)
                    }
                }
                Spacer(minLength: 0)
                Text(tile.process.agent ?? tile.process.name)
                    .font(.system(size: 22 * scale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.workspace.map { "WORKSPACE · \($0)" } ?? "WORKSPACE UNAVAILABLE")
                    .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let task = tile.taskLabel {
                    Text("LATEST REQUEST · \(elapsed(tile.taskObservedAt))")
                        .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                    Text(task)
                        .font(.system(size: 15 * scale, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Awaiting agent event · reload hooks for older sessions")
                        .font(.system(size: 11 * scale, design: .rounded))
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if geometry.size.height > 270 {
                    Group {
                        if geometry.size.width >= 500 {
                            HStack(spacing: 10 * scale) {
                                Text("HOST \(tile.host ?? "Unavailable")")
                                Text("UP \(tile.runningFor ?? "Unknown")")
                                if let event = tile.lastEvent {
                                    Text("LAST \(eventDescription(event)) · \(elapsed(tile.lastEventAt))")
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3 * scale) {
                                Text("HOST \(tile.host ?? "Unavailable")")
                                Text("UP \(tile.runningFor ?? "Unknown")")
                                if let event = tile.lastEvent {
                                    Text("LAST \(eventDescription(event)) · \(elapsed(tile.lastEventAt))")
                                }
                            }
                        }
                    }
                    .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                }
                HStack {
                    Text("CPU \(tile.process.cpu.map { String(format: "%.1f%%", $0) } ?? "—")")
                    Spacer(minLength: 2)
                    Text("RAM \(LiveViewModel.bytes(tile.process.memory))")
                    if geometry.size.width > 360 {
                        Text("PID \(tile.id.pid)")
                    }
                }
                .font(.system(size: 11 * scale, design: .monospaced))
                .foregroundStyle(PerformanceTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                Spacer(minLength: 0)
            }
            .padding(18 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(0.8), lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tile.process.agent ?? tile.process.name), \(tile.activity.rawValue), workspace \(tile.workspace ?? "unavailable"), latest request \(tile.taskLabel ?? "unavailable"), host \(tile.host ?? "unavailable"), running \(tile.runningFor ?? "unknown"), resident RAM \(LiveViewModel.bytes(tile.process.memory))")
            .help("\(tile.activity.rawValue) · PID \(tile.id.pid) · resident family RAM estimate. Latest request is a short label from the last prompt hook, not proof of current work. Shared pages may overlap.")
        }
    }

    private func eventDescription(_ event: String) -> String {
        switch event {
        case "UserPromptSubmit": "REQUEST"
        case "PreToolUse": "TOOL START"
        case "PostToolUse": "TOOL END"
        case "PostToolUseFailure": "TOOL FAILED"
        case "PreCompact": "COMPACT START"
        case "PostCompact", "PostCompaction": "COMPACT END"
        case "PermissionRequest": "INPUT"
        case "Elicitation": "INPUT"
        case "ElicitationResult": "INPUT RECEIVED"
        case "Stop": "TURN END"
        case "StopFailure": "FAILURE"
        case "RateLimit": "RATE LIMIT"
        case "Interrupt": "INTERRUPT"
        case "SessionStart": "SESSION START"
        case "SessionEnd": "SESSION END"
        default: "SIGNAL"
        }
    }

    private func elapsed(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds >= 3_600 { return "\(seconds / 3_600)h ago" }
        if seconds >= 60 { return "\(seconds / 60)m ago" }
        return "just now"
    }

    private func weights(for tiles: [LiveViewModel.AgentWallTile]) -> [Double] {
        let memory = tiles.map { Double($0.process.memory) }.sorted()
        guard let middle = memory.dropFirst(memory.count / 2).first else { return [] }
        let cap = max(64 * 1_048_576, middle * 4)
        return tiles.map { min(cap, max(64 * 1_048_576, Double($0.process.memory))) }
    }
}

private struct AgentTileMap: Layout {
    let weights: [Double]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 900, height: proposal.height ?? 600)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let values = subviews.indices.map { $0 < weights.count ? max(1, weights[$0]) : 1 }
        var frames = [CGRect](repeating: .zero, count: subviews.count)
        func assign(_ range: Range<Int>, _ rect: CGRect) {
            guard !range.isEmpty else { return }
            if range.count == 1 { frames[range.lowerBound] = rect; return }
            let total = range.reduce(0.0) { $0 + values[$1] }
            var split = range.lowerBound + 1
            var left = values[range.lowerBound]
            while split < range.upperBound - 1 && left + values[split] <= total / 2 {
                left += values[split]
                split += 1
            }
            let fraction = CGFloat(min(0.8, max(0.2, left / total)))
            if rect.width >= rect.height {
                let first = max(0, (rect.width - spacing) * fraction)
                assign(range.lowerBound..<split, CGRect(x: rect.minX, y: rect.minY, width: first, height: rect.height))
                assign(split..<range.upperBound, CGRect(x: rect.minX + first + spacing, y: rect.minY,
                                                       width: max(0, rect.width - first - spacing), height: rect.height))
            } else {
                let first = max(0, (rect.height - spacing) * fraction)
                assign(range.lowerBound..<split, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: first))
                assign(split..<range.upperBound, CGRect(x: rect.minX, y: rect.minY + first + spacing,
                                                       width: rect.width, height: max(0, rect.height - first - spacing)))
            }
        }
        assign(0..<subviews.count, bounds)
        for index in subviews.indices {
            let rect = frames[index]
            subviews[index].place(at: rect.origin, proposal: ProposedViewSize(rect.size))
        }
    }
}

private struct AgentWallFullScreenRequest: NSViewRepresentable {
    func makeNSView(context: Context) -> FullScreenView { FullScreenView() }
    func updateNSView(_ nsView: FullScreenView, context: Context) {}

    final class FullScreenView: NSView {
        private var requested = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !requested, let window else { return }
            requested = true
            DispatchQueue.main.async { [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }
}

struct AgentHookSetupView: View {
    @State private var provider = "Codex"
    @State private var showingJSON = false
    private let providers = ["Codex", "Claude", "Devin"]

    private var configurationPath: String {
        switch provider {
        case "Claude": "~/.claude/settings.json"
        case "Devin": "~/.config/devin/config.json"
        default: "~/.codex/hooks.json"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent status hooks").font(.title2.bold())
            Text("The wall uses local lifecycle events to tell work from an idle process. Add these hooks to your existing \(configurationPath) without replacing other entries. For a prompt event, the hook derives a short latest-request label and sends it with the event, process identity and workspace name through a local macOS notification. It discards the full prompt and does not read transcripts.")
                .fixedSize(horizontal: false, vertical: true)
            Picker("Agent", selection: $provider) {
                ForEach(providers, id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            DisclosureGroup("Review hook JSON", isExpanded: $showingJSON) {
                ScrollView {
                    Text(configuration)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color.black, in: RoundedRectangle(cornerRadius: 7))
            }
            Button("Copy \(provider) hook JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(configuration, forType: .string)
            }
            Text("Keep existing settings. New events appear after the agent reloads its hooks and starts work. Older sessions may need to restart before they send events. The wall shows process families; multiple conversations in one host can share a tile. Uninstrumented terminal agents stay orange as status unavailable. Events from a shared background host stay unavailable when no terminal session owns them.")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
        }
        .padding(24)
        .frame(width: 640, height: 540)
        .background(PerformanceTheme.fog)
    }

    private var configuration: String {
        let binary = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PerformanceDaddy").path
        let quoted = "'" + binary.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let events: [String]
        switch provider {
        case "Codex":
            events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "PostCompact", "Stop", "Interrupt", "SessionEnd"]
        case "Devin":
            events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "PostCompaction", "Stop", "SessionEnd"]
        default:
            events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Elicitation", "ElicitationResult", "Notification", "PreCompact", "PostCompact", "Stop", "StopFailure", "SessionEnd"]
        }
        let hooks = Dictionary(uniqueKeysWithValues: events.map { event in
            (event, [["hooks": [["type": "command", "command": "\(quoted) --agent-hook \(provider)"]]]])
        })
        guard let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "Unable to prepare hook JSON." }
        return text
    }
}
