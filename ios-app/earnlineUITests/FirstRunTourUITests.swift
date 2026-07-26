import XCTest

@MainActor
final class FirstRunTourUITests: XCTestCase {
    func testLegacyFirstRunFlagNeverShowsAnOnboardingOverlay() {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-firstRunTour",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = "signedOut"
        app.launch()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["tour.overlay"].exists)
        XCTAssertFalse(app.buttons["tour.skip"].exists)
        XCTAssertFalse(app.staticTexts["Write your first line"].exists)
        XCTAssertFalse(app.staticTexts["Jot income like a notebook —\n“$240 Acme: 2 screens”"].exists)
    }
}
