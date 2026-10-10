import XCTest

/// The shared sign-in screens on the `sign-in` preview page, whose stub
/// backend sends any code and accepts 123456.
final class SignInUITests: XCTestCase {
    func testEmailCodeFlowAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=sign-in"]
        app.launch()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 8), "no email field")
        let send = app.buttons["Send code"]
        XCTAssertFalse(send.isEnabled, "Send code enabled with no address")
        email.tap()
        email.typeText("shiv@example.com")
        XCTAssertTrue(send.isEnabled, "Send code stayed disabled for a valid address")
        send.tap()

        XCTAssertTrue(app.staticTexts["Enter your code"].waitForExistence(timeout: 4), "never reached the code step")
        app.buttons["Back"].tap()
        XCTAssertTrue(email.waitForExistence(timeout: 4), "Back did not return to the address step")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["preview.signin.left"].waitForExistence(timeout: 4), "Back at the first step did not leave sign-in")
    }
}
