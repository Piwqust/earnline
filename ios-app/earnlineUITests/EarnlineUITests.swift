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
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Supabase"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Data"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 2))
    }

    func testComposerSubmitKeepsAccessibleGlassButtonSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoComposer"]
        app.launch()

        let submit = app.buttons["composer.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(submit.frame.width, 44)
        XCTAssertGreaterThanOrEqual(submit.frame.height, 44)
    }

    func testInsightsLoadsAndDaySelectionIsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoInsights"]
        app.launch()

        let sheet = app.descendants(matching: .any)["insights.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["3M"].exists)

        let chart = app.descendants(matching: .any)["insights.monthlyIncomeChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 8))

        let heatmap = app.descendants(matching: .any)["insights.heatmap"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 3))
        heatmap.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["insights.selectedDay"].waitForExistence(timeout: 3))

        let clear = app.buttons["insights.clearDaySelection"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertFalse(app.descendants(matching: .any)["insights.selectedDay"].exists)

        app.buttons["6M"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 3))
    }

    func testLargeLedgerClientProfileAppearsBeforeAggregationCompletes() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoClientProfile"]
        app.launch()

        let profile = app.descendants(matching: .any)["client.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Stress Client 1"].exists)
        XCTAssertTrue(app.staticTexts["Total earned"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["All Transactions"].waitForExistence(timeout: 8))
    }
}
