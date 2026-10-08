import Testing
import Foundation
@testable import Integrations
import Persistence

@Suite struct FeatureStageResolverTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private let repo = "shivvyas2/LifeOS"
    private func pr(_ number: Int, _ state: GitHubPullState.State, branch: String = "feat/cards",
                    repo: String? = "shivvyas2/LifeOS", cross: Bool = false, mergedHoursAgo: Double? = nil) -> GitHubPullState {
        GitHubPullState(number: number, title: "PR \(number)", state: state,
                        url: URL(string: "https://github.com/\(self.repo)/pull/\(number)")!,
                        mergedAt: mergedHoursAgo.map { now.addingTimeInterval(-$0 * 3_600) },
                        headBranch: branch, headRepo: repo, isCrossRepository: cross)
    }
    private func status(branches: [GitHubBranchState] = [], pulls: [GitHubPullState] = []) -> GitHubProjectStatus {
        GitHubProjectStatus(defaultBranch: "main", branches: branches, pulls: pulls)
    }
    private func branch(_ name: String = "feat/cards", ahead: Int, hoursAgo: Double = 2) -> GitHubBranchState {
        GitHubBranchState(name: name, lastCommitAt: now.addingTimeInterval(-hoursAgo * 3_600), ahead: ahead, behind: 0)
    }

    @Test func noBranchIsNotStarted() {
        #expect(FeatureStageResolver.resolve(branch: nil, repo: repo, status: status(), now: now)
                == ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil))
    }

    @Test func aMissingBranchIsNotStarted() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo, status: status(), now: now).stage == .planned)
    }

    @Test func aBranchWithNoCommitsIsStillPlanned() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                                    status: status(branches: [branch(ahead: 0)]), now: now)
        #expect(resolved == ResolvedStage(stage: .planned, detail: "Branch made, no commits yet", prNumber: nil))
    }

    @Test func commitsAheadAreBuilding() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 12)]), now: now)
                == ResolvedStage(stage: .building, detail: "12 commits", prNumber: nil))
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 1)]), now: now).detail
                == "1 commit")
    }

    @Test func anOpenPRIsInReview() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 3)], pulls: [pr(42, .open)]), now: now)
                == ResolvedStage(stage: .review, detail: "PR #42 open", prNumber: 42))
    }

    @Test func aMergedPRIsDoneEvenAfterTheBranchIsDeleted() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(pulls: [pr(42, .merged, mergedHoursAgo: 50)]), now: now)
                == ResolvedStage(stage: .done, detail: "Merged · PR #42", prNumber: 42))
    }

    @Test func aNewerOpenPRAfterAMergeIsInReview() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
            status: status(branches: [branch(ahead: 1)], pulls: [pr(42, .merged, mergedHoursAgo: 50), pr(57, .open)]), now: now)
        #expect(resolved.stage == .review && resolved.prNumber == 57)
    }

    @Test func aClosedUnmergedPRIsIgnored() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 4)], pulls: [pr(42, .closed)]), now: now).stage
                == .building)
    }

    /// Review Focus 4: a fork's PR from a branch of the same name is not ours.
    @Test func aForksPRDoesNotMoveTheFeature() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
            status: status(pulls: [pr(42, .merged, repo: "someone/LifeOS", cross: true, mergedHoursAgo: 1)]), now: now)
        #expect(resolved.stage == .planned)
    }

    @Test func repoNamesMatchWithoutCase() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: "ShivVyas2/lifeos",
                                                    status: status(pulls: [pr(42, .open)]), now: now)
        #expect(resolved.stage == .review)
    }

    @Test func slugsAreShortPlainAndLowercase() {
        #expect(FeatureStageResolver.slug("Credit cards") == "credit-cards")
        #expect(FeatureStageResolver.slug("  Café & Crème: v2!  ") == "cafe-creme-v2")
        #expect(FeatureStageResolver.slug("🚀") == "feature")
        #expect(FeatureStageResolver.slug(String(repeating: "abc ", count: 30)).count <= 40)
        #expect(!FeatureStageResolver.slug(String(repeating: "abc ", count: 30)).hasSuffix("-"))
        #expect(FeatureStageResolver.suggestedBranch("Credit cards") == "feat/credit-cards")
    }

    @Test func linkingNeedsExactlyOneMatch() {
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["main", "feat/credit-cards"]) == .one("feat/credit-cards"))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["shiv/credit-cards"]) == .one("shiv/credit-cards"))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["feat/credit-cards", "fix/credit-cards"])
                == .several(["feat/credit-cards", "fix/credit-cards"]))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["feat/credit-cards-v2"]) == .none)
    }

    @Test func relativeTimesAreShort() {
        #expect(GitHubRelative.short(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(GitHubRelative.short(now.addingTimeInterval(-600), now: now) == "10m ago")
        #expect(GitHubRelative.short(now.addingTimeInterval(-7_200), now: now) == "2h ago")
        #expect(GitHubRelative.short(now.addingTimeInterval(-3 * 86_400), now: now) == "3d ago")
    }

    @Test func theLastCommitIsTheNewestBranchCommit() {
        let s = status(branches: [branch("a", ahead: 1, hoursAgo: 5), branch("b", ahead: 1, hoursAgo: 1)])
        #expect(s.lastCommitAt == now.addingTimeInterval(-3_600))
    }

    /// Review fix 7: after a rename GitHub reports the new name; a PR from
    /// this repo still counts, and a fork's still does not.
    @Test func aRenamedRepoStillCountsItsOwnPRs() {
        let renamed = GitHubPullState(number: 42, title: "Cards", state: .open, url: URL(string: "https://x")!,
                                      mergedAt: nil, headBranch: "feat/cards", headRepo: "shivvyas2/Almanac",
                                      isCrossRepository: false)
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo, status: status(pulls: [renamed]), now: now).stage
                == .review)
    }
}
