import AppKit
@testable import PerformanceCore
import SwiftUI
@testable import PerformanceDaddy
import XCTest

@MainActor
final class DesignEvidenceTests: XCTestCase {
    func testAgentWallFitsViewportWithoutScrollAtSparseAndDenseCounts() throws {
        for count in [1, 6, 20] {
            let model = LiveViewModel()
            let date = Date()
            let started = UInt64((date.timeIntervalSince1970 - 180) * 1_000_000)
            let processes: [LiveProcess] = (0..<count).map { index in
                let identity = ProcessIdentity(pid: Int32(30_000 + index), started: started)
                let directory = "/Users/example/project-\(index)"
                let cpu = Double(index)
                let memory: UInt64 = UInt64(100 + index * 10) * 1_048_576
                return LiveProcess(id: identity, parent: 1, uid: getuid(), name: "codex",
                                   executable: "/opt/bin/codex", directory: directory, cpu: cpu,
                                   memory: memory, hasControllingTerminal: true)
            }
            let system = SystemSample(timestamp: date, usedCPUCores: 1, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                                      diskFreeBytes: nil, thermal: .nominal, processes: [])
            model.snapshot = LiveSnapshot(date: date, processes: processes, system: system, pressure: "Normal", compressed: 0, unavailableProcesses: 0, portsDate: date, scanSeconds: 0.01)
            for (index, process) in processes.enumerated() {
                let event = ["UserPromptSubmit", "Stop", "PermissionRequest"][index % 3]
                model.recordAgentSignal(try XCTUnwrap(AgentWallSignal(userInfo: [
                    "pid": NSNumber(value: process.id.pid), "started": NSNumber(value: started), "provider": "Codex",
                    "event": event, "timestamp": NSNumber(value: date.timeIntervalSince1970),
                    "taskLabel": "Verify the agent session and memory changes for project \(index)"
                ])))
            }
            let size = NSSize(width: 1_440, height: 900)
            let view = NSHostingView(rootView: AgentWallView(model: model, requestsFullScreen: false).frame(width: size.width, height: size.height))
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            func hasScrollView(_ node: NSView) -> Bool { node is NSScrollView || node.subviews.contains(where: hasScrollView) }
            XCTAssertFalse(hasScrollView(view))
            XCTAssertEqual(model.agentWallTiles.count, count)
            let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: representation)
            XCTAssertEqual(representation.size, size)
            if let output = ProcessInfo.processInfo.environment["PERFORMANCEDADDY_DESIGN_OUTPUT"] {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("agent-wall-\(count).png"), options: .atomic)
            }
        }
    }

    func testFanInvestigationRendersSetupAndUnavailableEvidenceAtNativeSizes() throws {
        for width: CGFloat in [760, 1_220] {
            for hasReport in [false, true] {
                let model = DiagnosisViewModel()
                if hasReport {
                    let start = Date(timeIntervalSince1970: 0)
                    let samples = (0..<12).map { index in
                        SystemSample(timestamp: start.addingTimeInterval(Double(index)), usedCPUCores: 4,
                                     memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil,
                                     thermal: .fair, processes: [],
                                     workloads: [.init(id: "browser", name: "Browser & helpers", association: "App bundle path association", cpuCores: 3, processCount: 8)])
                    }
                    model.review(DiagnosticEngine().analyze(.init(startedAt: start, endedAt: start.addingTimeInterval(12), samples: samples, isFixture: true)))
                }
                let view = NSHostingView(rootView: FanInvestigationView(model: model)
                    .frame(width: width, height: 800))
                view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
                let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: representation)
                XCTAssertEqual(representation.size.width, width)
                XCTAssertEqual(representation.size.height, 800)
                if let output = ProcessInfo.processInfo.environment["PERFORMANCEDADDY_DESIGN_OUTPUT"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent("fan-\(hasReport ? "report" : "setup")-content-\(Int(width)).png"), options: .atomic)
                }
            }
        }
    }
    func testDashboardRendersAtSupportedNativeSizes() throws {
        let outputDirectory = ProcessInfo.processInfo.environment["PERFORMANCEDADDY_DESIGN_OUTPUT"]
        let specifications: [(label: Int, width: CGFloat, height: CGFloat)] = outputDirectory == nil
            ? [(390, 980, 800)]
            : [(390, 980, 800), (768, 1_096, 768), (1_440, 1_440, 900)]

        for specification in specifications {
            let model = LiveViewModel()
            model.snapshot = fixtureSnapshot()
            let view = NSHostingView(
                rootView: DashboardView(model: DiagnosisViewModel(), live: model)
                    .frame(width: specification.width, height: specification.height)
            )
            view.frame = NSRect(x: 0, y: 0, width: specification.width, height: specification.height)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: representation)
            XCTAssertEqual(representation.size.width, specification.width)
            XCTAssertEqual(representation.size.height, specification.height)

            guard let outputDirectory else { continue }
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("after-\(specification.label).png"), options: .atomic)
        }
    }

    private func fixtureSnapshot() -> LiveSnapshot {
        let date = Date()
        let started = UInt64((date.timeIntervalSince1970 - 4_200) * 1_000_000)
        let processes = [
            LiveProcess(
                id: .init(pid: 4_201, started: started), parent: 1, uid: getuid(), name: "codex",
                executable: "/opt/homebrew/bin/codex", directory: "/Users/example/project",
                cpu: 18.4, memory: 482_000_000,
                ports: [.init(port: 3_000, transport: "TCP", address: "127.0.0.1", loopback: true)]
            ),
            LiveProcess(
                id: .init(pid: 4_202, started: started + 300_000_000), parent: 1, uid: getuid(), name: "BrowserDaddy",
                executable: "/Applications/BrowserDaddy.app/Contents/MacOS/BrowserDaddy", directory: "/",
                cpu: 3.1, memory: 228_000_000
            ),
            LiveProcess(
                id: .init(pid: 4_203, started: started + 600_000_000), parent: 1, uid: getuid(), name: "Xcode",
                executable: "/Applications/Xcode.app/Contents/MacOS/Xcode", directory: "/Users/example/project",
                cpu: 1.8, memory: 1_240_000_000
            ),
        ]
        let system = SystemSample(
            timestamp: date, usedCPUCores: 2.1, memoryHeadroomRatio: 0.42,
            swapUsedBytes: 0, diskFreeBytes: 512_000_000_000, thermal: .nominal,
            processes: []
        )
        return LiveSnapshot(
            date: date, processes: processes, system: system, pressure: "Normal",
            compressed: 1_100_000_000, unavailableProcesses: 0, portsDate: date, scanSeconds: 0.04
        )
    }
}
