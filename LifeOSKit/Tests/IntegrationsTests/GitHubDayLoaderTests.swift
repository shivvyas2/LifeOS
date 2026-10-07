import Testing
import Foundation
@testable import Integrations

private final class StubTransport: GitHubTransport, @unchecked Sendable {
    var routes: [(String, Int, String)] = []   // path prefix, status, body
    private(set) var requested: [URL] = []
    func get(_ url: URL, token: String) async throws -> (Data, Int) {
        requested.append(url)
        let path = url.path + "?" + (url.query ?? "")
        guard let route = routes.first(where: { path.hasPrefix($0.0) }) else { return (Data("{}".utf8), 404) }
        return (Data(route.2.utf8), route.1)
    }
}

@Suite struct GitHubDayLoaderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))! }
    private let connection = GitHubConnection(token: "t", login: "me")

    private func commit(_ repo: String, _ hour: Int, _ message: String = "work") -> String {
        """
        {"sha":"\(UUID().uuidString)","html_url":"https://github.com/o/\(repo)/commit/x",
         "commit":{"message":"\(message)","author":{"date":"2026-10-07T\(String(format: "%02d", hour)):00:00Z"}},
         "repository":{"name":"\(repo)","full_name":"o/\(repo)","html_url":"https://github.com/o/\(repo)"}}
        """
    }

    private func loader(_ transport: StubTransport, pin: String? = nil) -> GitHubDayLoader {
        GitHubDayLoader(transport: transport, connection: connection, pinnedRepo: pin, calendar: calendar)
    }

    @Test func theBusiestRepoWithItsMilestone() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9)),\#(commit("b", 10)),\#(commit("b", 11))]}"#),
            ("/repos/o/b/milestones", 200, #"[{"title":"1.1","open_issues":4,"closed_issues":5,"due_on":null,"html_url":"https://github.com/o/b/milestone/1"}]"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: false)
        guard case .card(let card, let asOf)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "b")
        #expect(card.commitCount == 2)
        #expect(asOf == nil)
        #expect(card.followUp == .milestone(title: "1.1", open: 4, total: 9, due: nil, url: URL(string: "https://github.com/o/b/milestone/1")!))
        #expect(!transport.requested.contains { $0.path.hasPrefix("/search/issues") })
    }

    @Test func withoutAMilestoneTheIssuesAreAsked() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/a/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":3,"items":[{"title":"Crash","html_url":"https://github.com/o/a/issues/9"}]}"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.followUp == .issues(count: 3, newest: [ProjectIssue(title: "Crash", url: URL(string: "https://github.com/o/a/issues/9")!)]))
        let issueQuery = transport.requested.first { $0.path == "/search/issues" }?.query ?? ""
        #expect(issueQuery.contains("is:issue") || issueQuery.contains("is%3Aissue"))
    }

    @Test func aPastDayWithoutCommitsHasNoCard() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 200, #"{"items":[]}"#)]
        let result = try await loader(transport).load(day: day, isToday: false)
        #expect(result.state == nil)
    }

    @Test func todayWithoutCommitsShowsTheLastPushedRepo() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[]}"#),
            ("/user/repos", 200, #"[{"name":"c","full_name":"o/c","html_url":"https://github.com/o/c","pushed_at":"2026-10-06T20:00:00Z"}]"#),
            ("/repos/o/c/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: true)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "c")
        #expect(card.isTodayWithoutCommits)
        #expect(card.followUp == nil)
    }

    @Test func thePinWinsEvenWithoutCommitsInIt() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/p/milestones", 200, "[]"),
            ("/repos/o/p", 200, #"{"name":"p","full_name":"o/p","html_url":"https://github.com/o/p"}"#),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport, pin: "o/p").load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "p")
        #expect(card.commitCount == 0)
        #expect(!result.pinMissing)
    }

    @Test func aMissingPinFallsBackToAutomatic() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/gone", 404, #"{"message":"Not Found"}"#),
            ("/repos/o/a/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport, pin: "o/gone").load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "a")
        #expect(result.pinMissing)
    }

    @Test func aRevokedTokenAsksToReconnect() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 401, #"{"message":"Bad credentials"}"#)]
        let result = try await loader(transport).load(day: day, isToday: true)
        #expect(result.state == .reconnect)
    }

    @Test func anOutageThrows() async {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 503, "")]
        await #expect(throws: GitHubLoadError.unavailable(503)) {
            _ = try await loader(transport).load(day: day, isToday: true)
        }
    }

    @Test func theSearchAsksForTheLocalDay() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 200, #"{"items":[]}"#)]
        _ = try await loader(transport).load(day: day, isToday: false)
        let query = URLComponents(url: transport.requested[0], resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
        #expect(query == "author:me author-date:2026-10-07T00:00:00Z..2026-10-07T23:59:59Z")
    }
}
