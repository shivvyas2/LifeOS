import XCTest

/// The day's Project section on the `day-github` preview page, whose stub
/// card has seven commits.
final class DayProjectUITests: XCTestCase {
    func testFourMoreShowsEveryCommit() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=day-github"]
        app.launch()
        let more = app.buttons["4 more"]
        for _ in 0..<6 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 6), "no 4 more")
        more.tap()
        // The stub's oldest subject, repeated: the UI test target cannot import the app.
        XCTAssertTrue(app.buttons["chore(release): version 1.0.2, build 50, on every target"].waitForExistence(timeout: 4),
                      "the last subject never showed")
        XCTAssertFalse(app.buttons["4 more"].exists)
    }
}
