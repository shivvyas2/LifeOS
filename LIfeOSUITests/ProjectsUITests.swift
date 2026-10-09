import XCTest

/// Projects on its preview pages: an in-memory store, no server.
final class ProjectsUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testCreateAProjectAndAddATask() {
        let app = launch("projects")
        let new = app.buttons["New project"]
        XCTAssertTrue(new.waitForExistence(timeout: 8))
        new.tap()
        let name = app.textFields["LifeOS 1.1"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText("Garden")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Garden"].waitForExistence(timeout: 4), "the new project did not open")
        app.buttons["New task"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText("Plant tomatoes")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["board.card.Plant tomatoes"].waitForExistence(timeout: 4), "the task is not on the board")
    }

    func testDragATaskIntoDoing() {
        let app = launch("project-board")
        let card = app.buttons["board.card.Release notes"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let target = app.otherElements["board.drop.doing"].firstMatch
        let drop = target.exists ? target : app.descendants(matching: .any)["board.drop.doing"].firstMatch
        XCTAssertTrue(drop.waitForExistence(timeout: 4), "no Doing drop zone")
        let before = card.frame.minX
        card.press(forDuration: 0.8, thenDragTo: drop, withVelocity: .slow, thenHoldForDuration: 0.5)
        let moved = app.buttons["board.card.Release notes"]
        XCTAssertTrue(moved.waitForExistence(timeout: 3))
        // Doing is the column to the right of To do.
        XCTAssertGreaterThan(moved.frame.minX, before + 40, "Release notes did not move into Doing")
    }

    func testScheduleATaskFromAnEmptyHour() {
        let app = launch("project-schedule")
        let target = app.buttons["schedule.slot.8"]
        XCTAssertTrue(target.waitForExistence(timeout: 8), "no empty hour to tap")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText("Standup notes")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["schedule.block.Standup notes"].waitForExistence(timeout: 4), "the block is not on the schedule")
    }
}
