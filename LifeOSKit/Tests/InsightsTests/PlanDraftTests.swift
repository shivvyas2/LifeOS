import Testing
import Foundation
@testable import Insights

@Suite struct PlanDraftTests {
    @Test func thePromptCarriesTheProjectAndStaysUnderTheCap() {
        let prompt = PlanPrompt.make(
            name: "LifeOS", scope: "Ship credit cards", startsOn: nil, endsOn: nil, milestones: ["Alpha", "Beta"],
            readme: String(repeating: "r", count: 20_000), commits: (0..<50).map { "commit \($0)" },
            nudge: String(repeating: "n", count: 500))
        #expect(prompt.contains("Project: LifeOS"))
        #expect(prompt.contains("Scope: Ship credit cards"))
        #expect(prompt.contains("Milestones: Alpha; Beta"))
        #expect(prompt.contains("commit 19") && !prompt.contains("commit 20"))
        #expect(!prompt.contains(String(repeating: "r", count: 6_001)))
        #expect(!prompt.contains(String(repeating: "n", count: 201)))
        #expect(prompt.count <= 12_000)
    }

    @Test func noRepoMeansNoRepoSection() {
        let prompt = PlanPrompt.make(name: "P", scope: "S", startsOn: nil, endsOn: nil, milestones: [],
                                     readme: nil, commits: [], nudge: nil)
        #expect(!prompt.contains("README"))
        #expect(!prompt.contains("Recent commits"))
        #expect(!prompt.contains("Nudge"))
    }

    @Test func aDraftDecodesWithFreshIDs() throws {
        let data = Data(#"{"output":{"features":[{"title":"Sign in","note":"Apple","branch":"feat/sign-in","milestone":""},{"title":"Cards","note":"","branch":"feat/cards","milestone":"Alpha"}]},"tokens":10}"#.utf8)
        let draft: PlanDraft = try RemoteWire.result(data: data, status: 200)
        #expect(draft.features.map(\.title) == ["Sign in", "Cards"])
        #expect(draft.features[0].id != draft.features[1].id)
        #expect(draft.features[1].milestone == "Alpha")
    }

    @Test func theAllowanceIsItsOwnError() {
        #expect(throws: RemoteEngineError.exhausted) {
            let _: PlanDraft = try RemoteWire.result(data: Data(#"{"error":"exhausted"}"#.utf8), status: 429)
        }
    }
}
