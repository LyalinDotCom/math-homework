import XCTest

/// Drives the main flows against real archive data and saves screenshots for
/// visual verification. Screens are captured even when an intermediate step
/// can't be found, so a partial run still produces evidence.
final class WalkthroughUITests: XCTestCase {
    private var screenshotDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let url = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    func testWalkthroughCapturesScreens() throws {
        let app = XCUIApplication()
        app.launch()

        // Home with the seeded desktop sessions.
        _ = app.staticTexts["Math Homework"].waitForExistence(timeout: 10)
        snap("ui-01-home")

        // Open the most recent (20 page) session.
        let firstSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '20 pages'")
        ).firstMatch
        if firstSession.waitForExistence(timeout: 5) {
            firstSession.tap()
            let scoreHeader = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'correct'")
            ).firstMatch
            _ = scoreHeader.waitForExistence(timeout: 10)
            sleep(1)
            snap("ui-02-review-page1")

            // Swipe to the next page of the session — the phone gesture.
            app.swipeLeft()
            sleep(1)
            snap("ui-03-review-page2")

            // Open the zoomable original scan.
            let zoomButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'view the scan'")
            ).firstMatch
            if zoomButton.exists {
                zoomButton.tap()
                _ = app.navigationBars["Original Scan"].waitForExistence(timeout: 5)
                sleep(1)
                snap("ui-04-zoomed-scan")
                let done = app.buttons["Done"].firstMatch
                if done.exists { done.tap() }
            }

            // Back to home.
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
        }

        // History.
        let history = app.buttons["History"].firstMatch
        if history.waitForExistence(timeout: 5) {
            history.tap()
            sleep(1)
            snap("ui-05-history")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
        }

        // Settings.
        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            sleep(1)
            snap("ui-06-settings")
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() }
        }

        // Scanning workspace (camera is unavailable in the simulator, so this
        // lands on the workspace with its import affordance).
        let scan = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Scan Homework'")
        ).firstMatch
        if scan.waitForExistence(timeout: 5), scan.isEnabled {
            scan.tap()
            sleep(1)
            snap("ui-07-scan-workspace")
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 5) { done.tap() }
        }

        snap("ui-08-final")
    }
}
