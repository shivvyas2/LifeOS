import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubDayCacheTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func defaults() -> UserDefaults {
        let name = "github.cache.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }
    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
    private let card = ProjectCard(repo: "r", repoURL: URL(string: "https://github.com/o/r")!, commitCount: 0,
                                   commits: [], isTodayWithoutCommits: false, followUp: nil)

    @Test func aPastDayFetchedAfterItEndedIsKept() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(6), calendar: calendar)
        let entry = cache.entry(for: day(5), calendar: calendar)!
        #expect(cache.isFresh(entry, for: day(5), now: day(30), calendar: calendar))
    }

    @Test func aPastDayFetchedBeforeItEndedIsStale() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(5), calendar: calendar)
        let entry = cache.entry(for: day(5), calendar: calendar)!
        #expect(!cache.isFresh(entry, for: day(5), now: day(7), calendar: calendar))
    }

    @Test func todayIsFreshForFiveMinutes() {
        let cache = GitHubDayCache(defaults: defaults())
        let now = day(7)
        cache.store(card, for: now, fetchedAt: now, calendar: calendar)
        let entry = cache.entry(for: now, calendar: calendar)!
        #expect(cache.isFresh(entry, for: now, now: now.addingTimeInterval(299), calendar: calendar))
        #expect(!cache.isFresh(entry, for: now, now: now.addingTimeInterval(301), calendar: calendar))
    }

    @Test func aDayWithNoCardIsRememberedAsNone() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(nil, for: day(5), fetchedAt: day(6), calendar: calendar)
        #expect(cache.entry(for: day(5), calendar: calendar) != nil)
        #expect(cache.entry(for: day(5), calendar: calendar)?.card == nil)
    }

    @Test func clearForgetsEverything() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(6), calendar: calendar)
        cache.clear()
        #expect(cache.entry(for: day(5), calendar: calendar) == nil)
    }
}
