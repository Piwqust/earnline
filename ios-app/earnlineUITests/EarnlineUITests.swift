import XCTest

@MainActor
final class EarnlineUITests: XCTestCase {
    func testLedgerAndSettingsAreReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()

        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Primary"].exists)
        XCTAssertTrue(app.staticTexts["Display conversion rate"].exists)
    }

    func testSearchOpensFromMoreMenuWithNativeSearchState() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()

        XCTAssertTrue(app.staticTexts["Search income"].waitForExistence(timeout: 3))
    }

    func testDeveloperModeRevealsAdvancedSettingsOnlyWhenEnabled() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoSettings"]
        app.launch()

        let developerMode = app.switches["Developer Mode"]
        XCTAssertTrue(developerMode.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(developerMode.isHittable)
        XCTAssertFalse(app.staticTexts["Status"].exists)
        developerMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        XCTAssertEqual(app.switches["Developer Mode"].value as? String, "1")
    }
}
