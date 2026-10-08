import XCTest

/// The iPad rail: put away, the content takes its room; brought back, the
/// content steps clear of it again. Regular width only, so it skips on a phone.
@MainActor
final class RailUITests: XCTestCase {
    func testHidingTheRailWidensTheContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=root"]
        app.launch()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the rail is iPad only")

        let hide = app.buttons["Hide navigation"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10), "no rail")
        let tab = app.buttons["Today"]
        attach(app, "rail out")

        hide.tap()
        let show = app.buttons["Show navigation"]
        XCTAssertTrue(show.waitForExistence(timeout: 4), "no way back to the rail")
        XCTAssertFalse(tab.isHittable, "the rail's tabs are still in reach")
        attach(app, "rail away")

        show.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 4))
        XCTAssertTrue(tab.isHittable)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
