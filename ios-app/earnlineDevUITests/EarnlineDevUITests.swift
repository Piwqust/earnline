import XCTest

/// Kept on the dedicated Dev scheme so production test and CI actions never
/// build or launch the local companion.
///
/// The Dev build does not have its own account screen: the debug menu drives
/// the *real* `AuthGateView` through `AppModel.accountState`, so these
/// assertions are against the production gate's own identifiers
/// (`auth.entry` / `auth.authenticating` / `auth.failure`). The only Dev-only
/// chrome is the preview bar laid over it.
@MainActor
final class EarnlineDevUITests: XCTestCase {
    private func launchDev() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = app.launchArguments.joined(separator: " ")
        app.launch()
        return app
    }

    private func openDebugMenu(in app: XCUIApplication) {
        let debugChip = app.buttons["debug.chip"]
        XCTAssertTrue(debugChip.waitForExistence(timeout: 5))
        debugChip.tap()
    }

    /// Scrolls the debug sheet until `element` is on screen.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 3)
    }

    func testDebugMenuListsEveryAccountPreview() {
        let app = launchDev()
        openDebugMenu(in: app)

        XCTAssertTrue(app.buttons["debug.auth.signedOut"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["debug.auth.checking"].exists)
        XCTAssertTrue(app.buttons["debug.auth.signingIn"].exists)
        XCTAssertTrue(app.buttons["debug.auth.signInFailure"].exists)
        XCTAssertTrue(app.buttons["debug.auth.offlineFailure"].exists)
        XCTAssertTrue(app.buttons["debug.auth.workspacePending"].exists)
        XCTAssertTrue(app.buttons["debug.auth.pairedWorkspacePending"].exists)

        // These two sit below the fold on a 402 pt screen.
        XCTAssertTrue(reveal(app.buttons["debug.auth.signOut"], in: app))
        XCTAssertTrue(reveal(app.buttons["debug.auth.returnToLedger"], in: app))

        // The onboarding routes live in their own section further down.
        XCTAssertTrue(reveal(app.buttons["debug.onboarding.replay"], in: app))
        XCTAssertTrue(reveal(app.buttons["debug.onboarding.reset"], in: app))
    }

    /// The preview must show the production gate itself — same copy, same
    /// controls — with only the Dev preview bar added.
    func testTheSignedOutPreviewShowsTheRealGate() {
        let app = launchDev()
        openDebugMenu(in: app)
        app.buttons["debug.auth.signedOut"].tap()

        XCTAssertTrue(app.otherElements["auth.entry"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Track every income"].exists)
        XCTAssertTrue(app.buttons["Continue with Google"].exists)
        XCTAssertTrue(app.buttons["Continue with GitHub"].exists)
        XCTAssertTrue(app.buttons["Continue without an account"].exists)
        XCTAssertTrue(app.buttons["Pair a device"].exists)

        // Dev-only chrome, laid over the real screen.
        XCTAssertTrue(app.buttons["debug.auth.close"].exists)
        XCTAssertTrue(app.staticTexts["debug.auth.badge"].exists)
    }

    /// Tapping a provider in a preview must move the *preview* forward without
    /// opening a real provider or writing a session.
    func testAProviderTapStaysInsideThePreview() {
        let app = launchDev()
        openDebugMenu(in: app)
        app.buttons["debug.auth.signedOut"].tap()

        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 3))
        app.buttons["Continue with Google"].tap()

        XCTAssertTrue(app.otherElements["auth.authenticating"].waitForExistence(timeout: 3))
    }

    func testTheErrorPreviewsRenderOnTheRealGate() {
        let app = launchDev()
        openDebugMenu(in: app)
        app.buttons["debug.auth.signInFailure"].tap()

        XCTAssertTrue(app.otherElements["auth.failure"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sign-in issue"].exists)
    }

    func testClosingThePreviewReturnsToTheLedger() {
        let app = launchDev()
        openDebugMenu(in: app)
        app.buttons["debug.auth.signedOut"].tap()

        let close = app.buttons["debug.auth.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
    }
}
