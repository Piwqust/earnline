import XCTest

@MainActor
final class AuthGateUITests: XCTestCase {
    private func launchAuthGate(state: String = "signedOut", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-authGatePreview",
            "-authGateState", state,
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + extraArguments
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = state
        app.launch()
        return app
    }

    func testGateShowsTheBrandHeadlineOverTheOnboardingVideo() {
        let app = launchAuthGate()
        XCTAssertTrue(app.staticTexts["Track every income"].waitForExistence(timeout: 3))
    }

    func testEntryOffersProvidersAndAnAccessiblePairingRoute() {
        let app = launchAuthGate()

        let apple = app.buttons["auth.apple"]
        let google = app.buttons["Continue with Google"]
        let github = app.buttons["Continue with GitHub"]
        let guest = app.buttons["Continue without an account"]
        let pair = app.buttons["Pair a device"]
        XCTAssertTrue(google.waitForExistence(timeout: 3))
        XCTAssertTrue(apple.exists)
        XCTAssertTrue(github.exists)
        XCTAssertTrue(guest.exists)
        XCTAssertTrue(pair.exists)
        XCTAssertEqual(apple.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(google.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(github.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(guest.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(pair.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(google.frame.minX, apple.frame.minX, accuracy: 0.5)
        XCTAssertEqual(github.frame.maxX, apple.frame.maxX, accuracy: 0.5)

        pair.tap()
        let code = app.textFields["Pairing code"]
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        code.tap()
        code.typeText("earnline-pairing://v1/4c4b8b18-6e55-4b04-b3ec-5b4b2b3aa97c")
        XCTAssertTrue(app.buttons["Connect this device"].isEnabled)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(google.waitForExistence(timeout: 2))
    }

    func testOnboardingVideoAudioCanBeEnabledAndMuted() {
        let app = launchAuthGate()

        let enableSound = app.buttons["Enable sound"]
        XCTAssertTrue(enableSound.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(enableSound.frame.height, 44)
        enableSound.tap()

        XCTAssertTrue(app.buttons["Mute sound"].waitForExistence(timeout: 2))
    }

    func testAuthGateRendersProcessingAndRecoveryStatesWithoutNetwork() {
        let checking = launchAuthGate(state: "checking")
        XCTAssertTrue(checking.staticTexts["Checking your workspace…"].waitForExistence(timeout: 3))
        checking.terminate()

        let authenticating = launchAuthGate(state: "authenticating")
        XCTAssertTrue(authenticating.staticTexts["Opening your workspace…"].waitForExistence(timeout: 3))
        authenticating.terminate()

        let failed = launchAuthGate(state: "failure")
        XCTAssertTrue(failed.staticTexts["Sign-in issue"].waitForExistence(timeout: 3))
        XCTAssertTrue(failed.buttons["Continue with Google"].exists)
        failed.terminate()

        let workspacePending = launchAuthGate(state: "workspacePending")
        XCTAssertTrue(workspacePending.staticTexts["Finish setting up your workspace"].waitForExistence(timeout: 3))
        let checkAgain = workspacePending.buttons["Check again"]
        let signOut = workspacePending.buttons["Sign out"]
        XCTAssertTrue(checkAgain.exists)
        XCTAssertTrue(signOut.exists)
        XCTAssertEqual(checkAgain.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(signOut.frame.height, 44, accuracy: 0.5)
        workspacePending.terminate()

        let pairedWorkspacePending = launchAuthGate(state: "pairedWorkspacePending")
        XCTAssertTrue(pairedWorkspacePending.staticTexts["Finish pairing this device"].waitForExistence(timeout: 3))
        XCTAssertTrue(pairedWorkspacePending.buttons["Pair this device"].exists)
    }

    func testEntryActionsStayReachableAtAccessibilityTextSizes() {
        let app = launchAuthGate(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"
        ])

        let guest = app.buttons["Continue without an account"]
        XCTAssertTrue(guest.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(guest.frame.height, 44)
        XCTAssertTrue(app.buttons["Pair a device"].isHittable)
    }

    func testManualPairingHandsOffToTheLedgerWithoutNetwork() {
        let app = launchAuthGate()

        app.buttons["Pair a device"].tap()
        let code = app.textFields["Pairing code"]
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        code.tap()
        code.typeText("earnline-pairing://v1/4c4b8b18-6e55-4b04-b3ec-5b4b2b3aa97c")
        app.buttons["Connect this device"].tap()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
    }

    func testGuestModeHandsOffToTheLedgerWithoutNetwork() {
        let app = launchAuthGate()

        let guest = app.buttons["Continue without an account"]
        XCTAssertTrue(guest.waitForExistence(timeout: 3))
        guest.tap()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
    }

    func testOwnerCanInspectTheOfflinePairingCodeSheet() {
        let app = launchAuthGate(state: "ready")

        let menu = app.buttons["ledger.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()

        let pairAnotherDevice = app.buttons["Pair another device"]
        XCTAssertTrue(pairAnotherDevice.waitForExistence(timeout: 3))
        pairAnotherDevice.tap()
        XCTAssertTrue(app.staticTexts["Connect another device"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.images["One-time device pairing QR code"].exists)
    }

    func testOwnerCanInspectPairedDevicesWithoutNetwork() {
        let app = launchAuthGate(state: "ready")

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
        app.buttons["ledger.menu"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 2))
        app.buttons["Settings"].tap()

        let manage = app.buttons["Manage paired devices"]
        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(manage.frame.height, 44)
        manage.tap()

        XCTAssertTrue(app.navigationBars["Paired devices"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Paired device"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last signed in'")).firstMatch.exists)
    }
}
