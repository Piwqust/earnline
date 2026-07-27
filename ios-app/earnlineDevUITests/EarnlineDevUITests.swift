import XCTest

/// Kept on the dedicated Dev scheme so production test and CI actions never
/// build or launch the local companion.
@MainActor
final class EarnlineDevUITests: XCTestCase {
    func testDebugMenuOpensLocalAccountAndErrorPreviews() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = app.launchArguments.joined(separator: " ")
        app.launch()

        let debugChip = app.buttons["debug.chip"]
        XCTAssertTrue(debugChip.waitForExistence(timeout: 5))
        debugChip.tap()

        let onboarding = app.buttons["debug.auth.signedOut"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["debug.auth.signOut"].exists)
        XCTAssertTrue(app.buttons["debug.auth.signInFailure"].exists)
        XCTAssertTrue(app.buttons["debug.auth.offlineFailure"].exists)
        XCTAssertTrue(app.buttons["debug.auth.workspacePending"].exists)
        XCTAssertTrue(app.buttons["debug.auth.pairedWorkspacePending"].exists)

        onboarding.tap()
        XCTAssertTrue(app.buttons["debug.auth.close"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)

        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.staticTexts["debug.auth.authenticatingState"].waitForExistence(timeout: 2))
        app.buttons["Simulate error"].tap()
        XCTAssertTrue(app.staticTexts["debug.auth.failure"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sign-in issue"].exists)

        app.buttons["debug.auth.close"].tap()
        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 3))
    }
}
