import Foundation

public enum GitHubProjectError: Error, Equatable {
    case unauthorized, notFound, rateLimited
    case unavailable(Int)
}

public struct GitHubCommitItem: Decodable, Equatable, Sendable {
    public struct Commit: Decodable, Equatable, Sendable {
        public struct Author: Decodable, Equatable, Sendable {
            public let name: String
            public let date: Date
        }
        public let message: String
        public let author: Author
    }
    public let sha: String
    public let htmlUrl: URL
    public let commit: Commit
    public var subject: String { commit.message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
    public var authorName: String { commit.author.name }
    public var date: Date { commit.author.date }
    public var shortSHA: String { String(sha.prefix(7)) }
}

/// Everything a project reads from its repo, with the phone's own token.
public struct GitHubProjectSource: Sendable {
    let transport: any GitHubTransport
    let token: String
    let repo: String

    public init(transport: any GitHubTransport, token: String, repo: String) {
        self.transport = transport; self.token = token; self.repo = repo
    }

    private var owner: String { String(repo.split(separator: "/").first ?? "") }
    private var name: String { String(repo.split(separator: "/").dropFirst().first ?? "") }

    // MARK: Status (GraphQL)

    public func status() async throws -> GitHubProjectStatus {
        let first: DefaultReply = try await graphQL(Self.defaultQuery, ["owner": owner, "name": name])
        guard let repository = first.repository else { throw GitHubProjectError.notFound }
        let base = repository.defaultBranchRef?.name ?? "main"
        let second: StatusReply = try await graphQL(Self.statusQuery, ["owner": owner, "name": name, "base": base])
        guard let repo = second.repository else { throw GitHubProjectError.notFound }
        // `Ref.compare(headRef:)` takes this branch as the base and the
        // default branch as the head, so its behindBy is this branch's ahead.
        let branches = repo.refs.nodes.map {
            GitHubBranchState(name: $0.name, lastCommitAt: $0.target?.committedDate,
                              ahead: $0.compare?.behindBy ?? 0, behind: $0.compare?.aheadBy ?? 0)
        }
        let pulls = repo.pullRequests.nodes.compactMap { node -> GitHubPullState? in
            guard let state = GitHubPullState.State(rawValue: node.state.lowercased()) else { return nil }
            return GitHubPullState(number: node.number, title: node.title, state: state, url: node.url,
                                   mergedAt: node.mergedAt, headBranch: node.headRefName,
                                   headRepo: node.headRepository?.nameWithOwner,
                                   isCrossRepository: node.isCrossRepository ?? (node.headRepository == nil))
        }
        return GitHubProjectStatus(defaultBranch: base, branches: branches, pulls: pulls)
    }

    static let defaultQuery = """
    query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { defaultBranchRef { name } } }
    """

    static let statusQuery = """
    query($owner: String!, $name: String!, $base: String!) {
      repository(owner: $owner, name: $name) {
        refs(refPrefix: "refs/heads/", first: 100, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
          nodes { name target { ... on Commit { committedDate } } compare(headRef: $base) { aheadBy behindBy } }
        }
        pullRequests(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes { number title state url mergedAt headRefName isCrossRepository headRepository { nameWithOwner } }
        }
      }
    }
    """

    private struct Envelope<Payload: Decodable>: Decodable {
        struct Failure: Decodable { let type: String? }
        let data: Payload?
        let errors: [Failure]?
    }
    private struct DefaultReply: Decodable {
        struct Repository: Decodable { struct Ref: Decodable { let name: String }; let defaultBranchRef: Ref? }
        let repository: Repository?
    }
    private struct StatusReply: Decodable {
        struct Repository: Decodable {
            struct Refs: Decodable {
                struct Node: Decodable {
                    struct Target: Decodable { let committedDate: Date? }
                    struct Compare: Decodable { let aheadBy: Int; let behindBy: Int }
                    let name: String; let target: Target?; let compare: Compare?
                }
                let nodes: [Node]
            }
            struct Pulls: Decodable {
                struct Node: Decodable {
                    struct Head: Decodable { let nameWithOwner: String }
                    let number: Int; let title: String; let state: String; let url: URL
                    let mergedAt: Date?; let headRefName: String; let isCrossRepository: Bool?
                    let headRepository: Head?
                }
                let nodes: [Node]
            }
            let refs: Refs; let pullRequests: Pulls
        }
        let repository: Repository?
    }

    private func graphQL<Payload: Decodable>(_ query: String, _ variables: [String: String]) async throws -> Payload {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, status) = try await transport.post(URL(string: "https://api.github.com/graphql")!, body: body, token: token)
        try Self.check(status)
        guard let envelope = try? GitHubWire.decoder.decode(Envelope<Payload>.self, from: data) else {
            throw GitHubProjectError.unavailable(status)
        }
        if let errors = envelope.errors, !errors.isEmpty {
            if errors.contains(where: { $0.type == "RATE_LIMITED" }) { throw GitHubProjectError.rateLimited }
            if errors.contains(where: { $0.type == "NOT_FOUND" }) { throw GitHubProjectError.notFound }
        }
        guard let payload = envelope.data else { throw GitHubProjectError.unavailable(status) }
        return payload
    }

    // MARK: REST

    public func history(branch: String, page: Int) async throws -> [GitHubCommitItem] {
        let url = GitHubAPI.url("/repos/\(repo)/commits", query: [("sha", branch), ("per_page", "30"), ("page", "\(page)")])
        let (data, status) = try await transport.get(url, token: token)
        if status == 409 { return [] }   // an empty repository
        try Self.check(status)
        return (try? GitHubWire.decoder.decode([GitHubCommitItem].self, from: data)) ?? []
    }

    /// The commits `head` has that `base` does not; none when the branch is gone.
    public func branchCommits(base: String, head: String) async throws -> [GitHubCommitItem] {
        struct Reply: Decodable { let commits: [GitHubCommitItem] }
        let url = GitHubAPI.url("/repos/\(repo)/compare/\(base)...\(head)")
        let (data, status) = try await transport.get(url, token: token)
        if status == 404 { return [] }
        try Self.check(status)
        return ((try? GitHubWire.decoder.decode(Reply.self, from: data))?.commits ?? []).reversed()
    }

    /// The README as text, or nil when there is none or it cannot be read.
    public func readme() async -> String? {
        struct Reply: Decodable { let content: String; let encoding: String }
        guard let (data, status) = try? await transport.get(GitHubAPI.url("/repos/\(repo)/readme"), token: token),
              status == 200, let reply = try? GitHubWire.decoder.decode(Reply.self, from: data),
              reply.encoding == "base64",
              let decoded = Data(base64Encoded: reply.content.replacingOccurrences(of: "\n", with: "")) else { return nil }
        return String(data: decoded, encoding: .utf8)
    }

    /// Every repo the person can see, 100 a page, up to 10 pages.
    public static func repos(transport: any GitHubTransport, token: String) async throws -> [GitHubRepoRef] {
        var all: [GitHubRepoRef] = []
        for page in 1...10 {
            let url = GitHubAPI.url("/user/repos", query: [
                ("per_page", "100"), ("page", "\(page)"), ("sort", "pushed"),
                ("affiliation", "owner,collaborator,organization_member"),
            ])
            let (data, status) = try await transport.get(url, token: token)
            try check(status)
            let batch = (try? GitHubWire.decoder.decode([GitHubRepoRef].self, from: data)) ?? []
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw GitHubProjectError.unauthorized
        case 403, 429: throw GitHubProjectError.rateLimited
        case 404: throw GitHubProjectError.notFound
        default: throw GitHubProjectError.unavailable(status)
        }
    }
}
