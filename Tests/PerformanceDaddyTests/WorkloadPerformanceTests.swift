import Foundation
@testable import PerformanceCore
@testable import PerformanceDaddy
import XCTest

/// Fixed synthetic input makes before/after CPU work comparable. This measures
/// derivation, not whole-app energy use or SwiftUI frame rendering.
@MainActor
final class WorkloadPerformanceTests: XCTestCase {
    func testSnapshotDerivationPerformance() {
        let date = Date(timeIntervalSince1970: 1_000)
        let processes = (0..<1_000).map { offset in
            let name = offset.isMultiple(of: 20) ? "codex" : "worker-\(offset)"
            return LiveProcess(id: .init(pid: Int32(offset + 100), started: UInt64(offset + 1)),
                parent: 1, uid: getuid(), name: name, executable: "/opt/developer/tools/\(name)",
                directory: "/Users/example/Projects/project-\(offset % 20)", cpu: Double(offset % 100),
                memory: UInt64(offset + 1) * 1_048_576,
                hasControllingTerminal: name == "codex")
        }
        let snapshot = LiveSnapshot(date: date, processes: processes,
            system: .init(timestamp: date, usedCPUCores: 1, memoryHeadroomRatio: 0.5,
                swapUsedBytes: 0, diskFreeBytes: nil, thermal: .nominal, processes: []),
            pressure: "Normal", compressed: nil, unavailableProcesses: 0, portsDate: date, scanSeconds: 0.01)
        let model = LiveViewModel()
        model.sortOrder = [KeyPathComparator(\LiveProcess.sortName)]
        measure {
            model.snapshot = snapshot
            XCTAssertEqual(model.rows(for: .workloads).count, 1_000)
            XCTAssertEqual(model.rows(for: .agents).count, 50)
            XCTAssertEqual(model.agentCount, 50)
            for process in model.rows(for: .workloads) {
                XCTAssertFalse(LiveViewModel.bytes(process.memory).isEmpty)
            }
        }
    }
}
