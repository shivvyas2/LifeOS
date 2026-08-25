import Testing
import Foundation
@testable import Insights

@Suite struct BriefCacheTests {

    private let brief = DailyBrief(headline: "Fine.", observations: ["a", "b"])
    private let morning = Date(timeIntervalSince1970: 1_770_000_000)

    /// The cache buckets by calendar day, so tests must use a fixed calendar
    /// to be deterministic regardless of the host timezone. Using Calendar.current
    /// would pass or fail depending on where the test runs (e.g., a timestamp that
    /// is two hours before midnight locally might be 22 hours before midnight elsewhere).
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func theFirstCallGenerates() async {
        let cache = BriefCache(store: InMemoryBriefStore(), calendar: utc)
        let calls = Counter()

        let result = await cache.brief(for: morning) {
            await calls.increment()
            return .answered(self.brief)
        }

        #expect(result == .answered(brief))
        #expect(await calls.count == 1)
    }

    @Test func aSecondCallOnTheSameDayDoesNotGenerateAgain() async {
        let cache = BriefCache(store: InMemoryBriefStore(), calendar: utc)
        let calls = Counter()
        let generate: @Sendable () async -> CoachResult<DailyBrief> = {
            await calls.increment()
            return .answered(self.brief)
        }

        _ = await cache.brief(for: morning, generate: generate)
        let second = await cache.brief(for: morning.addingTimeInterval(6 * 3_600), generate: generate)

        #expect(second == .answered(brief))
        #expect(await calls.count == 1)
    }

    @Test func aNewDayGeneratesAgain() async {
        let cache = BriefCache(store: InMemoryBriefStore(), calendar: utc)
        let calls = Counter()
        let generate: @Sendable () async -> CoachResult<DailyBrief> = {
            await calls.increment()
            return .answered(self.brief)
        }

        _ = await cache.brief(for: morning, generate: generate)
        _ = await cache.brief(for: morning.addingTimeInterval(86_400), generate: generate)

        #expect(await calls.count == 2)
    }

    /// Caching a failure would strand the user without a brief until
    /// midnight, so only a real answer is kept.
    @Test func aFailureIsNotCached() async {
        let cache = BriefCache(store: InMemoryBriefStore(), calendar: utc)
        let calls = Counter()

        _ = await cache.brief(for: morning) {
            await calls.increment()
            return .unavailable
        }
        let second = await cache.brief(for: morning) {
            await calls.increment()
            return .answered(self.brief)
        }

        #expect(second == .answered(brief))
        #expect(await calls.count == 2)
    }
}

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}
