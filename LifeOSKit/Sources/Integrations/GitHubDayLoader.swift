import Foundation

public protocol GitHubTransport: Sendable {
    func get(_ url: URL, token: String) async throws -> (Data, Int)
}

public struct URLSessionGitHubTransport: GitHubTransport {
    public init() {}
    public func get(_ url: URL, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum GitHubLoadError: Error, Equatable {
    case unavailable(Int)
}

public enum GitHubAPI {
    public static func url(_ path: String, query: [(String, String)] = []) -> URL {
        var components = URLComponents(string: "https://api.github.com")!
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
            // URLComponents leaves `+` alone, and GitHub reads a bare `+` in a
            // query as a space: `+05:30` would arrive as ` 05:30`.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }
}

/// The day's project card: two or three requests, decided by the builder.
public struct GitHubDayLoader: Sendable {
    public struct Result: Equatable, Sendable {
        public let state: ProjectCardState?
        public let pinMissing: Bool
    }

    private struct Unauthorized: Error {}
    private struct NotFound: Error {}

    let transport: any GitHubTransport
    let connection: GitHubConnection
    let pinnedRepo: String?
    let calendar: Calendar

    public init(transport: any GitHubTransport, connection: GitHubConnection, pinnedRepo: String?, calendar: Calendar = .current) {
        self.transport = transport; self.connection = connection; self.pinnedRepo = pinnedRepo; self.calendar = calendar
    }

    public func load(day: Date, isToday: Bool) async throws -> Result {
        do {
            let search: GitHubCommitSearch = try await get(GitHubAPI.url("/search/commits", query: [
                ("q", GitHubDay.commitQuery(login: connection.login, day: day, calendar: calendar)),
                ("sort", "author-date"), ("order", "desc"), ("per_page", "100"),
            ]))
            var pinMissing = false
            var repo: GitHubRepoRef?
            if let pinnedRepo {
                if let match = search.items.first(where: { $0.repository.fullName == pinnedRepo })?.repository {
                    repo = match
                } else {
                    do { repo = try await get(GitHubAPI.url("/repos/\(pinnedRepo)")) as GitHubRepoRef }
                    catch is NotFound { pinMissing = true }
                }
            }
            if repo == nil { repo = ProjectCardBuilder.busiestRepo(in: search.items) }
            if repo == nil, isToday {
                let recent: [GitHubRepoRef] = try await get(GitHubAPI.url("/user/repos", query: [
                    ("sort", "pushed"), ("per_page", "1"),
                ]))
                repo = recent.first
            }
            guard let repo else { return Result(state: nil, pinMissing: pinMissing) }

            // The follow-up is extra: a repo with Issues turned off (most forks)
            // or a hiccup on these calls costs the line, never the commits.
            // Only a revoked token stops the card.
            let milestones: [GitHubMilestone] = (try await optional(GitHubAPI.url("/repos/\(repo.fullName)/milestones", query: [
                ("state", "open"), ("per_page", "10"),
            ]))) ?? []
            var issues: GitHubIssueSearch?
            if milestones.isEmpty {
                issues = try await optional(GitHubAPI.url("/search/issues", query: [
                    ("q", "repo:\(repo.fullName) is:issue is:open"), ("sort", "created"), ("order", "desc"), ("per_page", "2"),
                ]))
            }
            let card = ProjectCardBuilder.card(
                repo: repo, commits: ProjectCardBuilder.commits(in: search.items, repo: repo.fullName),
                isToday: isToday, followUp: ProjectCardBuilder.followUp(milestones: milestones, issues: issues))
            return Result(state: .card(card, asOf: nil), pinMissing: pinMissing)
        } catch is Unauthorized {
            return Result(state: .reconnect, pinMissing: false)
        }
    }

    /// Nil for any failure but a revoked token.
    private func optional<Value: Decodable>(_ url: URL) async throws -> Value? {
        do { return try await get(url) as Value }
        catch is Unauthorized { throw Unauthorized() }
        catch { return nil }
    }

    private func get<Value: Decodable>(_ url: URL) async throws -> Value {
        let (data, status) = try await transport.get(url, token: connection.token)
        switch status {
        case 200..<300: return try GitHubWire.decoder.decode(Value.self, from: data)
        case 401: throw Unauthorized()
        case 404: throw NotFound()
        default: throw GitHubLoadError.unavailable(status)
        }
    }
}
