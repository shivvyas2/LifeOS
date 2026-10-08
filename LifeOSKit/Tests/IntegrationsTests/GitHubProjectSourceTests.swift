import Testing
import Foundation
@testable import Integrations

/// GET routes by path prefix, and GraphQL replies by a substring of the query.
final class ProjectStubTransport: GitHubTransport, @unchecked Sendable {
    var gets: [(String, Int, String)] = []
    var posts: [(String, Int, String)] = []
    private(set) var requested: [URL] = []
    private(set) var queries: [String] = []

    func get(_ url: URL, token: String) async throws -> (Data, Int) {
        requested.append(url)
        let path = url.path + "?" + (url.query ?? "")
        guard let route = gets.first(where: { path.hasPrefix($0.0) }) else { return (Data("{}".utf8), 404) }
        return (Data(route.2.utf8), route.1)
    }

    func post(_ url: URL, body: Data, token: String) async throws -> (Data, Int) {
        let query = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["query"] as? String ?? ""
        queries.append(query)
        guard let reply = posts.first(where: { query.contains($0.0) }) else { return (Data("{}".utf8), 500) }
        return (Data(reply.2.utf8), reply.1)
    }
}

@Suite struct GitHubProjectSourceTests {
    private let defaultQuery = #"{"data":{"repository":{"defaultBranchRef":{"name":"develop"}}}}"#
    private let statusReply = """
    {"data":{"repository":{
      "refs":{"nodes":[
        {"name":"feat/cards","target":{"committedDate":"2026-10-07T10:00:00Z"},"compare":{"aheadBy":2,"behindBy":5}},
        {"name":"develop","target":{"committedDate":"2026-10-06T10:00:00Z"},"compare":{"aheadBy":0,"behindBy":0}}
      ]},
      "pullRequests":{"nodes":[
        {"number":42,"title":"Cards","state":"OPEN","url":"https://github.com/o/r/pull/42","mergedAt":null,
         "headRefName":"feat/cards","headRepository":{"nameWithOwner":"o/r"}},
        {"number":40,"title":"Old","state":"MERGED","url":"https://github.com/o/r/pull/40","mergedAt":"2026-10-01T09:00:00Z",
         "headRefName":"feat/sign-in","headRepository":null}
      ]}
    }}}
    """
    private func source(_ t: ProjectStubTransport, repo: String = "o/r") -> GitHubProjectSource {
        GitHubProjectSource(transport: t, token: "t", repo: repo)
    }

    /// Review Focus 2: the default branch is read, not assumed to be main.
    /// `Ref.compare(headRef:)` takes the branch as base: its behindBy is what
    /// the branch has that the default does not.
    @Test func statusReadsTheRealDefaultBranchAndFlipsCompare() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, defaultQuery), ("refs(", 200, statusReply)]
        let status = try await source(t).status()
        #expect(status.defaultBranch == "develop")
        let cards = try #require(status.branches.first { $0.name == "feat/cards" })
        #expect(cards.ahead == 5 && cards.behind == 2)
        #expect(status.pulls.map(\.number) == [42, 40])
        #expect(status.pulls[0].state == .open && status.pulls[0].headRepo == "o/r")
        #expect(status.pulls[1].state == .merged && status.pulls[1].headRepo == nil)
        #expect(t.queries.last?.contains("develop") == false, "the default branch goes in variables, not the query text")
    }

    @Test func aMissingRepoIsNotFound() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, #"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND"}]}"#)]
        await #expect(throws: GitHubProjectError.notFound) { _ = try await source(t).status() }
    }

    @Test func aRevokedTokenIsUnauthorized() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 401, "{}")]
        await #expect(throws: GitHubProjectError.unauthorized) { _ = try await source(t).status() }
    }

    @Test func aRateLimitIsItsOwnError() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, #"{"errors":[{"type":"RATE_LIMITED"}]}"#)]
        await #expect(throws: GitHubProjectError.rateLimited) { _ = try await source(t).status() }
        t.posts = [("defaultBranchRef", 403, "{}")]
        await #expect(throws: GitHubProjectError.rateLimited) { _ = try await source(t).status() }
    }

    /// Review Focus 3: an empty repository has no history, not an error.
    @Test func anEmptyRepoHasNoHistory() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/commits", 409, #"{"message":"Git Repository is empty."}"#)]
        #expect(try await source(t).history(branch: "main", page: 1).isEmpty)
    }

    @Test func historyPagesThirtyAtATime() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/commits", 200, """
        [{"sha":"abc1234def","html_url":"https://github.com/o/r/commit/abc",
          "commit":{"message":"feat: cards\\n\\nbody","author":{"name":"Shiv","date":"2026-10-07T10:00:00Z"}}}]
        """)]
        let page = try await source(t).history(branch: "develop", page: 2)
        #expect(page.first?.subject == "feat: cards")
        #expect(page.first?.authorName == "Shiv")
        let query = try #require(t.requested.first?.query)
        #expect(query.contains("sha=develop") && query.contains("per_page=30") && query.contains("page=2"))
    }

    /// Review Focus 5: odd branch names reach GitHub encoded.
    @Test func branchNamesAreEncodedInCompare() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/compare/", 200, #"{"commits":[]}"#)]
        _ = try await source(t).branchCommits(base: "main", head: "fix/50% faster #2")
        let url = try #require(t.requested.first)
        #expect(url.absoluteString.contains("fix/50%25%20faster%20%232"))
    }

    @Test func aDeletedBranchHasNoCommits() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/compare/", 404, "{}")]
        #expect(try await source(t).branchCommits(base: "main", head: "gone").isEmpty)
    }

    @Test func reposPageUntilAShortPage() async throws {
        let t = ProjectStubTransport()
        let full = "[" + (0..<100).map { #"{"name":"r\#($0)","full_name":"o/r\#($0)","html_url":"https://github.com/o/r\#($0)"}"# }
            .joined(separator: ",") + "]"
        t.gets = [("/user/repos?per_page=100&page=1", 200, full),
                  ("/user/repos?per_page=100&page=2", 200, #"[{"name":"last","full_name":"o/last","html_url":"https://github.com/o/last"}]"#)]
        let repos = try await GitHubProjectSource.repos(transport: t, token: "t")
        #expect(repos.count == 101)
        #expect(t.requested.count == 2)
    }

    @Test func theReadmeIsDecodedFromBase64() async throws {
        let t = ProjectStubTransport()
        let encoded = Data("# LifeOS\nA home for your life.".utf8).base64EncodedString()
        t.gets = [("/repos/o/r/readme", 200, #"{"content":"\#(encoded)","encoding":"base64"}"#)]
        #expect(await source(t).readme() == "# LifeOS\nA home for your life.")
        t.gets = []
        #expect(await source(t).readme() == nil)
    }
}
