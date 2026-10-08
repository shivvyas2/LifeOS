import XCTest

/// The Plan view on the `project-plan` preview page, whose fixture has three
/// features: one done, one in review, one planned.
@MainActor
final class ProjectPlanUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testThePlanShowsProgressAndStages() {
        let app = launch("project-plan")
        XCTAssertTrue(app.staticTexts["1 OF 3 FEATURES DONE"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["IN REVIEW"].exists)
        XCTAssertTrue(app.staticTexts["PR #42 open"].exists)
    }

    func testAddingAFeature() {
        let app = launch("project-plan")
        let field = app.textFields["New feature"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Dark mode\n")
        XCTAssertTrue(app.staticTexts["Dark mode"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["1 OF 4 FEATURES DONE"].exists)
    }

    func testOpeningAFeatureShowsItsBranch() {
        let app = launch("project-plan")
        let row = app.buttons["Credit cards"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(app.staticTexts["feat/credit-cards"].waitForExistence(timeout: 4))
    }
}
