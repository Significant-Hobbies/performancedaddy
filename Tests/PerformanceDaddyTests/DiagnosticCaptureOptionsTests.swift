import XCTest
@testable import PerformanceDaddy

final class DiagnosticCaptureOptionsTests: XCTestCase {
    func testLegacyDiagnosticOptionsKeepSystemEnumerationDefault() {
        let options = DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json"])
        XCTAssertEqual(options, DiagnosticCaptureOptions(duration: 10, outputPath: "/tmp/capture.json", selectedSameUserPIDs: nil))
        XCTAssertTrue(options?.includesForegroundEvidence == true)
    }

    func testExplicitPIDsAreRepeatableAndBounded() {
        let options = DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json", "--pid", "123", "--pid", "456"])
        XCTAssertEqual(options?.selectedSameUserPIDs, [123, 456])
        XCTAssertFalse(options?.includesForegroundEvidence ?? true)
        XCTAssertNil(DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json", "--pid", "0"]))
        XCTAssertNil(DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json", "--pid", "-1"]))
        XCTAssertNil(DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "3", "--pid"]))
        XCTAssertNil(DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json", "--pid", "123", "--pid", "123"]))

        let tooMany = (1...17).flatMap { ["--pid", String($0)] }
        XCTAssertNil(DiagnosticCaptureOptions.parse(arguments: ["--capture-diagnostic", "10", "/tmp/capture.json"] + tooMany))
    }

    func testPIDOptionRequiresDiagnosticCommand() {
        XCTAssertTrue(DiagnosticCaptureOptions.hasPIDOption(["--pid", "123"]))
        XCTAssertTrue(DiagnosticCaptureOptions.hasPIDOption(["--pid=123"]))
        XCTAssertFalse(DiagnosticCaptureOptions.hasPIDOption(["--check-ui-resources"]))
        XCTAssertTrue(DiagnosticCaptureOptions.usage.contains("not establish whole-Mac process coverage"))
    }
}
