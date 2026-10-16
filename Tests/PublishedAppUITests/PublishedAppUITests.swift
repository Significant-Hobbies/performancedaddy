import AppKit
import XCTest

/// Runs only on an ephemeral graphical CI Mac, against the unchanged published app.
final class PublishedAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var output: URL!
    private var observations: [[String: Any]] = []

    @MainActor
    private func prepare() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard env["PD_EPHEMERAL_UI_RUNNER"] == "true",
              let path = env["PD_EXPECTED_APP_PATH"],
              let home = env["PD_PRIVATE_HOME"],
              let out = env["PD_UI_OUTPUT"],
              let bundle = Bundle(path: path),
              let identifier = bundle.bundleIdentifier else {
            throw NSError(domain: "PublishedAppUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Requires the isolated published-app harness"])
        }
        output = URL(fileURLWithPath: out)
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?
            .standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path else {
            throw NSError(domain: "PublishedAppUITests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Registered application path does not match"])
        }
        app = XCUIApplication(bundleIdentifier: identifier)
        app.launchEnvironment["CFFIXED_USER_HOME"] = home
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == identifier }
        guard running.count == 1,
              running[0].bundleURL?.standardizedFileURL.path ==
                URL(fileURLWithPath: path).standardizedFileURL.path else {
            throw NSError(domain: "PublishedAppUITests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Refuse an ambiguous running app identity"])
        }
        try record("launched", extra: ["pid": running[0].processIdentifier,
                                       "bundleIdentifier": identifier,
                                       "appPath": path])
    }

    @MainActor
    private func captureFinal() throws {
        if let app, let output {
            try app.debugDescription.write(to: output.appendingPathComponent("final-ax.txt"),
                                           atomically: true, encoding: .utf8)
            try app.screenshot().pngRepresentation.write(to: output.appendingPathComponent("final.png"))
        }
        // The outer harness stops only the exact published executable it owns.
    }

    @MainActor
    func testMinimumWindowKeepsEveryPageAndItsEssentialControlsReachable() throws {
        try prepare()
        defer { try? captureFinal() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.3,
                     thenDragTo: corner.withOffset(CGVector(dx: -600, dy: -400)))
        try record("minimum-window")
        XCTAssertEqual(window.frame.width, 980, accuracy: 2, "Measure the actual supported minimum")
        XCTAssertEqual(window.frame.height, 800, accuracy: 2, "Measure the actual supported minimum")

        let livePages = [
            ("Processes", "See what is running."),
            ("Ports", "Find a local listener"),
            ("Agent sessions", "Local coding-agent families"),
            ("Memory", "Watch memory pressure"),
        ]
        for (page, subtitle) in livePages {
            try open(page, window: window)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", subtitle))
                .firstMatch.waitForExistence(timeout: 10), page)
            try reachable(app.textFields["Search processes, projects and ports"], window: window)
            for title in ["Pause", "Refresh processes", "Help with processes and measurements", "Stop…"] {
                try reachable(app.descendants(matching: .any).matching(identifier: title).firstMatch,
                              window: window)
            }
            try capture(page)
        }
        try open("Fans & heat", window: window)
        try reachable(app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] 'record ' AND label CONTAINS[c] 'fan check'"
        )).firstMatch, window: window)
        try capture("Fans & heat")
        try open("App access", window: window)
        try reachable(app.textFields["Search app access audit"], window: window)
        try reachable(app.buttons["Review Login Items"], window: window)
        try reachable(app.buttons["Refresh audit"], window: window)
        try capture("App access")
        try open("Configuration", window: window)
        try reachable(app.textFields["Search configuration files"], window: window)
        try reachable(app.buttons["Refresh"], window: window)
        try capture("Configuration")
        try open("Diagnose", window: window)
        try reachable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Start '"))
            .firstMatch, window: window)
        try reachable(app.buttons["Diagnose terminal startup…"], window: window)
        try capture("Diagnose")
        try record("completed", extra: ["pages": 8])
    }

    @MainActor
    private func open(_ title: String, window: XCUIElement) throws {
        let button = app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        try reachable(button, window: window)
        button.click()
        try record("opened", extra: ["page": title])
    }

    @MainActor
    private func reachable(_ element: XCUIElement, window: XCUIElement) throws {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed,
                       "Control must exist and be hittable: \(element)")
        XCTAssertGreaterThan(element.frame.width, 0)
        XCTAssertGreaterThan(element.frame.height, 0)
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                      "Control must fit fully inside the minimum window: \(element)")
    }

    @MainActor
    private func capture(_ page: String) throws {
        let name = page.lowercased().replacingOccurrences(of: " ", with: "-")
        try app.screenshot().pngRepresentation.write(to: output.appendingPathComponent("\(name).png"))
        try app.debugDescription.write(to: output.appendingPathComponent("\(name)-ax.txt"),
                                       atomically: true, encoding: .utf8)
        try record("page-qualified", extra: ["page": page])
    }

    @MainActor
    private func record(_ stage: String, extra: [String: Any] = [:]) throws {
        var observation = extra
        observation["stage"] = stage
        observation["timestamp"] = Date().timeIntervalSince1970
        if let frame = app?.windows.firstMatch.frame {
            observation["window"] = ["x": frame.minX, "y": frame.minY,
                                     "width": frame.width, "height": frame.height]
        }
        observations.append(observation)
        let data = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("ui-observations.json"), options: .atomic)
    }
}
