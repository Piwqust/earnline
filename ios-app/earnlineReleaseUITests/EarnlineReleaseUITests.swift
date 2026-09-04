import XCTest

@MainActor
final class EarnlineReleaseUITests: XCTestCase {
    /// The Release target deliberately receives the old automation arguments.
    /// A real shipping binary must ignore them and start at an ordinary
    /// account gate or an already restored ledger. The latter is valid when a
    /// simulator retains data from a preceding test run.
    func testReleaseBinaryIgnoresDebugAutomationArguments() {
        let app = XCUIApplication()
        let automationArguments = [
            "-uiTesting",
            "-authGatePreview",
            "-authGateState", "failure",
            "-demoLedger",
            "-demoInsights",
            "-resetDeveloperMode"
        ]
        app.launchArguments = automationArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = automationArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = "failure"
        app.launch()

        let guest = app.buttons["Continue without an account"]
        let ledger = app.buttons["ledger.menu"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5) || ledger.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["auth.failure"].exists)
    }

    func testReleaseBinaryShowsAnEntryPointAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let guest = app.buttons["Continue without an account"]
        let ledger = app.buttons["ledger.menu"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5) || ledger.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["auth.failure"].exists)
    }
}
