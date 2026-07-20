import XCTest

@MainActor
final class EarnlineUITests: XCTestCase {
    private func launchApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + arguments
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = "signedOut"
        app.launch()
        return app
    }

    /// Settings grows when Developer Mode exposes diagnostic routes. Assert on
    /// the actual elements rather than assuming one swipe equals one section;
    /// that kept this release check from exercising the lower recovery tools
    /// after the separate Connection route was added.
    private func reveal(_ element: XCUIElement,
                        in app: XCUIApplication,
                        maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 3)
    }

    private func returnToSettingsHeader(in app: XCUIApplication,
                                        close: XCUIElement) -> Bool {
        for _ in 0..<8 where !close.exists {
            app.swipeDown()
        }
        return close.waitForExistence(timeout: 3)
    }

    func testLedgerAndSettingsAreReachable() {
        let app = launchApp()

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

    func testSearchOpensFromDockedBottomToolbarFieldWithNativeFiltersMenu() {
        let app = launchApp()

        // The resting search field is docked in the bottom toolbar between
        // the "…" and "+" circles, Notes/Mail-style.
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        // A contextual native menu replaces More while searching. Status is
        // always offered, so it anchors the check.
        let filters = app.buttons["ledger.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 3))
        XCTAssertEqual(filters.label, "Filters")
        XCTAssertTrue(filters.isHittable)
        filters.tap()

        let status = app.buttons["Status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        status.tap()

        let paid = app.descendants(matching: .any)["Paid"].firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 2))
        paid.tap()

        filters.tap()
        let clear = app.buttons["Clear filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 2))
        clear.tap()
    }

    func testFiltersRemainReachableAtAccessibilityTextSize() {
        let app = launchApp([
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        let filters = app.buttons["ledger.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 3))
        XCTAssertTrue(filters.isHittable)
        XCTAssertGreaterThanOrEqual(filters.frame.height, 44)
    }

    func testDeveloperModeRevealsAdvancedSettingsOnlyWhenEnabled() {
        let app = launchApp(["-demoSettings"])

        let developerMode = app.switches["Developer Mode"]
        for _ in 0..<3 where !developerMode.exists {
            app.swipeUp()
        }
        XCTAssertTrue(developerMode.waitForExistence(timeout: 3))
        XCTAssertTrue(developerMode.isHittable)
        XCTAssertFalse(app.staticTexts["Status"].exists)
        XCTAssertFalse(app.switches["Client badges"].exists)
        developerMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        XCTAssertEqual(app.switches["Developer Mode"].value as? String, "1")
        XCTAssertTrue(reveal(app.staticTexts["Experimental"], in: app))
        let clientBadges = app.switches["Client badges"]
        XCTAssertTrue(reveal(clientBadges, in: app))
        XCTAssertEqual(clientBadges.value as? String, "0")
        clientBadges.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(clientBadges.value as? String, "1")
        XCTAssertTrue(reveal(app.staticTexts["Connection"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["Sync"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["Data"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["About"], in: app))

        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(returnToSettingsHeader(in: app, close: close))
        close.tap()

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()

        let restoredDeveloperMode = app.switches["Developer Mode"]
        for _ in 0..<3 where !restoredDeveloperMode.exists {
            app.swipeUp()
        }
        XCTAssertTrue(restoredDeveloperMode.waitForExistence(timeout: 3))
        XCTAssertEqual(restoredDeveloperMode.value as? String, "1")
        let restoredClientBadges = app.switches["Client badges"]
        for _ in 0..<3 where !restoredClientBadges.exists {
            app.swipeUp()
        }
        XCTAssertTrue(restoredClientBadges.waitForExistence(timeout: 3))
        XCTAssertEqual(restoredClientBadges.value as? String, "1")
    }

    func testDeveloperConnectionSettingsStayInASafeSeparateRoute() {
        let app = launchApp(["-demoSettings", "-demoDeveloperSettings"])

        let connection = app.buttons["settings.supabaseConnection"]
        for _ in 0..<5 where !connection.exists {
            app.swipeUp()
        }
        XCTAssertTrue(connection.waitForExistence(timeout: 3))
        XCTAssertTrue(connection.isHittable)
        XCTAssertTrue(connection.label.contains("Personal Supabase database"))
        connection.tap()

        XCTAssertTrue(app.staticTexts["Current connection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Set up a personal Supabase database"].exists)
    }

    func testComposerSubmitKeepsAccessibleGlassButtonSize() {
        let app = launchApp(["-demoComposer"])

        let submit = app.buttons["composer.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(submit.frame.width, 44)
        XCTAssertGreaterThanOrEqual(submit.frame.height, 44)
    }

    func testInsightsLoadsAndDaySelectionIsReachable() {
        let app = launchApp(["-demoInsights"])

        let sheet = app.descendants(matching: .any)["insights.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["3M"].exists)

        let chart = app.descendants(matching: .any)["insights.monthlyIncomeChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 8))

        // The range control lives inside the Monthly income card now.
        app.buttons["1Y"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 3))

        // The income chart leads the sheet; expand to the large detent to
        // bring the heatmap card into view before touching it.
        sheet.swipeUp()
        let heatmap = app.descendants(matching: .any)["insights.heatmap"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 3))
        heatmap.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["insights.selectedDay"].waitForExistence(timeout: 3))

        let clear = app.buttons["insights.clearDaySelection"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertFalse(app.descendants(matching: .any)["insights.selectedDay"].exists)
    }

    func testLargeLedgerClientProfileAppearsBeforeAggregationCompletes() {
        let app = launchApp(["-demoClientProfile"])

        let profile = app.descendants(matching: .any)["client.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Stress Client 1"].exists)
        XCTAssertTrue(app.staticTexts["Total earned"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["All Transactions"].waitForExistence(timeout: 8))
    }

    func testProjectIconCanBeChosenFromSettings() {
        let app = launchApp(["-demoInsights", "-demoSettings"])

        let projectIcons = app.buttons["Project icons"]
        XCTAssertTrue(projectIcons.waitForExistence(timeout: 8))
        projectIcons.tap()

        let project = app.buttons["Launch Kit"]
        XCTAssertTrue(project.waitForExistence(timeout: 8))
        project.tap()

        let work = app.buttons["Work"]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(work.frame.width, 44)
        XCTAssertGreaterThanOrEqual(work.frame.height, 44)
        work.tap()
        XCTAssertFalse(app.alerts["Could not save project icon"].exists)
    }

    func testClientAchievementCollectionAnd3DDetailAreReachable() {
        let app = launchApp(["-demoClientProfile"])

        let collection = app.descendants(matching: .any)["client.achievements.open"]
        XCTAssertTrue(collection.waitForExistence(timeout: 12))
        collection.tap()

        XCTAssertTrue(app.descendants(matching: .any)["client.achievements"].waitForExistence(timeout: 8))
        let firstPayment = app.descendants(matching: .any)["client.achievement.first_payment"]
        XCTAssertTrue(firstPayment.waitForExistence(timeout: 5))
        firstPayment.tap()

        let award3D = app.descendants(matching: .any)["client.achievement3D"]
        XCTAssertTrue(award3D.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Drag to rotate"].exists)
        award3D.swipeRight()
        XCTAssertTrue(award3D.waitForExistence(timeout: 3))
    }
}
