import AppKit
import XCTest

/// Runs against one exact isolated bundle; local runs require a private source candidate.
final class PublishedAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var output: URL!
    private var observations: [[String: Any]] = []
    private var minimumWindow: CGRect!

    override func tearDown() async throws {
        try await MainActor.run { try captureFinal(attach: true) }
    }

    @MainActor
    private func prepare() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let localOwned = env["PD_LOCAL_OWNED_UI_RUNNER"] == "true"
        guard env["PD_EPHEMERAL_UI_RUNNER"] == "true" || localOwned,
              let path = env["PD_EXPECTED_APP_PATH"],
              let home = env["PD_PRIVATE_HOME"],
              let out = env["PD_UI_OUTPUT"],
              let bundle = Bundle(path: path),
              let identifier = bundle.bundleIdentifier else {
            throw NSError(domain: "PublishedAppUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Requires the isolated published-app harness"])
        }
        output = URL(fileURLWithPath: out)
        if localOwned {
            let outputPath = output.resolvingSymlinksInPath()
            guard identifier == env["PD_EXPECTED_APP_BUNDLE_IDENTIFIER"],
                  identifier.hasPrefix("com.significanthobbies.performancedaddy.qualification.r"),
                  URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent() == outputPath,
                  URL(fileURLWithPath: home).resolvingSymlinksInPath().deletingLastPathComponent() == outputPath,
                  NSWorkspace.shared.runningApplications.allSatisfy({ $0.bundleIdentifier != identifier }) else {
                throw NSError(domain: "PublishedAppUITests", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Local runs require a new private candidate, private home and no existing candidate process"])
            }
            // The signed runner stays sandboxed. Transport evidence through
            // XCTest attachments instead of granting access to the checkout.
            output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
        }
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
    private func captureFinal(attach: Bool = false) throws {
        if let app, let output {
            try app.debugDescription.write(to: output.appendingPathComponent("final-ax.txt"),
                                           atomically: true, encoding: .utf8)
            try app.windows.firstMatch.screenshot().pngRepresentation.write(to: output.appendingPathComponent("final.png"))
            if attach && ProcessInfo.processInfo.environment["PD_LOCAL_OWNED_UI_RUNNER"] == "true" {
                for artifact in try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) {
                    let attachment = XCTAttachment(contentsOfFile: artifact)
                    attachment.name = artifact.lastPathComponent
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        // The outer harness stops only the exact published executable it owns.
    }

    @MainActor
    func testMinimumWindowKeepsEveryPageAndItsEssentialControlsReachable() throws {
        try prepare()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        if ProcessInfo.processInfo.environment["PD_LOCAL_OWNED_UI_RUNNER"] == "true",
           let screen = NSScreen.main {
            // Keep pointer-based checks on one visible display. Do not change
            // display modes or move any other application's window.
            let frame = window.frame
            let x = screen.visibleFrame.minX + 20
            let y = screen.frame.maxY - screen.visibleFrame.maxY + 20
            let title = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 10))
            title.click(forDuration: 0.3, thenDragTo: title.withOffset(
                CGVector(dx: x - frame.minX, dy: y - frame.minY)))
            try record("local-window-positioned")
            XCTAssertEqual(window.frame.minX, x, accuracy: 2)
            XCTAssertEqual(window.frame.minY, y, accuracy: 2)
        }
        let initial = window.frame
        resize(window, by: CGVector(dx: 140, dy: 0))
        try record("resize-positive-control")
        XCTAssertGreaterThan(window.frame.width, initial.width + 100, "The window resize gesture must actually work")
        resize(window, by: CGVector(dx: -800, dy: -600))
        let minimum = window.frame
        resize(window, by: CGVector(dx: -100, dy: -100))
        minimumWindow = window.frame
        try record("minimum-window")
        try captureFinal()
        XCTAssertEqual(window.frame.width, minimum.width, accuracy: 2, "A second shrink must stay at the real minimum")
        XCTAssertEqual(window.frame.height, minimum.height, accuracy: 2, "A second shrink must stay at the real minimum")
        let content = app.splitGroups.firstMatch
        XCTAssertTrue(content.exists, "Inspect the native navigation content, separately from window chrome")
        XCTAssertEqual(content.frame.width, 980, accuracy: 2, "Minimum supported content width")
        // The native split-group includes the title-bar area. Its divider spans
        // the 800-point content layout; the observed full window is 852 high.
        XCTAssertTrue(app.splitters.firstMatch.exists)
        XCTAssertEqual(app.splitters.firstMatch.frame.height, 800, accuracy: 2,
                       "Minimum supported content layout height")

        // Freeze only the owned sampler after the startup and resize controls.
        // Verify real pointer input through the resulting Resume control.
        app.activate()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(pause.frame))
        pause.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 15))
        try record("sampling-paused")
        resize(window, by: CGVector(dx: 20, dy: 0))
        XCTAssertGreaterThan(window.frame.width, minimumWindow.width + 10)
        resizeToWidth(window, width: minimumWindow.width)
        XCTAssertEqual(window.frame.width, minimumWindow.width, accuracy: 2)

        if ProcessInfo.processInfo.environment["PD_EXPECT_NAVIGATION_OVERFLOW"] == "true" {
            try open("Diagnose", window: window)
            try capture("Diagnose")
            XCTFail("The known published navigation overflow must fail its layout assertion")
            return
        }

        let widths = (ProcessInfo.processInfo.environment["PD_UI_WIDTHS"] ?? "980")
            .split(separator: ",").compactMap { Double($0) }
        XCTAssertFalse(widths.isEmpty)
        for width in widths {
            resizeToWidth(window, width: width)
            minimumWindow = window.frame
            XCTAssertEqual(window.frame.width, width, accuracy: 2)
            try checkEveryPage(window: window)
        }
        try record("completed", extra: ["pages": widths.count * 8])
    }

    @MainActor
    private func checkEveryPage(window: XCUIElement) throws {
        let livePages = [
            ("Processes", "See what is running."),
            ("Ports", "Find a local listener"),
            ("Agent sessions", "Local coding-agent families"),
            ("Memory", "Watch memory pressure"),
        ]
        for (page, subtitle) in livePages {
            try open(page, window: window)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@", subtitle, subtitle
            ))
                .firstMatch.waitForExistence(timeout: 10), page)
            try editSearch(app.textFields["Search processes, projects and ports"], window: window)
            for title in ["Resume", "Refresh processes", "Help with processes and measurements", "Stop…"] {
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
        try editSearch(app.textFields["Search app access audit"], window: window)
        try reachable(app.buttons["Review Login Items"], window: window)
        try reachable(app.buttons["Refresh audit"], window: window)
        try capture("App access")
        try open("Configuration", window: window)
        try editSearch(app.textFields["Search configuration files"], window: window)
        try reachable(app.buttons["Refresh"], window: window)
        try capture("Configuration")
        try open("Diagnose", window: window)
        try reachable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Start '"))
            .firstMatch, window: window)
        try reachable(app.buttons["Diagnose terminal startup…"], window: window)
        try capture("Diagnose")
    }

    @MainActor
    private func resize(_ window: XCUIElement, by delta: CGVector) {
        guard abs(delta.dx) > 1 || abs(delta.dy) > 1 else { return }
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.3, thenDragTo: corner.withOffset(delta))
    }

    @MainActor
    private func resizeToWidth(_ window: XCUIElement, width: Double) {
        for _ in 0..<4 {
            if abs(window.frame.width - width) <= 2 { return }
            // Pointer drags are not exact window-coordinate assignments.
            // Re-observe the real frame; keep the strict final size assertion.
            resize(window, by: CGVector(dx: width - window.frame.width, dy: 0))
        }
    }

    @MainActor
    private func open(_ title: String, window: XCUIElement) throws {
        let button = app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        try reachable(button, window: window)
        button.click()
        try record("opened", extra: ["page": title])
    }

    @MainActor
    private func editSearch(_ field: XCUIElement, window: XCUIElement) throws {
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(field.frame.width, 0)
        XCTAssertGreaterThan(field.frame.height, 0)
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(field.frame))
        // Prove actual pointer and keyboard input. SwiftUI plain text fields
        // can report isHittable=false despite being visible and editable.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let probe = "fleet-ui-check-1701"
        app.typeText(probe)
        XCTAssertTrue((field.value as? String)?.contains(probe) == true,
                      "The visible search field must receive typed input")
        app.typeKey("a", modifierFlags: .command)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse((field.value as? String)?.contains(probe) == true,
                       "The search query must be clearable")
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
        let window = app.windows.firstMatch
        XCTAssertEqual(window.frame.width, minimumWindow.width, accuracy: 2,
                       "Page navigation must not enlarge the minimum window")
        XCTAssertEqual(window.frame.height, minimumWindow.height, accuracy: 2,
                       "Page navigation must not enlarge the minimum window")
        XCTAssertEqual(app.splitters.firstMatch.frame.height, 800, accuracy: 2,
                       "Every page retains the minimum content layout")
        let name = "\(Int(window.frame.width))-" + page.lowercased().replacingOccurrences(of: " ", with: "-")
        try window.screenshot().pngRepresentation.write(to: output.appendingPathComponent("\(name).png"))
        try app.debugDescription.write(to: output.appendingPathComponent("\(name)-ax.txt"),
                                       atomically: true, encoding: .utf8)
        try record("layout-observed", extra: ["page": page])
        let content = app.splitGroups.firstMatch
        XCTAssertTrue(content.exists)
        XCTAssertLessThanOrEqual(content.frame.height, window.frame.height + 2,
                                 "Navigation split group must fit inside the window")
        XCTAssertTrue(window.frame.insetBy(dx: -2, dy: -2).contains(content.frame),
                      "Navigation split group must fit inside the window")
        for title in ["Processes", "Ports", "Agent sessions", "Memory", "Fans & heat",
                      "App access", "Configuration", "Diagnose"] {
            let button = app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
            try reachable(button, window: window)
        }
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
        if let screen = NSScreen.main {
            observation["screen"] = ["width": screen.frame.width, "height": screen.frame.height,
                                     "visibleWidth": screen.visibleFrame.width, "visibleHeight": screen.visibleFrame.height]
        }
        if let content = app?.splitGroups.firstMatch, content.exists {
            observation["navigationSplitGroup"] = ["width": content.frame.width, "height": content.frame.height]
        }
        if let divider = app?.splitters.firstMatch, divider.exists {
            observation["contentLayoutHeight"] = divider.frame.height
        }
        observations.append(observation)
        let data = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("ui-observations.json"), options: .atomic)
    }
}
