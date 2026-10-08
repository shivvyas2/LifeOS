import XCTest

/// Today's Inbox on the `today-inbox` preview page: two mails that need you,
/// three FYI, from a stub source.
final class InboxUITests: XCTestCase {
    func testNeedsYouSitsAboveFYIAndARowIsAButton() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=today-inbox"]
        app.launch()
        let needsYou = app.staticTexts["NEEDS YOU"]
        let fyi = app.staticTexts["FYI"]
        XCTAssertTrue(needsYou.waitForExistence(timeout: 8), "no NEEDS YOU group")
        XCTAssertTrue(fyi.exists, "no FYI group")
        XCTAssertLessThan(needsYou.frame.minY, fyi.frame.minY, "FYI drawn above NEEDS YOU")
        XCTAssertTrue(app.staticTexts["2 need you"].exists, "no count line")
        let row = app.buttons["inbox.row.1"]
        XCTAssertTrue(row.exists, "the Priya row is not a button")
        XCTAssertTrue(row.label.hasPrefix("Unread, Priya Shah"), "row label: \(row.label)")
        XCTAssertLessThan(row.frame.minY, fyi.frame.minY, "a NEEDS YOU row sits under FYI")
        XCTAssertGreaterThan(app.buttons["inbox.row.3"].frame.minY, fyi.frame.minY, "an FYI row sits above FYI")
    }
}
