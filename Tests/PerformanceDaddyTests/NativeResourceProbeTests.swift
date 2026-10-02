import AppKit
import NativeInspection
@testable import PerformanceCore
import SwiftUI
@testable import PerformanceDaddy
import XCTest

/// Opt-in measurement, not a memory-budget assertion or installed-app test.
/// Run in a fresh Release test process for every candidate being compared.
@MainActor
final class NativeResourceProbeTests: XCTestCase {
    func testRenderedProcessAndMemoryPagesFootprint() throws {
        guard ProcessInfo.processInfo.environment["PERFORMANCEDADDY_RESOURCE_PROBE"] == "1" else {
            throw XCTSkip("Opt-in native memory measurement; use scripts/measure-native-pages.py")
        }
        let model = LiveViewModel()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let processes: [LiveProcess] = (0..<512).map { i in
            let agent = i % 8 == 0
            let ports: [ListeningPort] = i % 10 == 0
                ? [.init(port: UInt16(3_000 + i), transport: "TCP", address: "127.0.0.1", loopback: true)] : []
            return LiveProcess(id: .init(pid: Int32(30_000 + i), started: 1_700_000_000_000_000), parent: 1, uid: getuid(),
                               name: agent ? "codex" : "worker", executable: agent ? "/opt/bin/codex" : "/Applications/PerformanceDaddy.app/Contents/MacOS/PerformanceDaddy",
                               directory: "/Users/example/project-\(i % 16)", cpu: Double(i % 20), memory: UInt64(i + 1) * 1_048_576,
                               hasControllingTerminal: agent, ports: ports)
        }
        let system = SystemSample(timestamp: date, usedCPUCores: 2, memoryHeadroomRatio: 0.5, swapUsedBytes: 0,
                                  diskFreeBytes: nil, thermal: .nominal, processes: [])
        model.snapshot = LiveSnapshot(date: date, processes: processes, system: system, pressure: "Normal", compressed: 0,
                                      unavailableProcesses: 0, portsDate: date, scanSeconds: 0.02)
        model.memoryHistory = (0..<30).map { .init(date: date.addingTimeInterval(Double($0 * 10)), used: 0.4 + Double($0 % 5) * 0.01) }
        _ = PerformanceAppIcon.image
        let size = NSSize(width: 1_180, height: 800)
        let view = NSHostingView(rootView: LiveWorkloadsView(model: model, page: .workloads).frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        record("initialized")
        for (stage, page) in [("processes", LivePage.workloads), ("memory", .memory), ("processes-after-memory", .workloads)] {
            view.rootView = LiveWorkloadsView(model: model, page: page).frame(width: size.width, height: size.height)
            autoreleasepool {
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
            }
            record(stage)
        }
        window.contentView = nil
        record("content-detached")
    }

    private func record(_ stage: String) {
        var raw = PDProcess()
        XCTAssertEqual(pd_process(getpid(), &raw), 1)
        print("NATIVE_RESOURCE_PROBE \(stage) resident=\(raw.memory) footprint=\(raw.footprint)")
    }
}
