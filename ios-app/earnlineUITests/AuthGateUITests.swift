import XCTest

@MainActor
final class AuthGateUITests: XCTestCase {
    private func launchWithLegacyAuthGateArguments() -> XCUIApplication {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-authGatePreview",
            "-authGateState", "signedOut",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launchEnvironment["EARNLINE_UI_TEST_AUTH_GATE_STATE"] = "signedOut"
        app.launch()
        return app
    }

    func testLegacyAuthGateArgumentsOpenTheLedgerWithoutAnyPrompt() {
        let app = launchWithLegacyAuthGateArguments()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["auth.entry"].exists)
        XCTAssertFalse(app.staticTexts["Track every income"].exists)
        XCTAssertFalse(app.buttons["Continue with Google"].exists)
        XCTAssertFalse(app.buttons["Continue without an account"].exists)
        XCTAssertFalse(app.buttons["Pair a device"].exists)
    }

    func testDeleteMenuShowsItsTrashIcon() {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-demoLedger",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ]
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launch()

        let entry = app.buttons["$760, Ops Console, Component library, In progress, 19.07.26"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.press(forDuration: 1.1)
        XCTAssertTrue(app.descendants(matching: .any)["Delete"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "delete-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
