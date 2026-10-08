import Testing
import Foundation
@testable import Integrations

@Suite @MainActor struct GitHubStatusCacheTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private let status = GitHubProjectStatus(defaultBranch: "main", branches: [], pulls: [])

    /// Review fix 9: a private repo read for one GitHub account is never
    /// handed to another on the same phone.
    @Test func anotherAccountMisses() {
        let cache = GitHubStatusCache()
        cache.store(status, login: "shiv", repo: "o/r", at: now)
        #expect(cache.fresh(login: "shiv", repo: "O/R", now: now) != nil)
        #expect(cache.fresh(login: "someone", repo: "o/r", now: now) == nil)
        #expect(cache.latest(login: "someone", repo: "o/r") == nil)
    }

    @Test func aReadGoesStaleAfterFiveMinutes() {
        let cache = GitHubStatusCache()
        cache.store(status, login: "shiv", repo: "o/r", at: now)
        #expect(cache.fresh(login: "shiv", repo: "o/r", now: now.addingTimeInterval(299)) != nil)
        #expect(cache.fresh(login: "shiv", repo: "o/r", now: now.addingTimeInterval(301)) == nil)
        #expect(cache.latest(login: "shiv", repo: "o/r") != nil, "the card's last-commit line may use an old read")
    }

    @Test func disconnectingForgetsEverything() {
        let cache = GitHubStatusCache()
        cache.store(status, login: "shiv", repo: "o/r", at: now)
        cache.clear()
        #expect(cache.latest(login: "shiv", repo: "o/r") == nil)
    }
}
