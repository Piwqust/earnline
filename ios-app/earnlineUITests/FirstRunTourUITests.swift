import XCTest

/// The guided first-entry tour. Under UI automation the tour is opt-in via
/// `-firstRunTour` (an empty store would otherwise start it under every
/// ledger test).
@MainActor
final class FirstRunTourUITests: XCTestCase {
    private func launchWithTour(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-firstRunTour",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + extra
        app.launch()
        return app
    }

    func testTourCompletesAfterTheFirstEntry() {
        let app = launchWithTour()

        let overlay = app.otherElements["tour.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))

        // The spotlighted empty-state CTA opens the client sheet; the overlay
        // stays out of the way while the sheet is up.
        app.buttons["New line"].tap()
        let nameField = app.textFields["Client name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Acme")
        app.buttons["Add client"].tap()

        // The composer opens through the spotlight's hole; saving the first
        // real line completes onboarding immediately.
        let amount = app.textFields["Amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("240")
        let task = app.textFields["Task"]
        task.tap()
        task.typeText("2 screens")
        app.buttons["composer.submit"].tap()

        XCTAssertFalse(overlay.waitForExistence(timeout: 2))

        // The tour never returns within the session either.
        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 3))
        XCTAssertFalse(overlay.exists)
    }

    func testTourSkipDismissesImmediately() {
        let app = launchWithTour()

        let overlay = app.otherElements["tour.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        app.buttons["tour.skip"].tap()
        XCTAssertFalse(overlay.waitForExistence(timeout: 2))

        // The ledger works normally after skipping.
        XCTAssertTrue(app.buttons["New line"].exists)
    }

    func testTourDoesNotAppearOnASeededLedger() {
        let app = launchWithTour(["-demoComposer"])

        XCTAssertTrue(app.buttons["composer.submit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["tour.overlay"].exists)
    }
}
