import Foundation
import XCTest
@testable import PerformanceCore

final class DiagnosticCaptureScopeTests: XCTestCase {
    func testOlderCaptureWithoutScopeStillDecodes() throws {
        let data = Data(#"{"startedAt":0,"endedAt":2,"samples":[],"isFixture":false}"#.utf8)
        let capture = try JSONDecoder().decode(DiagnosticCapture.self, from: data)
        XCTAssertNil(capture.processScope)
    }

    func testSelectedProcessScopeSurvivesJSONAndAppearsInAnalysisCoverage() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let scope = DiagnosticProcessScope(
            coverage: .selectedSameUserPIDs,
            selectedPIDCount: 2,
            readableProcessSamples: 3,
            unavailableProcessSamples: 1,
            statement: "Other processes are unobserved; not whole-Mac process coverage.")
        let capture = DiagnosticCapture(startedAt: date, endedAt: date, samples: [], processScope: scope)
        let decoded = try JSONDecoder().decode(DiagnosticCapture.self, from: JSONEncoder().encode(capture))
        XCTAssertEqual(decoded.processScope, scope)
        let analysis = DiagnosticEngine().analyze(decoded).rootCauseAnalysis
        XCTAssertTrue(analysis.coverage.contains("Other processes are unobserved"))
        XCTAssertTrue(analysis.limitations.contains("Other processes are unobserved"))
    }
}
