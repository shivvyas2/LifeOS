import XCTest

/// Taps through the Notes walkthrough with its real driver, over the design
/// preview's fixture shelf: the app needs a signed-in account otherwise, and
/// the preview gives every run the same pages.
final class NotesWalkthroughUITests: XCTestCase {
    private let sentences = [
        "One tap starts a page. It lands in your Inbox until you file it.",
        "This says where the page lives. Tap it to move it anywhere.",
        "To-dos, headings and lists from here, or type / in the text.",
        "Every open to-do from every page, in one list.",
        "Folders, favourites and habits live here.",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=notes-walkthrough-live"] + extra
        app.launch()
        return app
    }

    private var card: (XCUIApplication) -> XCUIElement { { $0.otherElements["walkthrough.card"] } }

    private func expectStep(_ number: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts[sentences[number - 1]]
        XCTAssertTrue(text.waitForExistence(timeout: 6), "step \(number) never showed", file: file, line: line)
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 4), "no \(label) button")
        button.tap()
    }

    func testAllFiveStepsInOrderThenTheUntouchedSampleGoes() {
        let app = launch()
        for step in 1...4 {
            expectStep(step, in: app)
            tap("Next", in: app)
        }
        expectStep(5, in: app)
        tap("Done", in: app)
        XCTAssertTrue(app.staticTexts[sentences[4]].waitForNonExistence(timeout: 4), "the card stayed after Done")
        XCTAssertFalse(app.staticTexts["Your first page"].waitForExistence(timeout: 2), "the untouched sample was kept")
    }

    func testWordsTypedOnTheSampleSurviveAnImmediateSkip() {
        let app = launch()
        expectStep(1, in: app)
        tap("Next", in: app)
        expectStep(2, in: app)
        app.typeText("Buy milk")
        tap("Skip", in: app)
        XCTAssertTrue(app.staticTexts[sentences[1]].waitForNonExistence(timeout: 4), "the card stayed after Skip")
        XCTAssertTrue(app.staticTexts["Your first page"].waitForExistence(timeout: 6), "the written-in sample was deleted")
    }

    func testTypingASlashOnTheBlockPickerStepKeepsTheStep() {
        let app = launch()
        expectStep(1, in: app)
        tap("Next", in: app)
        expectStep(2, in: app)
        tap("Next", in: app)
        expectStep(3, in: app)
        app.typeText("/")
        // Longer than the two-second anchor wait: the step must still be up.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.staticTexts[sentences[2]].exists, "typing / skipped the block picker step")
    }

    func testAReplayFromAFolderWithASearchStillReachesTheToDosTab() {
        let app = launch(["--from-folder"])
        expectStep(1, in: app)
        for _ in 1...3 { tap("Next", in: app) }
        expectStep(4, in: app)
    }

    func testAWalkthroughStartedBeforeTheShelfIsOnScreenShowsStepOne() {
        let app = launch(["--start-before-hub"])
        expectStep(1, in: app)
        tap("Next", in: app)
        expectStep(2, in: app)
    }
}
