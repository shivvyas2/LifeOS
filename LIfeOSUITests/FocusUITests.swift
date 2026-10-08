import XCTest

final class FocusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    /// Saves a screenshot when FOCUS_SHOTS names a folder, for looking at
    /// the screens by eye; does nothing otherwise.
    private func shot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["FOCUS_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    func testStartChangeMoodAndEndASession() {
        let app = launch("focus")
        XCTAssertTrue(app.buttons["focus.open"].waitForExistence(timeout: 8))
        app.buttons["focus.open"].tap()

        XCTAssertTrue(app.buttons["focus.mood.brainstorm"].waitForExistence(timeout: 5))
        app.buttons["focus.mood.brainstorm"].tap()
        app.buttons["focus.preset.50-10"].tap()
        shot("1-setup")
        app.buttons["focus.start"].tap()

        let phase = app.staticTexts["focus.phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 8))
        XCTAssertEqual(phase.label, "Focus 1 of 4")
        let timer = app.staticTexts["focus.timer"]
        XCTAssertTrue(timer.label.hasPrefix("50:") || timer.label.hasPrefix("49:"), timer.label)
        shot("2-session")

        app.buttons["focus.changeMood"].tap()
        app.buttons["Relax"].tap()
        shot("2b-mood")
        XCTAssertTrue(app.staticTexts["RELAX"].waitForExistence(timeout: 3))
        XCTAssertEqual(phase.label, "Focus 1 of 4", "changing mood must not touch the clock")

        app.buttons["focus.skip"].tap()
        XCTAssertTrue(phase.waitForLabel("Break"))
        shot("3-break")

        app.buttons["focus.end"].tap()
        XCTAssertTrue(app.buttons["focus.summary.done"].waitForExistence(timeout: 5))
        shot("4-summary")
        app.buttons["focus.summary.done"].tap()
        XCTAssertTrue(app.buttons["focus.open"].waitForExistence(timeout: 5))
    }

    func testAProjectTaskSessionOffersToMarkItDone() {
        let app = launch("focus-task")
        app.buttons["focus.open"].tap()
        XCTAssertTrue(app.staticTexts["Write the launch post"].waitForExistence(timeout: 5))
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.buttons["focus.end"].waitForExistence(timeout: 8))
        app.buttons["focus.end"].tap()
        XCTAssertTrue(app.buttons["Mark \u{201C}Write the launch post\u{201D} done"].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func waitForLabel(_ label: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
