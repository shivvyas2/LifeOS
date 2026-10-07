import XCTest

/// Arranging Today on the `today-custom` preview page, whose layout starts
/// with Month, Today's tasks, GitHub and Next up on the left.
final class TodayLayoutUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }

    func testLongPressHideAndAddBack() {
        let app = launch("today-custom")
        let month = app.otherElements["today.module.month"]
        XCTAssertTrue(month.waitForExistence(timeout: 8), "no Month module")
        month.press(forDuration: 0.9)
        XCTAssertTrue(app.staticTexts["Arranging Today"].waitForExistence(timeout: 4), "arranging never started")
        app.buttons["Hide Month"].tap()
        XCTAssertTrue(app.otherElements["today.module.month"].waitForNonExistence(timeout: 3), "Month stayed")
        let add = app.buttons["Add Month"]
        scrollTo(add, in: app)
        XCTAssertTrue(add.exists, "no Add Month in the tray")
        add.tap()
        XCTAssertTrue(app.otherElements["today.module.month"].waitForExistence(timeout: 3), "Month never came back")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Arranging Today"].waitForNonExistence(timeout: 3))
    }

    func testATapWhileArrangingDoesNotTick() {
        let app = launch("today-arranging")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draft the plan, not done")).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "no Draft the plan row")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let done = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draft the plan, done")).firstMatch
        XCTAssertFalse(done.waitForExistence(timeout: 2), "a tap while arranging ticked the task")
    }

    func testDraggingTasksAboveMonth() {
        let app = launch("today-arranging")
        let month = app.otherElements["today.module.month"]
        let tasks = app.otherElements["today.module.tasks"]
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        XCTAssertTrue(tasks.waitForExistence(timeout: 4))
        XCTAssertTrue(tasks.isHittable, "Today's tasks is not on screen to drag")
        let from = tasks.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let to = month.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertLessThan(app.otherElements["today.module.tasks"].frame.minY,
                          app.otherElements["today.module.month"].frame.minY, "Today's tasks did not move above Month")
    }

    func testDroppingOnTheLowerHalfMovesAModuleDownByOne() {
        let app = launch("today-arranging")
        let month = app.otherElements["today.module.month"]
        let tasks = app.otherElements["today.module.tasks"]
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        XCTAssertTrue(tasks.waitForExistence(timeout: 4))
        // Below the middle of Today's tasks, but still on screen: the module
        // runs past the bottom edge.
        let screen = app.windows.firstMatch.frame
        for _ in 0..<6 where tasks.frame.midY > screen.maxY - 200 {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)))
        }
        let frame = tasks.frame
        let targetY = min(frame.maxY - 20, screen.maxY - 120)
        XCTAssertGreaterThan(targetY, frame.midY, "the lower half of Today's tasks is off screen")
        let monthFrame = month.frame
        let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: monthFrame.midX, dy: max(monthFrame.maxY - 40, screen.minY + 140)))
        let to = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: targetY))
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertGreaterThan(app.otherElements["today.module.month"].frame.minY,
                             app.otherElements["today.module.tasks"].frame.minY, "Month did not move below Today's tasks")
    }

    func testALongPressOnATaskStartsArrangingWithoutTickingIt() {
        let app = launch("today-custom")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draft the plan, not done")).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).press(forDuration: 0.9)
        XCTAssertTrue(app.staticTexts["Arranging Today"].waitForExistence(timeout: 4), "arranging never started")
        let ticked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draft the plan, done")).firstMatch
        XCTAssertFalse(ticked.waitForExistence(timeout: 2), "releasing the long-press ticked the task")
    }

    func testEveryShownModuleHasAVoiceOverHandle() {
        let app = launch("today-custom")
        XCTAssertTrue(app.otherElements["today.module.month"].waitForExistence(timeout: 8))
        for name in ["month", "tasks", "github", "nextUp"] {
            XCTAssertTrue(app.descendants(matching: .any)["today.handle.\(name)"].exists, "no handle for \(name)")
        }
    }
}

