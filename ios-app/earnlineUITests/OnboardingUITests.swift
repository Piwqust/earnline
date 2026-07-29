import XCTest

/// The first-run flow: two steps that write real rows, then the ledger with the
/// result in it. There is no Skip — the design treats both steps as required —
/// so these tests walk it the way an owner has to.
@MainActor
final class OnboardingUITests: XCTestCase {
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let launchArguments = [
            "-uiTesting",
            "-resetDeveloperMode",
            "-resetExperimentalFeatures"
        ] + extraArguments
        app.launchArguments = launchArguments
        app.launchEnvironment["EARNLINE_UI_TEST_FLAGS"] = launchArguments.joined(separator: " ")
        app.launch()
        return app
    }

    /// UI automation runs on a wiped defaults suite, so the flow is opt-in
    /// behind its own flag rather than firing in every other suite.
    private func launchOnboarding() -> XCUIApplication {
        let app = launch(["-demoOnboarding"])
        XCTAssertTrue(app.otherElements["onboarding.flow"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement,
                        in app: XCUIApplication,
                        maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 3)
    }

    /// Names the client and moves to the income step, returning the name that
    /// actually landed in the field.
    ///
    /// `typeText` goes through whatever keyboard layout the host machine has
    /// attached, so a machine set to a non-Latin layout types something other
    /// than what was asked for. Read the field back rather than assuming.
    @discardableResult
    private func completeClientStep(in app: XCUIApplication, name: String = "Acme Studio") -> String {
        let field = app.textFields["onboarding.clientName"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(name)
        let typed = (field.value as? String) ?? name

        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.isEnabled)
        primary.tap()
        return typed
    }

    // MARK: It stays out of the normal launch path

    /// A workspace that has already been introduced — which is every other UI
    /// test's starting state — lands on the ledger, never on the flow.
    func testAPlainLaunchGoesStraightToTheLedger() {
        let app = launch()

        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["onboarding.flow"].exists)
        XCTAssertFalse(app.textFields["onboarding.clientName"].exists)
    }

    /// And the Settings replay route stays hidden until Developer Mode is on.
    func testTheReplayRouteIsHiddenUntilDeveloperModeIsOn() {
        let app = launch(["-demoSettings"])

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        let developerMode = app.switches["Developer Mode"]
        XCTAssertTrue(reveal(developerMode, in: app))
        XCTAssertEqual(developerMode.value as? String, "0")
        XCTAssertFalse(app.buttons["settings.onboarding"].exists)
    }

    // MARK: Step 1 — the client

    func testItOpensOnTheClientStep() {
        let app = launchOnboarding()

        XCTAssertTrue(app.otherElements["onboarding.step.client"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["onboarding.clientName"].exists)
        XCTAssertTrue(app.buttons["onboarding.primary"].exists)
    }

    /// The flow covers the ledger completely: nothing behind it should be
    /// reachable while it is up.
    func testTheLedgerIsNotReachableBehindTheFlow() {
        let app = launchOnboarding()

        XCTAssertTrue(app.textFields["onboarding.clientName"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ledger.menu"].isHittable)
        XCTAssertFalse(app.buttons["ledger.fab"].isHittable)
    }

    /// There is no Skip anywhere in the flow — the ledger needs a client.
    func testThereIsNoWayPastTheClientStepWithoutNamingOne() {
        let app = launchOnboarding()

        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        XCTAssertFalse(app.buttons["onboarding.primary"].isEnabled)

        let field = app.textFields["onboarding.clientName"]
        field.tap()
        field.typeText("Acme Studio")
        XCTAssertTrue(app.buttons["onboarding.primary"].isEnabled)
    }

    func testOpeningTheKeyboardDoesNotResizeTheIllustration() {
        let app = launchOnboarding()
        let illustration = app.otherElements["onboarding.illustration"]
        XCTAssertTrue(illustration.waitForExistence(timeout: 3))
        let initialFrame = illustration.frame

        app.textFields["onboarding.clientName"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let keyboardFrame = illustration.frame

        XCTAssertEqual(keyboardFrame.origin.x, initialFrame.origin.x, accuracy: 1)
        XCTAssertEqual(keyboardFrame.origin.y, initialFrame.origin.y, accuracy: 1)
        XCTAssertEqual(keyboardFrame.width, initialFrame.width, accuracy: 1)
        XCTAssertEqual(keyboardFrame.height, initialFrame.height, accuracy: 1)
    }

    // MARK: Step 2 — the first earning

    func testNamingAClientReachesTheIncomeStep() {
        let app = launchOnboarding()
        completeClientStep(in: app)

        XCTAssertTrue(app.otherElements["onboarding.step.income"].waitForExistence(timeout: 3))
        // The real composer, not a mock of it.
        XCTAssertTrue(app.textFields["composer.amount"].waitForExistence(timeout: 3))
    }

    // MARK: Step 3 — the ledger behind the result

    func testWritingTheFirstLineFinishesTheFlow() {
        let app = launchOnboarding()
        let clientName = completeClientStep(in: app)

        let amount = app.textFields["composer.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("100")

        // The task field is a vertical `TextField`, which UIKit backs with a
        // text view — match on identifier rather than on element type.
        let task = app.descendants(matching: .any)["composer.task"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        task.typeText("Launch kit")

        let submit = app.buttons["composer.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        submit.tap()

        // Assert on what the owner actually sees rather than on the container:
        // the result copy, naming the client and the amount just written.
        XCTAssertTrue(app.staticTexts["You’re all set!"].waitForExistence(timeout: 8))
        let summary = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                  clientName, "$100")
        )
        XCTAssertTrue(summary.waitForExistence(timeout: 3))

        let start = app.buttons["onboarding.done.primary"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        // The flow hands over to the ledger it has just populated.
        XCTAssertTrue(app.buttons["ledger.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["onboarding.flow"].exists)
        // The ledger draws the client name inside its chip's button, so match
        // on any element type rather than assuming a static text.
        let chip = app.descendants(matching: .any)[clientName].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
    }
}
