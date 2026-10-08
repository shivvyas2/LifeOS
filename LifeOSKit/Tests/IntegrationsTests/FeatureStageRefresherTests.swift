import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

@Suite @MainActor struct FeatureStageRefresherTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private func setUp() throws -> (ProjectsStore, UUID) {
        let store = ProjectsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
        let p = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: UUID())
        return (store, p)
    }
    private func status(_ branches: [String], pulls: [GitHubPullState] = []) -> GitHubProjectStatus {
        GitHubProjectStatus(defaultBranch: "main",
                            branches: branches.map { GitHubBranchState(name: $0, lastCommitAt: now, ahead: 3, behind: 0) },
                            pulls: pulls)
    }

    @Test func anUnlinkedFeatureLinksToItsOneBranchAndMoves() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Credit cards")
        let changed = try FeatureStageRefresher.apply(status(["main", "feat/credit-cards"]), repo: "o/r",
                                                      projectID: p, store: store, now: now)
        #expect(changed)
        let feature = try #require(try store.feature(id: f))
        #expect(feature.branch == "feat/credit-cards")
        #expect(feature.stage == .building)
    }

    @Test func severalMatchesLinkNone() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Credit cards")
        try FeatureStageRefresher.apply(status(["feat/credit-cards", "fix/credit-cards"]), repo: "o/r",
                                        projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.branch == nil)
        let feature = try #require(try store.feature(id: f))
        #expect(FeatureStageRefresher.candidates(for: feature, in: status(["feat/credit-cards", "fix/credit-cards"]))
                == ["feat/credit-cards", "fix/credit-cards"])
    }

    @Test func nothingChangedIsNothingToSync() throws {
        let (store, p) = try setUp()
        _ = try store.createFeature(projectID: p, title: "Widgets")
        // The first read writes "Not started" once; reading the same again
        // must write nothing, or every member's phone would push it forever.
        try FeatureStageRefresher.apply(status(["main"]), repo: "o/r", projectID: p, store: store, now: now)
        try store.markSynced(at: now)
        let changed = try FeatureStageRefresher.apply(status(["main"]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(changed == false)
        #expect(try store.pending().isEmpty)
    }

    @Test func aMergedFeatureStaysDoneWhenItsBranchGoes() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Sign in", branch: "feat/sign-in")
        let merged = GitHubPullState(number: 40, title: "Sign in", state: .merged, url: URL(string: "https://x")!,
                                     mergedAt: now, headBranch: "feat/sign-in", headRepo: "o/r")
        try FeatureStageRefresher.apply(status(["main"], pulls: [merged]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.stage == .done)
    }

    /// Review fix 1: a read minutes later with nothing new on GitHub writes
    /// nothing. Details must not carry a clock, or every tick is an edit.
    @Test func aLaterReadWithNothingNewWritesNothing() throws {
        let (store, p) = try setUp()
        _ = try store.createFeature(projectID: p, title: "Cards", branch: "feat/cards")
        let merged = GitHubPullState(number: 40, title: "Sign in", state: .merged, url: URL(string: "https://x")!,
                                     mergedAt: now.addingTimeInterval(-86_400), headBranch: "feat/sign-in",
                                     headRepo: "o/r", isCrossRepository: false)
        _ = try store.createFeature(projectID: p, title: "Sign in", branch: "feat/sign-in")
        try FeatureStageRefresher.apply(status(["main", "feat/cards"], pulls: [merged]), repo: "o/r",
                                        projectID: p, store: store, now: now)
        try store.markSynced(at: now)
        let changed = try FeatureStageRefresher.apply(status(["main", "feat/cards"], pulls: [merged]), repo: "o/r",
                                                      projectID: p, store: store, now: now.addingTimeInterval(6 * 60))
        #expect(changed == false)
        #expect(try store.pending().isEmpty)
    }

    /// Review fix 2: a done feature whose PR has dropped out of the read and
    /// whose branch was deleted stays done.
    @Test func aDoneFeatureStaysDoneWhenItsPRIsOutOfTheWindow() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Sign in", branch: "feat/sign-in")
        try store.applyStage(featureID: f, stage: .done, detail: "Merged · PR #40", prNumber: 40, checkedAt: now)
        try FeatureStageRefresher.apply(status(["main"]), repo: "o/r", projectID: p, store: store, now: now)
        let feature = try #require(try store.feature(id: f))
        #expect(feature.stage == .done && feature.prNumber == 40)
    }

    /// Review fix 4: unlinking a branch by hand holds, though a branch is
    /// still named for the feature.
    @Test func anUnlinkedFeatureIsNotLinkedAgain() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Credit cards")
        try FeatureStageRefresher.apply(status(["feat/credit-cards"]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.branch == "feat/credit-cards")
        try store.updateFeature(id: f, branch: .some(nil))
        try FeatureStageRefresher.apply(status(["feat/credit-cards"]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.branch == nil)
        try store.updateFeature(id: f, branch: .some("feat/credit-cards"))
        #expect(try store.feature(id: f)?.autoLink == true)
    }
}
