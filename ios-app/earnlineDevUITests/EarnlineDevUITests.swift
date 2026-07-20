import XCTest

/// Kept on the dedicated Dev scheme so production test and CI actions never
/// build or launch the local companion.
@MainActor
final class EarnlineDevUITests: XCTestCase {
    func testDebugMenuRendersLocalAuthGatePreviews() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = app.launchArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = "signedOut"
        app.launch()

        let debugChip = app.buttons["debug.chip"]
        XCTAssertTrue(debugChip.waitForExistence(timeout: 5))
        debugChip.tap()

        let signedOut = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Signed out")
        ).firstMatch
        XCTAssertTrue(signedOut.waitForExistence(timeout: 3))
        signedOut.tap()

        let entryGate = app.descendants(matching: .any)["auth.entry"]
        XCTAssertTrue(entryGate.waitForExistence(timeout: 3))

        XCTAssertTrue(debugChip.waitForExistence(timeout: 3))
        debugChip.tap()

        let ready = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Ready (debug session)")
        ).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 3))
        ready.tap()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 3))
    }
}
