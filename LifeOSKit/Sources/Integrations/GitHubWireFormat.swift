import Foundation

/// The few shapes the project card reads from GitHub's REST API.
public enum GitHubWire {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct GitHubRepoRef: Codable, Equatable, Sendable {
    public let name: String
    public let fullName: String
    public let htmlUrl: URL
    public var pushedAt: Date?

    public init(name: String, fullName: String, htmlUrl: URL, pushedAt: Date?) {
        self.name = name; self.fullName = fullName; self.htmlUrl = htmlUrl; self.pushedAt = pushedAt
    }
}

public struct GitHubCommitSearch: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        public struct Commit: Decodable, Sendable {
            public struct Author: Decodable, Sendable {
                public let date: Date
                public init(date: Date) { self.date = date }
            }
            public let message: String
            public let author: Author
            public init(message: String, author: Author) { self.message = message; self.author = author }
        }
        public let sha: String
        public let htmlUrl: URL
        public let commit: Commit
        public let repository: GitHubRepoRef
        public init(sha: String, htmlUrl: URL, commit: Commit, repository: GitHubRepoRef) {
            self.sha = sha; self.htmlUrl = htmlUrl; self.commit = commit; self.repository = repository
        }
    }
    public let items: [Item]
}

public struct GitHubMilestone: Decodable, Equatable, Sendable {
    public let title: String
    public let openIssues: Int
    public let closedIssues: Int
    public let dueOn: Date?
    public let htmlUrl: URL
    public init(title: String, openIssues: Int, closedIssues: Int, dueOn: Date?, htmlUrl: URL) {
        self.title = title; self.openIssues = openIssues; self.closedIssues = closedIssues
        self.dueOn = dueOn; self.htmlUrl = htmlUrl
    }
}

public struct GitHubIssueSearch: Decodable, Equatable, Sendable {
    public struct Issue: Decodable, Equatable, Sendable {
        public let title: String
        public let htmlUrl: URL
        public init(title: String, htmlUrl: URL) { self.title = title; self.htmlUrl = htmlUrl }
    }
    public let totalCount: Int
    public let items: [Issue]
    public init(totalCount: Int, items: [Issue]) { self.totalCount = totalCount; self.items = items }
}

public struct GitHubUser: Decodable, Sendable {
    public let login: String
}
