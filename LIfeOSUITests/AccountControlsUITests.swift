import XCTest

/// The account controls on their preview pages: no server, a stub client.
final class AccountControlsUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testClearSelectedNeedsABoxAndTheWord() {
        let app = launch("settings-clear-data")
        let clear = app.buttons["Clear selected…"]
        XCTAssertTrue(clear.waitForExistence(timeout: 8))
        XCTAssertFalse(clear.isEnabled, "enabled with nothing ticked")
        app.buttons["AI chats"].tap()
        XCTAssertFalse(clear.isEnabled, "enabled before CLEAR was typed")
        let field = app.textFields["Type CLEAR to confirm"]
        field.tap()
        field.typeText("CLEAR")
        XCTAssertTrue(clear.isEnabled, "still disabled with a box ticked and CLEAR typed")
        clear.tap()
        XCTAssertTrue(app.staticTexts["Cleared."].waitForExistence(timeout: 4))
    }

    func testDeleteNeedsTheWord() {
        let app = launch("settings-delete-account")
        let delete = app.buttons["Delete my account"]
        XCTAssertTrue(delete.waitForExistence(timeout: 8))
        XCTAssertFalse(delete.isEnabled)
        let field = app.textFields["Type DELETE to confirm"]
        field.tap()
        field.typeText("DELETE")
        XCTAssertTrue(delete.isEnabled)
    }

    func testKeepMyAccountDismissesThePage() {
        let app = launch("keep-account")
        let keep = app.buttons["Keep my account"]
        XCTAssertTrue(keep.waitForExistence(timeout: 8))
        keep.tap()
        XCTAssertTrue(app.staticTexts["Kept"].waitForExistence(timeout: 4))
    }

    func testTheCoachClearsItsConversation() {
        let app = launch("coach")
        let question = app.staticTexts["Give me a quick look at my week."]
        XCTAssertTrue(question.waitForExistence(timeout: 8), "no sample turn")
        app.buttons["Conversation options"].tap()
        app.buttons["Clear conversation"].tap()
        let confirm = app.buttons["Clear"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 4), "the conversation stayed")
    }
}
