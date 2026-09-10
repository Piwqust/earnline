import XCTest

@MainActor
final class EarnlineUITests: XCTestCase {
    private func launchApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + arguments
        if ProcessInfo.processInfo.environment["EARNLINE_DISABLE_3D_FOR_UI_TESTS"] == "1" {
            launchArguments.append("-disable3DForUITests")
        }
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

    func testComposerFieldsDoNotOverlapAtLargestTextSize() {
        let app = launchApp(["-demoComposer", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                             "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let amount = app.textFields["composer.amount"]
        let project = app.textFields["composer.project"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        XCTAssertTrue(project.exists)
        XCTAssertGreaterThan(amount.frame.width, 0)
        XCTAssertGreaterThan(project.frame.width, 0)
        XCTAssertFalse(amount.frame.intersects(project.frame))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "composer-russian-largest-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSyncStatusIsAvailableWithoutDeveloperMode() {
        let app = launchApp(["-demoSettings", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Sync now"].exists)
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
        XCTAssertTrue(reveal(app.staticTexts["Primary"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["Display conversion rate"], in: app))
    }

    func testSummaryCardsFollowTheTopVisibleLedgerMonth() {
        let app = launchApp(["-demoLedger"])
        let summary = app.descendants(matching: .any)["ledger.earned.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        let initialMonth = summary.label
        for _ in 0..<8 {
            // On the iOS 27 runtime SwiftUI's `List` is not consistently
            // exposed as an XCUIElementTypeTable. The screen-level gesture
            // still targets the visible ledger and verifies the real
            // scroll-driven month handoff without depending on that UIKit
            // implementation detail.
            app.swipeUp()
        }

        let changedMonth = NSPredicate(format: "label != %@", initialMonth)
        expectation(for: changedMonth, evaluatedWith: summary)
        waitForExpectations(timeout: 3)
    }

    func testStressLedgerRemainsResponsiveWhileScrolling() {
        let app = launchApp(["-demoStressLedger"])
        let summary = app.descendants(matching: .any)["ledger.earned.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 8))

        // The stress fixture intentionally has roughly 120 rows per month.
        // Month handoff is covered by the focused fixture above; here the
        // useful assertion is that a large virtualized List continues to
        // accept gestures and expose rows instead of stalling XCUITest.
        for _ in 0..<8 {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(summary.exists)
        let visibleEntry = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "entry.row.")
        ).firstMatch
        XCTAssertTrue(visibleEntry.waitForExistence(timeout: 5))
    }

    func testSearchOpensWithNativeFiltersMenu() {
        let app = launchApp()

        // Search remains system-owned; the command controls are in the
        // navigation bar to avoid the iOS 26 bottom-toolbar hierarchy fault.
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
        let app = launchApp()
        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()

        let developerModeRow = app.switches["settings.developerMode"]
        for _ in 0..<3 where !developerModeRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(developerModeRow.waitForExistence(timeout: 3))
        let developerMode = developerModeRow.descendants(matching: .switch).firstMatch
        XCTAssertTrue(developerMode.waitForExistence(timeout: 3))
        XCTAssertTrue(developerMode.isHittable)
        // Sync status is part of ordinary Settings, independent of Developer Mode.
        XCTAssertFalse(app.switches["Client badges"].exists)
        developerMode.tap()
        let developerEnabled = NSPredicate(format: "value == %@", "1")
        expectation(for: developerEnabled, evaluatedWith: developerMode)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(reveal(app.staticTexts["Experimental"], in: app))
        let clientBadgesRow = app.switches["settings.clientBadges"]
        XCTAssertTrue(reveal(clientBadgesRow, in: app))
        let clientBadges = clientBadgesRow.descendants(matching: .switch).firstMatch
        XCTAssertTrue(clientBadges.waitForExistence(timeout: 3))
        XCTAssertEqual(clientBadges.value as? String, "0")
        clientBadges.tap()
        let badgesEnabled = NSPredicate(format: "value == %@", "1")
        expectation(for: badgesEnabled, evaluatedWith: clientBadges)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(reveal(app.staticTexts["Connection"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["Data"], in: app))

        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(returnToSettingsHeader(in: app, close: close))
        close.tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()

        let restoredDeveloperModeRow = app.switches["settings.developerMode"]
        for _ in 0..<3 where !restoredDeveloperModeRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(restoredDeveloperModeRow.waitForExistence(timeout: 3))
        let restoredDeveloperMode = restoredDeveloperModeRow.descendants(matching: .switch).firstMatch
        XCTAssertTrue(restoredDeveloperMode.waitForExistence(timeout: 3))
        XCTAssertEqual(restoredDeveloperMode.value as? String, "1")
        let restoredClientBadgesRow = app.switches["settings.clientBadges"]
        for _ in 0..<3 where !restoredClientBadgesRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(restoredClientBadgesRow.waitForExistence(timeout: 3))
        let restoredClientBadges = restoredClientBadgesRow.descendants(matching: .switch).firstMatch
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
        XCTAssertFalse(app.buttons["insights.report.share"].exists)

        let chart = app.descendants(matching: .any)["insights.monthlyIncomeChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 8))

        // The range control belongs to the one yearly income chart. Changing
        // it must not reload the full Insights dashboard below.
        let threeMonths = app.buttons["3M"]
        let oneYear = app.buttons["1Y"]
        XCTAssertTrue(threeMonths.exists)
        XCTAssertTrue(oneYear.isSelected)
        threeMonths.tap()
        XCTAssertTrue(threeMonths.isSelected)
        oneYear.tap()
        XCTAssertTrue(oneYear.isSelected)
        XCTAssertTrue(chart.waitForExistence(timeout: 3))

        // The income chart now leads the sheet, so make the calendar actually
        // hittable before tapping a day rather than treating an off-screen AX
        // element as visible.
        let heatmap = app.descendants(matching: .any)["insights.heatmap"]
        for _ in 0..<6 where !heatmap.isHittable {
            sheet.swipeUp()
        }
        XCTAssertTrue(heatmap.waitForExistence(timeout: 3))
        XCTAssertTrue(heatmap.isHittable)
        // Exercise the card's accessible day movement rather than guessing a
        // physical cell inside its horizontally scrollable calendar.
        heatmap.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["insights.selectedDay"].waitForExistence(timeout: 3))

        let clear = app.buttons["insights.clearDaySelection"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertFalse(app.descendants(matching: .any)["insights.selectedDay"].exists)
    }

    func testStatsCardOpensInsights() {
        let app = launchApp(["-demoLedger"])

        let stats = app.buttons["ledger.stats.summary"]
        XCTAssertTrue(stats.waitForExistence(timeout: 8))
        XCTAssertTrue(stats.isHittable)
        stats.tap()
        XCTAssertTrue(app.descendants(matching: .any)["insights.sheet"].waitForExistence(timeout: 5))
    }

    func testDirectIncomeFormPreservesDraftAndSavesToSelectedClient() {
        let app = launchApp(["-demoLedger", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let add = app.buttons["ledger.fab"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let amount = app.textFields["composer.newIncome.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("241.50")
        let task = app.textFields["composer.newIncome.task"]
        task.tap()
        task.typeText("Release verification")
        let client = app.buttons["composer.newIncome.client"]
        client.tap()
        app.buttons["Acme Studio"].firstMatch.tap()
        app.buttons["Close"].firstMatch.tap()
        let keep = app.buttons["Keep editing"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3))
        keep.tap()
        XCTAssertEqual(amount.value as? String, "241.50")
        XCTAssertEqual(task.value as? String, "Release verification")
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.isEnabled)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "direct-income-filled"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        save.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        let entry = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'entry.row.' AND label CONTAINS 'Release verification'")
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("999")
        app.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard draft"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertNotEqual(amount.value as? String, "999")
    }

    func testHomeScreenQuickActionWaitsForTheIncomeDraft() {
        let app = launchApp(["-demoLedger", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let add = app.buttons["ledger.fab"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let amount = app.textFields["composer.newIncome.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("375")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["earnline"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.press(forDuration: 1.2)
        let quickAction = springboard.buttons["Search income"]
        XCTAssertTrue(quickAction.waitForExistence(timeout: 3))
        quickAction.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "375")
        app.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard draft"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testRussianIncomeAndRecoveryScreensInDarkAppearance() {
        let app = launchApp(["-demoLedger", "-uiTestDarkAppearance", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        let add = app.buttons["ledger.fab"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let amount = app.textFields["composer.newIncome.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.isHittable)
        XCTAssertTrue(app.buttons["composer.newIncome.client"].isHittable)
        let form = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        form.name = "direct-income-russian-dark-keyboard"
        form.lifetime = .keepAlways
        self.add(form)
        app.buttons["Закрыть"].firstMatch.tap()
        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        app.buttons["Настройки"].tap()
        let snapshots = app.buttons["settings.safetySnapshots.open"]
        for _ in 0..<10 where !snapshots.isHittable { app.swipeUp() }
        XCTAssertTrue(snapshots.isHittable)
        snapshots.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.safetySnapshots"].waitForExistence(timeout: 5))
        let recovery = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recovery.name = "safety-snapshots-russian-dark"
        recovery.lifetime = .keepAlways
        self.add(recovery)
    }

    func testInsightsRemainInMoreMenu() {
        let app = launchApp(["-demoLedger"])

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()

        let insights = app.buttons["Insights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 3))
        insights.tap()
        XCTAssertTrue(app.descendants(matching: .any)["insights.sheet"].waitForExistence(timeout: 5))
    }

    func testLedgerSummaryRefreshesAfterDeletingAnIncomeLine() {
        let app = launchApp(["-demoLedger"])

        let summary = app.descendants(matching: .any)["ledger.earned.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        let totalBeforeDelete = summary.value as? String
        XCTAssertNotNil(totalBeforeDelete)

        let entry = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "entry.row.")
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.swipeLeft()

        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()

        let confirm = app.alerts["Delete income line?"].buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let summaryUpdated = NSPredicate(format: "value != %@", totalBeforeDelete!)
        expectation(for: summaryUpdated, evaluatedWith: summary, handler: nil)
        waitForExpectations(timeout: 5)
    }

    func testEmptyLedgerAddButtonCreatesAClientBeforeOpeningIncomeComposer() {
        let app = launchApp()

        let add = app.buttons["ledger.fab"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let clientName = app.textFields["Client name"]
        XCTAssertTrue(clientName.waitForExistence(timeout: 3))
        clientName.tap()
        clientName.typeText("Acme")

        let create = app.buttons["client.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        create.tap()

        XCTAssertTrue(app.buttons["composer.submit"].waitForExistence(timeout: 5))
    }

    func testLargeLedgerClientProfileAppearsBeforeAggregationCompletes() {
        let app = launchApp(["-demoClientProfile"])

        let profile = app.descendants(matching: .any)["client.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["client.report.share"].exists)
        XCTAssertTrue(app.staticTexts["Stress Client 1"].exists)
        XCTAssertTrue(app.staticTexts["Total earned"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["All Transactions"].waitForExistence(timeout: 8))
    }

    func testClientTransactionDrillDownKeepsTheLedgerRowsReachable() {
        // Keep this routing assertion independent from the large-profile
        // aggregation benchmark above. The compact fixture verifies the same
        // destination and rows without asking a preview iOS 26 runner to lay
        // out hundreds of off-screen profile records before every gesture.
        let app = launchApp(["-demoClientProfileCompact"])
        let allTransactions = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "All Transactions")
        ).firstMatch
        XCTAssertTrue(allTransactions.waitForExistence(timeout: 12))
        // XCUI performs the same semantic scroll-to-visible gesture a user
        // gets from tapping this native button, without assuming how many
        // profile cards precede it at a particular Dynamic Type size.
        allTransactions.tap()

        XCTAssertTrue(app.navigationBars["All Transactions"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "entry.row.")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testProjectIconCanBeChosenAndPersistsInSettings() {
        let app = launchApp(["-demoSettings", "-demoInsights"])

        let projectIcons = app.buttons["settings.projectIcons"]
        XCTAssertTrue(reveal(projectIcons, in: app))
        projectIcons.tap()

        let project = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Launch Kit")
        ).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 8))
        project.tap()

        let receipt = app.buttons["projectIcon.option.receipt"]
        let preview = app.descendants(matching: .any)["projectIcon.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        let outline = app.segmentedControls["projectIcon.appearance"].buttons["Outline"]
        XCTAssertTrue(outline.exists)
        outline.tap()
        XCTAssertTrue(outline.isSelected)
        XCTAssertEqual(preview.value as? String, "Folder, Outline")

        XCTAssertTrue(reveal(receipt, in: app))
        XCTAssertGreaterThanOrEqual(receipt.frame.width, 44)
        XCTAssertGreaterThanOrEqual(receipt.frame.height, 44)
        receipt.tap()
        XCTAssertFalse(app.alerts["Could not save project icon"].exists)
        XCTAssertEqual(receipt.value as? String, "Selected")
        XCTAssertEqual(preview.value as? String, "Invoice, Outline")

        let projectIconsBack = app.buttons["Project icons"]
        XCTAssertTrue(projectIconsBack.waitForExistence(timeout: 3))
        projectIconsBack.tap()
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        XCTAssertEqual(project.value as? String, "Invoice")

        let settingsBack = app.buttons["Settings"]
        XCTAssertTrue(settingsBack.waitForExistence(timeout: 3))
        settingsBack.tap()

        let close = app.buttons["Close"]
        XCTAssertTrue(returnToSettingsHeader(in: app, close: close))
        close.tap()
    }

    func testAboutIsAvailableOutsideDeveloperMode() {
        let app = launchApp(["-demoSettings"])

        let version = app.descendants(matching: .any)["settings.version"]
        XCTAssertTrue(reveal(version, in: app))
        XCTAssertTrue(version.exists)

        let whatsNew = app.buttons["settings.whatsNew"]
        XCTAssertTrue(reveal(whatsNew, in: app))
        whatsNew.tap()
        XCTAssertTrue(app.navigationBars["What's new"].waitForExistence(timeout: 5))
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
