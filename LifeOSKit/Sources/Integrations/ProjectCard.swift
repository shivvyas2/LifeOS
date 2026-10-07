import Foundation

public struct ProjectCommit: Codable, Equatable, Sendable {
    public let subject: String
    public let url: URL
    public init(subject: String, url: URL) { self.subject = subject; self.url = url }
}

public struct ProjectIssue: Codable, Equatable, Sendable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

public enum ProjectFollowUp: Codable, Equatable, Sendable {
    case milestone(title: String, open: Int, total: Int, due: Date?, url: URL)
    case issues(count: Int, newest: [ProjectIssue])
}

/// What the day's Project section shows.
public struct ProjectCard: Codable, Equatable, Sendable {
    public let repo: String
    public let repoURL: URL
    public let commitCount: Int
    public let commits: [ProjectCommit]
    public let isTodayWithoutCommits: Bool
    public let followUp: ProjectFollowUp?
}

public enum ProjectCardState: Equatable, Sendable {
    /// `asOf` is set when a refresh failed and this is the cached card.
    case card(ProjectCard, asOf: Date?)
    case reconnect
}

/// Turns what GitHub returned into the card. No network here.
public enum ProjectCardBuilder {
    /// The repo with the most of the day's commits; a tie goes to the one
    /// whose latest commit is latest.
    public static func busiestRepo(in items: [GitHubCommitSearch.Item]) -> GitHubRepoRef? {
        let groups = Dictionary(grouping: items, by: \.repository.fullName)
        let best = groups.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            let left = lhs.value.map(\.commit.author.date).max() ?? .distantPast
            let right = rhs.value.map(\.commit.author.date).max() ?? .distantPast
            return left < right
        }
        return best?.value.first?.repository
    }

    public static func commits(in items: [GitHubCommitSearch.Item], repo fullName: String) -> [ProjectCommit] {
        items.filter { $0.repository.fullName == fullName }
            .sorted { $0.commit.author.date > $1.commit.author.date }
            .map { item in
                let subject = item.commit.message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? ""
                return ProjectCommit(subject: subject, url: item.htmlUrl)
            }
    }

    /// The soonest-due open milestone, undated ones after dated ones; with
    /// none, the open issues; with neither, nothing.
    public static func followUp(milestones: [GitHubMilestone], issues: GitHubIssueSearch?) -> ProjectFollowUp? {
        let ordered = milestones.sorted { lhs, rhs in
            switch (lhs.dueOn, rhs.dueOn) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.title < rhs.title
            }
        }
        if let first = ordered.first {
            return .milestone(title: first.title, open: first.openIssues,
                              total: first.openIssues + first.closedIssues, due: first.dueOn, url: first.htmlUrl)
        }
        guard let issues, issues.totalCount > 0 else { return nil }
        return .issues(count: issues.totalCount, newest: issues.items.prefix(2).map { ProjectIssue(title: $0.title, url: $0.htmlUrl) })
    }

    public static func card(repo: GitHubRepoRef, commits: [ProjectCommit], isToday: Bool, followUp: ProjectFollowUp?) -> ProjectCard {
        ProjectCard(repo: repo.name, repoURL: repo.htmlUrl, commitCount: commits.count, commits: commits,
                    isTodayWithoutCommits: isToday && commits.isEmpty, followUp: followUp)
    }
}
