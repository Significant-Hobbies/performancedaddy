import AppKit
import SwiftUI
import XCTest
@testable import PerformanceCore
@testable import PerformanceDaddy

@MainActor final class IncidentDesignEvidenceTests: XCTestCase {
    func testMarkedIncidentAndProfileImportRenderAtNativeWidths() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/incident-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1000)
        let hardware = HardwareEvidence(fans: [.init(name: "Fan 1", rpm: 3200, maximumRPM: 5300), .init(name: "Fan 2", rpm: 3500, maximumRPM: 5800)], cpuSensorMaximumCelsius: 73, gpuSensorMaximumCelsius: 59, cpuSensorCount: 23, gpuSensorCount: 42, gpuUtilizationPercent: 76, source: "Fixture readings — no live machine data")
        let agent = LiveProcess(id: .init(pid: 4201, started: 100), parent: 1, uid: getuid(), name: "claude", executable: "/tmp/claude", directory: "/Users/example/project", cpu: 210, memory: 800000000, footprint: 700000000)
        var builder = SnapshotEvidenceBuilder()
        let samples = (0..<4).map { i in
            let time = date.addingTimeInterval(Double(i) * 5)
            let base = SystemSample(timestamp: time, usedCPUCores: 4, memoryHeadroomRatio: 0.44, swapUsedBytes: 0, diskFreeBytes: 200000000000, thermal: .nominal, processes: [])
            return builder.sample(LiveSnapshot(date: time, processes: [agent], system: base, pressure: "Normal", compressed: nil, unavailableProcesses: 2, portsDate: .distantPast, scanSeconds: 0.03, hardware: hardware)).withResponsiveness(.init(windowStartedAt: time.addingTimeInterval(-5), windowEndedAt: time,
                heartbeatCount: 5, heartbeatMaximumMilliseconds: 145, localEventCount: 3, localEventMaximumMilliseconds: 86,
                appProbe: .init(date: time, app: "Xcode", bundleID: "com.apple.dt.Xcode", version: "27", status: .replied, milliseconds: 138)))
        }
        let capture = DiagnosticCapture(startedAt: date, endedAt: date.addingTimeInterval(15), samples: samples, isFixture: true, marker: .init(date: date.addingTimeInterval(5), symptom: "Whole Mac felt slow", foreground: .init(name: "Chrome", bundleID: "com.google.Chrome", observedAt: date)))
        let profile = try ProfileImporter.parse(Data("Call graph:\n    10 Thread_0: Main Thread\n    + 10 applicationAction\n    + ! 10 semaphore_wait_trap\n".utf8))
        let followUp = capture.withFollowUp(.init(baseline: .init(capture), task: "Switch between Safari and Xcode", change: .paused, changeDetail: "Paused the project test runner", sameTaskConfirmed: true, outcome: .better))
        for width: CGFloat in [980,1180,1440] {
            let model = DiagnosisViewModel(); model.review(DiagnosticEngine().analyze(capture))
            let live = LiveViewModel()
            let after = DiagnosisViewModel(); after.review(DiagnosticEngine().analyze(followUp))
            let views: [(String, AnyView)] = [("incident",AnyView(DashboardView(model: model, live: live, initialDestination: "Diagnose"))), ("follow-up",AnyView(DashboardView(model: after, live: live, initialDestination: "Diagnose"))), ("prepare",AnyView(FollowUpPreparationView(report: DiagnosticEngine().analyze(capture), onCancel: {}, onRecord: { _,_,_,_ in }))), ("hardware",AnyView(FanInvestigationView(model: model, hardware: hardware))), ("stacks",AnyView(ImportedProfileView(profile: profile)))]
            for (name,root) in views {
                let view = NSHostingView(rootView: root.frame(width: width,height: 900).performanceTheme(PerformanceTheme.palette).buttonStyle(DaddyButtonStyle()))
                view.frame = NSRect(x: 0,y: 0,width: width,height: 900)
                let window = NSWindow(contentRect: view.frame,styleMask: .borderless,backing: .buffered,defer: false)
                window.contentView = view; view.layoutSubtreeIfNeeded()
                let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds,to: image)
                XCTAssertEqual(image.size.width,width)
                let png = try XCTUnwrap(image.representation(using: .png,properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(name)-\(Int(width)).png"),options: .atomic)
            }
        }
    }
}
