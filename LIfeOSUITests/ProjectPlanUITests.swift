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
        XCTAssertTrue(app.staticTexts["In review"].exists)
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

    /// Review fixes 5 and 6: the title can be renamed, and a note typed on
    /// the feature page is kept when the page is left without pressing Return.
    func testRenamingAFeatureAndKeepingItsNote() {
        let app = launch("project-plan")
        let row = app.buttons["Widgets"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        let title = app.textFields["Feature title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Home widgets\n")
        let note = app.textFields["Note"]
        note.tap()
        note.typeText("Small and medium")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Home widgets"].waitForExistence(timeout: 4), "the rename did not stick")
        app.buttons["Home widgets"].tap()
        XCTAssertEqual(app.textFields["Note"].value as? String, "Small and medium", "the note was lost")
    }
}
