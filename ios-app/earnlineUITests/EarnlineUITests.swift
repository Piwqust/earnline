import XCTest

@MainActor
final class EarnlineUITests: XCTestCase {
    private func launchApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + arguments
        app.launch()
        return app
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

    func testSearchOpensFromMoreMenuWithNativeSearchState() {
        let app = launchApp()

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()

        XCTAssertTrue(app.staticTexts["Search income"].waitForExistence(timeout: 3))
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
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Experimental"].waitForExistence(timeout: 2))
        let clientBadges = app.switches["Client badges"]
        XCTAssertTrue(clientBadges.exists)
        XCTAssertEqual(clientBadges.value as? String, "0")
        clientBadges.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(clientBadges.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Supabase"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Data"].waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 2))

        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 2))
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

    func testWorkspacePickerOffersDistinctNativeProductionAndTestOptions() {
        let app = launchApp(["-demoSettings", "-demoDeveloperSettings"])

        let workspace = app.buttons["settings.workspace"]
        for _ in 0..<5 where !workspace.exists {
            app.swipeUp()
        }
        XCTAssertTrue(workspace.waitForExistence(timeout: 3))
        XCTAssertTrue(workspace.isEnabled)
        workspace.tap()

        let production = app.buttons["Production"]
        let test = app.buttons["Test"]
        XCTAssertTrue(production.waitForExistence(timeout: 2))
        XCTAssertTrue(test.exists)
        test.tap()

        XCTAssertTrue(workspace.waitForExistence(timeout: 3))
        let selectedValue = workspace.value as? String ?? ""
        XCTAssertTrue(workspace.label.contains("Test") || selectedValue.contains("Test"))
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
