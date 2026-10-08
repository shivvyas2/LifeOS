import XCTest

/// The GitHub view and the Plan's GitHub lines on preview pages whose model
/// is built from a fixture status: branches feat/credit-cards (5 ahead) and
/// old/spike (no commit in 40 days), PR #42 open, PR #40 merged.
@MainActor
final class ProjectGitHubUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testTheGitHubViewListsCommitsBranchesAndPRs() {
        let app = launch("project-github")
        XCTAssertTrue(app.staticTexts["Commits"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["feat: cards in Settings"].exists)
        XCTAssertTrue(app.staticTexts["feat/credit-cards"].exists)
        // The line goes on with the time of the last commit.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "5 ahead · 0 behind")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["#42 Credit cards"].exists)
    }

    func testAFeaturePageShowsTheSuggestedBranch() {
        let app = launch("project-plan")
        let row = app.buttons["Widgets"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(app.textFields["Branch name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.textFields["Branch name"].value as? String, "feat/widgets")
    }
}
