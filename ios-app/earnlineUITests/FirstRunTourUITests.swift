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

    func testTourGuidesThroughTheFirstEntry() {
        let app = launchWithTour()

        let overlay = app.otherElements["tour.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))

        // Step 1: the spotlighted empty-state CTA opens the client sheet;
        // the overlay hides beneath the sheet while it's up.
        app.buttons["New line"].tap()
        let nameField = app.textFields["Client name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Acme")
        app.buttons["Add client"].tap()

        // The composer opens through the spotlight's hole; writing the first
        // real line advances the tour by itself.
        let amount = app.textFields["Amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("240")
        let task = app.textFields["Task"]
        task.tap()
        task.typeText("2 screens")
        app.buttons["composer.submit"].tap()

        // Step 2: the new row's status control is spotlighted.
        XCTAssertTrue(app.buttons["tour.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["entry.status"].firstMatch.exists)
        app.buttons["tour.next"].tap()

        // Step 3: summary cards, then done — permanently.
        let done = app.buttons["tour.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
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
