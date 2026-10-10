import XCTest

/// The LifeOS Focus app, driven by bundle id from this target: Home signed in
/// as a sample account (`--design-preview`), a mood, Start, a running
/// session, End, and the session counted on Home. Needs LifeOSFocus
/// installed on the simulator first.
final class FocusAppUITests: XCTestCase {
    func testAMoodStartsASessionThatShowsOnHome() {
        let app = XCUIApplication(bundleIdentifier: "com.shivvyas.lifeos.focus")
        app.launchArguments = ["--design-preview"]
        app.launch()

        let relax = app.buttons["Relax"]
        XCTAssertTrue(relax.waitForExistence(timeout: 8), "Home has no Relax mood")
        relax.tap()

        let start = app.buttons["focus.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "the setup sheet did not open")
        start.tap()

        XCTAssertTrue(app.descendants(matching: .any)["focus.timer"].waitForExistence(timeout: 8),
                      "no running session")
        let end = app.buttons["focus.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        end.tap()

        // The summary, then back to Home with the session listed.
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 5) { done.tap() }
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5), "the session is not listed on Home")
    }
}
