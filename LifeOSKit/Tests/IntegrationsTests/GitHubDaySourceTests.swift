import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubDaySourceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
    private var later: Date { day(20) }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "github.source.\(UUID().uuidString)")! }

    private func repoCommit(_ repo: String) -> String {
        """
        {"sha":"\(UUID().uuidString)","html_url":"https://github.com/o/\(repo)/commit/x",
         "commit":{"message":"work","author":{"date":"2026-10-05T09:00:00Z"}},
         "repository":{"name":"\(repo)","full_name":"o/\(repo)","html_url":"https://github.com/o/\(repo)"}}
        """
    }

    private func routes(_ transport: StubTransport, pinned: String) {
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(repoCommit("a"))]}"#),
            ("/repos/o/\(pinned)/milestones", 200, "[]"),
            ("/repos/o/\(pinned)", 200, #"{"name":"\#(pinned)","full_name":"o/\#(pinned)","html_url":"https://github.com/o/\#(pinned)"}"#),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
    }

    @Test func notConnectedHasNoCard() async {
        let source = GitHubDaySource(tokens: InMemoryGitHubTokenStore(), defaults: defaults(), transport: StubTransport(), calendar: calendar)
        #expect(await source.project(for: day(5), isToday: false, force: false, now: later) == nil)
    }

    @Test func thePinIsReadWhenAskedNotWhenMade() async {
        let store = defaults()
        let transport = StubTransport()
        let source = GitHubDaySource(tokens: InMemoryGitHubTokenStore(connection: .init(token: "t", login: "me")),
                                     defaults: store, transport: transport, calendar: calendar)
        store.set("o/p", forKey: GitHubDaySource.pinKey)
        routes(transport, pinned: "p")
        guard case .card(let first, _)? = await source.project(for: day(5), isToday: false, force: false, now: later) else {
            Issue.record("no card"); return
        }
        #expect(first.repo == "p")
        store.set("o/q", forKey: GitHubDaySource.pinKey)
        GitHubDayCache(defaults: store).clear()
        routes(transport, pinned: "q")
        guard case .card(let second, _)? = await source.project(for: day(5), isToday: false, force: false, now: later) else {
            Issue.record("no card"); return
        }
        #expect(second.repo == "q")
    }

    @Test func aDisconnectStopsTheCardAtOnce() async {
        let store = defaults()
        let tokens = InMemoryGitHubTokenStore(connection: .init(token: "t", login: "me"))
        let transport = StubTransport()
        routes(transport, pinned: "p")
        let source = GitHubDaySource(tokens: tokens, defaults: store, transport: transport, calendar: calendar)
        tokens.clear()
        #expect(await source.project(for: day(5), isToday: false, force: false, now: later) == nil)
    }

    @Test func aRevokedTokenIsRememberedOverCachedDays() async {
        let store = defaults()
        let transport = StubTransport()
        let source = GitHubDaySource(tokens: InMemoryGitHubTokenStore(connection: .init(token: "t", login: "me")),
                                     defaults: store, transport: transport, calendar: calendar)
        routes(transport, pinned: "a")
        _ = await source.project(for: day(4), isToday: false, force: false, now: later)   // cached, final
        transport.routes = [("/search/commits", 401, "")]
        #expect(await source.project(for: day(5), isToday: false, force: false, now: later) == .reconnect)
        #expect(GitHubDaySource.needsReconnect(store))
        let asked = transport.requested.count
        #expect(await source.project(for: day(4), isToday: false, force: false, now: later) == .reconnect)
        #expect(transport.requested.count == asked)
    }

    @Test func aForcedRefreshTriesAgainAndClearsTheFlag() async {
        let store = defaults()
        store.set(true, forKey: GitHubDaySource.needsReconnectKey)
        let transport = StubTransport()
        routes(transport, pinned: "a")
        let source = GitHubDaySource(tokens: InMemoryGitHubTokenStore(connection: .init(token: "t", login: "me")),
                                     defaults: store, transport: transport, calendar: calendar)
        guard case .card? = await source.project(for: day(5), isToday: false, force: true, now: later) else {
            Issue.record("no card"); return
        }
        #expect(!GitHubDaySource.needsReconnect(store))
    }

    @Test func aFailedRefreshShowsTheCachedCardWithItsTime() async {
        let store = defaults()
        let transport = StubTransport()
        routes(transport, pinned: "a")
        let source = GitHubDaySource(tokens: InMemoryGitHubTokenStore(connection: .init(token: "t", login: "me")),
                                     defaults: store, transport: transport, calendar: calendar)
        let today = day(20)
        _ = await source.project(for: today, isToday: true, force: false, now: today)
        transport.routes = [("/search/commits", 503, "")]
        guard case .card(_, let asOf)? = await source.project(for: today, isToday: true, force: true, now: today) else {
            Issue.record("no card"); return
        }
        #expect(asOf != nil)
    }
}
