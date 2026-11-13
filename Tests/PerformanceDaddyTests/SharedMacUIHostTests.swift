import AppKit
@testable import PerformanceCore
import SaaSMakerUI
import SwiftUI
import XCTest
@testable import PerformanceDaddy

/// Opt-in visible production page for coordinated screenshots, without live collection.
@MainActor
final class SharedMacUIHostTests: XCTestCase {
    func testHoldProtectedFixturePageForNativeReview() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PERFORMANCEDADDY_UI_HOST"] == "1" else {
            throw XCTSkip("Opt-in visible UI host; no live collectors or process actions")
        }
        let path = try XCTUnwrap(environment["PERFORMANCEDADDY_UI_HOST_READY"])
        XCTAssertTrue(path.hasPrefix("/"), "Use a new absolute ready-file path")
        guard path.hasPrefix("/") else { return }
        let ready = URL(fileURLWithPath: path)
        let done = URL(fileURLWithPath: path + ".done")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ready.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: done.path))
        guard !FileManager.default.fileExists(atPath: ready.path),
              !FileManager.default.fileExists(atPath: done.path) else { return }
        let page = try XCTUnwrap(LivePage(rawValue: environment["PERFORMANCEDADDY_UI_HOST_PAGE"] ?? "Processes"))
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let fonts = Bundle(url: products.appendingPathComponent("SaaSMakerUI_SaaSMakerUI.bundle"))
        XCTAssertTrue(PerformanceUIResources.registerFonts(in: fonts), "Review uses the actual bundled typefaces")
        let width = Double(environment["PERFORMANCEDADDY_UI_HOST_WIDTH"] ?? "960") ?? 960
        XCTAssertTrue((880...1_440).contains(width), "Keep the fixture host within supported review widths")
        guard (880...1_440).contains(width) else { return }
        let snapshot = fixtureSnapshot()
        XCTAssertTrue(snapshot.processes.allSatisfy { $0.stopRestriction != nil })

        let suite = "com.significanthobbies.performancedaddy.ui-host.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("performance-ui-host-\(UUID().uuidString)")
        let sampler = ProtectedFixtureSampler(snapshot: snapshot)
        let model = LiveViewModel(lifecycleStore: LifecycleHistoryStore(fileURL: fixtureDirectory.appendingPathComponent("lifecycle.json")),
                                  sampler: sampler, preferences: preferences)
        model.paused = true
        model.includeSystem = true
        model.snapshot = snapshot
        if environment["PERFORMANCEDADDY_UI_HOST_SELECTED"] == "1" {
            model.selection = [snapshot.processes[0].id]
        }
        let host = NSHostingView(rootView: DashboardView(model: DiagnosisViewModel(), live: model,
            initialDestination: page.rawValue, startsServices: false)
            .performanceTheme(PerformanceTheme.palette)
            .buttonStyle(SMMacButtonStyle()))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "PerformanceDaddy UI host · protected fixtures · \(page.rawValue)"
        window.contentMinSize = NSSize(width: 880, height: 680)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentView = host
        let activationPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            NSApplication.shared.setActivationPolicy(activationPolicy)
            preferences.removePersistentDomain(forName: suite)
            if FileManager.default.fileExists(atPath: fixtureDirectory.path) {
                try? FileManager.default.removeItem(at: fixtureDirectory)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let metadata: [String: Any] = [
            "pid": getpid(), "windowNumber": window.windowNumber, "title": window.title,
            "page": page.rawValue, "fixtureProcesses": snapshot.processes.count,
            "contentWidth": width,
            "allProcessActionsProtected": true, "liveSamplingStarted": false,
            "scope": "Full production dashboard with protected fixture processes; services disabled",
            "holdSeconds": 120, "donePath": done.path
        ]
        try FileManager.default.createDirectory(at: ready.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: ready, options: .withoutOverwriting)
        holdNativeEventLoop(until: done)
        let calls = await sampler.sampleCalls
        XCTAssertEqual(calls, 0, "The visual host must not start sampling")
        XCTAssertNil(model.review)
        XCTAssertTrue(model.outcomes.isEmpty)
    }

    /// Accessibility needs AppKit's event loop, not only an async XCTest delay.
    private func holdNativeEventLoop(until done: URL) {
        let deadline = Date().addingTimeInterval(120)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard FileManager.default.fileExists(atPath: done.path) || Date() >= deadline else { return }
                NSApplication.shared.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                    NSApplication.shared.postEvent(event, atStart: false)
                }
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
        timer.invalidate()
    }

    private func fixtureSnapshot() -> LiveSnapshot {
        let date = Date()
        let started = UInt64((date.timeIntervalSince1970 - 4_200) * 1_000_000)
        let protectedUID = UInt32.max
        var processes = [
            LiveProcess(id: .init(pid: 30_001, started: started), parent: 1, uid: protectedUID, name: "codex",
                        executable: "/opt/bin/codex", directory: "/Users/example/fleet", cpu: 18.4, memory: 482_000_000,
                        hasControllingTerminal: true,
                        ports: [.init(port: 3_000, transport: "TCP", address: "127.0.0.1", loopback: true)]),
            LiveProcess(id: .init(pid: 30_002, started: started + 300_000_000), parent: 1, uid: protectedUID,
                        name: "BrowserDaddy", executable: "/Applications/BrowserDaddy.app/Contents/MacOS/BrowserDaddy",
                        directory: "/", cpu: 3.1, memory: 228_000_000),
            LiveProcess(id: .init(pid: 30_003, started: started + 600_000_000), parent: 1, uid: protectedUID,
                        name: "Xcode", executable: "/Applications/Xcode.app/Contents/MacOS/Xcode",
                        directory: "/Users/example/fleet", cpu: 1.8, memory: 1_240_000_000)
        ]
        if let text = ProcessInfo.processInfo.environment["PERFORMANCEDADDY_UI_HOST_ROWS"],
           let count = Int(text), (4...1_500).contains(count) {
            processes += (3..<count).map { index in
                LiveProcess(id: .init(pid: Int32(30_001 + index), started: started + UInt64(index) * 1_000_000),
                            parent: 1, uid: protectedUID, name: "Protected fixture \(index + 1)",
                            executable: "/fixtures/process-\(index + 1)", directory: "/fixtures/workspace-\(index + 1)",
                            cpu: Double(index % 25) / 10, memory: UInt64(10 + index % 100) * 1_000_000)
            }
        }
        let system = SystemSample(timestamp: date, usedCPUCores: 2.1, memoryHeadroomRatio: 0.42,
                                  swapUsedBytes: 0, diskFreeBytes: 512_000_000_000, thermal: .nominal, processes: [])
        return LiveSnapshot(date: date, processes: processes, system: system, pressure: "Normal", compressed: 1_100_000_000,
                            unavailableProcesses: 0, portsDate: date, scanSeconds: 0.04)
    }
}

private actor ProtectedFixtureSampler: LiveWorkloadSampling {
    let snapshot: LiveSnapshot
    private(set) var sampleCalls = 0
    init(snapshot: LiveSnapshot) { self.snapshot = snapshot }
    func resetMeasurementWindow() async {}
    func sample(includePorts: Bool) async -> LiveSnapshot {
        sampleCalls += 1
        return snapshot
    }
}
