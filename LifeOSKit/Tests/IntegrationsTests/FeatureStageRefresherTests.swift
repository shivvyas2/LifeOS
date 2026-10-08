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
}
