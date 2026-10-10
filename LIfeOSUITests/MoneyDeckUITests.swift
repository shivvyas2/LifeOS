import XCTest

/// The deck of cards on Money, on the default `money` preview page, whose
/// four cards are Freedom, Discover it, Chase Debit and Zolve, in that order.
final class MoneyDeckUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=money"]
        app.launch()
        return app
    }

    /// A covered card shows only a band: its top when it sits above the open
    /// card, its bottom when it hangs below. A finger lands on the band, so
    /// the test does too, rather than on the centre, which is under the card
    /// in front.
    private func tap(_ card: XCUIElement, atBottom: Bool) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: atBottom ? 0.92 : 0.08)).tap()
    }

    func testTappingACoveredCardBringsItForward() {
        let app = launch()
        let freedom = app.buttons["Freedom ending 4821"]
        let discover = app.buttons["Discover it ending 3305"]
        XCTAssertTrue(freedom.waitForExistence(timeout: 8), "no Freedom card")
        XCTAssertTrue(discover.exists, "no Discover card")

        // Freedom is first, so its top band is never covered.
        tap(freedom, atBottom: false)
        XCTAssertTrue(freedom.isSelected, "Freedom did not open")
        XCTAssertFalse(discover.isSelected)

        tap(discover, atBottom: true)
        XCTAssertTrue(discover.isSelected, "Discover did not come forward")
        XCTAssertFalse(freedom.isSelected, "Freedom stayed open beside it")
    }

    func testTheFiguresLineFollowsTheOpenCard() {
        let app = launch()
        let figures = app.descendants(matching: .any).matching(identifier: "money.deck.figures").firstMatch
        XCTAssertTrue(figures.waitForExistence(timeout: 8), "no figures line under the deck")

        tap(app.buttons["Freedom ending 4821"], atBottom: false)
        XCTAssertTrue(figures.label.contains("1,284.56"), "balance is not Freedom's: \(figures.label)")

        tap(app.buttons["Discover it ending 3305"], atBottom: true)
        XCTAssertTrue(figures.label.contains("410.27"), "balance is not Discover's: \(figures.label)")
        XCTAssertTrue(figures.label.contains("205.77"), "month spend is not Discover's: \(figures.label)")

        tap(app.buttons["Zolve ending 5520"], atBottom: true)
        XCTAssertTrue(figures.label.contains("96.10"), "balance is not Zolve's: \(figures.label)")
    }
}
