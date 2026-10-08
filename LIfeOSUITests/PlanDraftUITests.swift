import XCTest

/// The draft sheet on the `project-draft` page, preset with three features
/// so no network is involved.
@MainActor
final class PlanDraftUITests: XCTestCase {
    func testEditingAndKeepingADraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=project-draft"]
        app.launch()
        let first = app.textFields["Feature 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 6))
        XCTAssertEqual(first.value as? String, "Sign in")
        app.buttons["Remove Widgets"].tap()
        XCTAssertFalse(app.textFields["Feature 3"].exists)
        app.buttons["Keep"].tap()
        XCTAssertTrue(app.staticTexts["0 OF 2 FEATURES DONE"].waitForExistence(timeout: 4))
    }
}
