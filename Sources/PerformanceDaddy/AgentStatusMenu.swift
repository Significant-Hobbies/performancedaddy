import AppKit
import PerformanceCore
import SwiftUI

struct AgentMenuSummary {
    let working: Int
    let attention: Int
    let failed: Int
    let total: Int

    init(activities: [AgentWallActivity]) {
        total = activities.count
        working = activities.filter { $0 == .working }.count
        attention = activities.filter { $0 == .waiting || $0 == .stopped || $0 == .unavailable }.count
        failed = activities.filter { $0 == .failed }.count
    }

    var accessibilityLabel: String {
        "Agent sessions: \(total) live, \(working) working, \(attention) need input, stopped, or status unavailable, \(failed) failed"
    }
}

struct AgentStatusMenuBarLabel: View {
    @ObservedObject var model: LiveViewModel

    var body: some View {
        let summary = AgentMenuSummary(activities: model.agentWallTiles.map(\.activity))
        Image(nsImage: AgentStatusMark.image(for: summary))
        .renderingMode(.original)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .help(summary.accessibilityLabel)
    }
}

@MainActor
private enum AgentStatusMark {
    static func image(for summary: AgentMenuSummary) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let count = String(summary.total)
        let countWidth = (count as NSString).size(withAttributes: attributes).width
        let exactMarks = summary.total <= 12
        let marksWidth = exactMarks ? CGFloat(max(0, summary.total * 6 - 2)) : 44
        let bodyWidth = max(30, 8 + countWidth + (summary.total == 0 ? 0 : 8 + marksWidth) + 8)
        let totalWidth = bodyWidth + 4
        let image = NSImage(size: NSSize(width: totalWidth, height: 20), flipped: false) { rect in
            NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.11, alpha: 0.96).setFill()
            let body = NSRect(x: 0, y: 1, width: bodyWidth, height: 18)
            NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6).fill()
            NSColor(calibratedRed: 0.25, green: 0.34, blue: 0.29, alpha: 1).setStroke()
            NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
            NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.39, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: bodyWidth + 1, y: 7, width: 3, height: 6), xRadius: 1, yRadius: 1).fill()
            let colors = [
                NSColor(calibratedRed: 0.42, green: 0.79, blue: 0.62, alpha: 1),
                NSColor(calibratedRed: 0.87, green: 0.67, blue: 0.28, alpha: 1),
                NSColor(calibratedRed: 0.90, green: 0.46, blue: 0.40, alpha: 1)
            ]
            (count as NSString).draw(at: NSPoint(x: 8, y: 3), withAttributes: attributes)
            var x = 8 + countWidth + 8
            let counts = [summary.working, summary.attention, summary.failed]
            if exactMarks {
                for index in counts.indices {
                    colors[index].setFill()
                    for _ in 0..<counts[index] {
                        NSBezierPath(roundedRect: NSRect(x: x, y: 5, width: 4, height: 10), xRadius: 2, yRadius: 2).fill()
                        x += 6
                    }
                }
            } else {
                for index in counts.indices where counts[index] > 0 {
                    let width = marksWidth * CGFloat(counts[index]) / CGFloat(summary.total)
                    colors[index].setFill()
                    NSRect(x: x, y: 5, width: width, height: 10).fill()
                    x += width
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct AgentStatusMenu: View {
    @ObservedObject var model: LiveViewModel
    @ObservedObject var updates: AppUpdates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let tiles = model.agentWallTiles
        let summary = AgentMenuSummary(activities: tiles.map(\.activity))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIVE SIGNAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(PerformanceTheme.mintInk)
                    Text("\(summary.total) live \(summary.total == 1 ? "session" : "sessions")")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(PerformanceTheme.ink)
                }
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PerformanceTheme.divider))
            }
            .padding(.bottom, 17)

            AgentStatusDistribution(summary: summary)
            HStack(spacing: 10) {
                countLabel("WORKING", count: summary.working, color: PerformanceTheme.mintInk)
                countLabel("ATTENTION", count: summary.attention, color: PerformanceTheme.amber)
                countLabel("FAILED", count: summary.failed, color: PerformanceTheme.coral)
            }
            .padding(.top, 10).padding(.bottom, 17)

            Rectangle().fill(PerformanceTheme.divider).frame(height: 1)
            if tiles.isEmpty {
                Text("No live agent sessions")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 118)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        AgentStatusSection(title: "Working", color: PerformanceTheme.mintInk,
                                           tiles: tiles.filter { $0.activity == .working })
                        AgentStatusSection(title: "Attention", color: PerformanceTheme.amber,
                                           tiles: tiles.filter { $0.activity == .waiting || $0.activity == .stopped || $0.activity == .unavailable })
                        AgentStatusSection(title: "Failed", color: PerformanceTheme.coral,
                                           tiles: tiles.filter { $0.activity == .failed })
                    }
                    .padding(.vertical, 15)
                }
                .frame(maxHeight: 390)
                .scrollIndicators(.automatic)
            }
            Rectangle().fill(PerformanceTheme.divider).frame(height: 1)

            HStack(spacing: 10) {
                Button("Open Agent Sessions") { open(id: "agent-wall") }
                    .buttonStyle(DaddyButtonStyle(prominent: true))
                Button("Open App") { open(id: "main") }
                    .buttonStyle(DaddyButtonStyle())
                Spacer(minLength: 0)
                Menu {
                    Button(model.paused ? "Resume monitoring" : "Pause monitoring") { model.paused.toggle() }
                    Button("Check for Updates…") { updates.check() }
                        .disabled(!updates.canCheck || !updates.isIdle)
                    Divider()
                    Button("Quit PerformanceDaddy") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More PerformanceDaddy controls")
            }
            .padding(.top, 15)
            VStack(alignment: .leading, spacing: 3) {
                Text("RAM estimate \(model.usedMemory) · Pressure \(model.snapshot?.pressure ?? "Measuring")")
                Text("\(model.portCount) open sockets · \(model.agentCount) agent processes")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(PerformanceTheme.secondaryInk)
            .padding(.top, 14)
        }
        .padding(16)
        .frame(width: 380)
        .background(PerformanceTheme.fog)
        .preferredColorScheme(.dark)
        .task { model.start() }
    }

    private func countLabel(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").foregroundStyle(color).bold()
            Text(title).foregroundStyle(PerformanceTheme.secondaryInk)
        }
        .font(.system(size: 10, design: .monospaced))
    }

    private func open(id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct AgentStatusDistribution: View {
    let summary: AgentMenuSummary

    var body: some View {
        GeometryReader { geometry in
            let segments: [(Int, Color)] = [
                (summary.working, PerformanceTheme.mintInk),
                (summary.attention, PerformanceTheme.amber),
                (summary.failed, PerformanceTheme.coral)
            ].filter { $0.0 > 0 }
            let width = max(0, geometry.size.width - CGFloat(max(0, segments.count - 1)) * 4)
            HStack(spacing: 4) {
                if segments.isEmpty {
                    Capsule().fill(PerformanceTheme.secondaryInk.opacity(0.35))
                } else {
                    ForEach(segments.indices, id: \.self) { index in
                        Capsule().fill(segments[index].1)
                            .frame(width: width * CGFloat(segments[index].0) / CGFloat(summary.total))
                    }
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

private struct AgentStatusSection: View {
    let title: String
    let color: Color
    let tiles: [LiveViewModel.AgentWallTile]

    var body: some View {
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(title.uppercased())
                        .tracking(1)
                    Spacer()
                    Text("\(tiles.count)")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                ForEach(tiles) { tile in AgentStatusRow(tile: tile, color: color) }
            }
        }
    }
}

private struct AgentStatusRow: View {
    let tile: LiveViewModel.AgentWallTile
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tile.process.agent ?? tile.process.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PerformanceTheme.ink)
                    Spacer()
                    Text(tile.activity.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                Text(tile.workspace ?? "Workspace unavailable")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .lineLimit(1)
                Text(tile.taskLabel ?? "Latest request unavailable")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(tile.taskLabel == nil ? PerformanceTheme.secondaryInk.opacity(0.7) : PerformanceTheme.ink)
                    .lineLimit(2)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PerformanceTheme.mint.opacity(0.33), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PerformanceTheme.divider))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.process.agent ?? tile.process.name), \(tile.activity.rawValue), workspace \(tile.workspace ?? "unavailable"), latest request \(tile.taskLabel ?? "unavailable")")
    }
}
