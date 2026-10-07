import Testing
import Foundation
@testable import Integrations

@Suite struct ProjectCardTests {
    private func repo(_ name: String) -> GitHubRepoRef {
        GitHubRepoRef(name: name, fullName: "o/\(name)", htmlUrl: URL(string: "https://github.com/o/\(name)")!, pushedAt: nil)
    }

    private func item(_ repoName: String, at seconds: TimeInterval, message: String = "work") -> GitHubCommitSearch.Item {
        GitHubCommitSearch.Item(
            sha: UUID().uuidString, htmlUrl: URL(string: "https://github.com/o/\(repoName)/commit/x")!,
            commit: .init(message: message, author: .init(date: Date(timeIntervalSince1970: seconds))),
            repository: repo(repoName))
    }

    @Test func theBusiestRepoWins() {
        let items = [item("a", at: 300), item("b", at: 200), item("b", at: 100)]
        #expect(ProjectCardBuilder.busiestRepo(in: items)?.fullName == "o/b")
    }

    @Test func aTieGoesToTheLatestCommit() {
        let items = [item("a", at: 100), item("b", at: 300)]
        #expect(ProjectCardBuilder.busiestRepo(in: items)?.fullName == "o/b")
        #expect(ProjectCardBuilder.busiestRepo(in: items.reversed())?.fullName == "o/b")
    }

    @Test func noCommitsNoRepo() {
        #expect(ProjectCardBuilder.busiestRepo(in: []) == nil)
    }

    @Test func subjectsAreFirstLinesNewestFirstForThatRepoOnly() {
        let items = [item("a", at: 100, message: "older\n\nbody"), item("b", at: 150), item("a", at: 200, message: "newer")]
        #expect(ProjectCardBuilder.commits(in: items, repo: "o/a").map(\.subject) == ["newer", "older"])
    }

    @Test func theSoonestDueMilestoneComesFirstAndUndatedLast() {
        let undated = GitHubMilestone(title: "Later", openIssues: 1, closedIssues: 0, dueOn: nil, htmlUrl: URL(string: "https://x/2")!)
        let soon = GitHubMilestone(title: "1.1", openIssues: 4, closedIssues: 5, dueOn: Date(timeIntervalSince1970: 1000), htmlUrl: URL(string: "https://x/1")!)
        let later = GitHubMilestone(title: "2.0", openIssues: 9, closedIssues: 0, dueOn: Date(timeIntervalSince1970: 9000), htmlUrl: URL(string: "https://x/3")!)
        #expect(ProjectCardBuilder.followUp(milestones: [undated, later, soon], issues: nil)
                == .milestone(title: "1.1", open: 4, total: 9, due: Date(timeIntervalSince1970: 1000), url: URL(string: "https://x/1")!))
        #expect(ProjectCardBuilder.followUp(milestones: [undated], issues: nil)
                == .milestone(title: "Later", open: 1, total: 1, due: nil, url: URL(string: "https://x/2")!))
    }

    @Test func withoutAMilestoneTheIssuesFollow() {
        let issues = GitHubIssueSearch(totalCount: 3, items: [.init(title: "Crash", htmlUrl: URL(string: "https://x/9")!)])
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: issues)
                == .issues(count: 3, newest: [ProjectIssue(title: "Crash", url: URL(string: "https://x/9")!)]))
    }

    @Test func aRepoWithNeitherHasNoFollowUp() {
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: GitHubIssueSearch(totalCount: 0, items: [])) == nil)
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: nil) == nil)
    }

    @Test func todayWithoutCommitsIsMarked() {
        let card = ProjectCardBuilder.card(repo: repo("a"), commits: [], isToday: true, followUp: nil)
        #expect(card.isTodayWithoutCommits)
        #expect(card.repo == "a")
        let past = ProjectCardBuilder.card(repo: repo("a"), commits: [], isToday: false, followUp: nil)
        #expect(!past.isTodayWithoutCommits)
    }
}
