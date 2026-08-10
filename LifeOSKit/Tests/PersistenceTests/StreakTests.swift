import Testing
@testable import Persistence

@Suite struct StreakTests {
    @Test func countsConsecutiveOnTargetDaysFromMostRecent() {
        #expect(currentStreak(statuses: [.onTarget, .onTarget, .onTarget, .missed]) == 3)
    }

    @Test func aMissEndsTheStreakImmediately() {
        #expect(currentStreak(statuses: [.missed, .onTarget, .onTarget]) == 0)
    }

    /// A day with no data neither extends nor breaks a streak.
    @Test func noDataDaysAreSkipped() {
        #expect(currentStreak(statuses: [.onTarget, .noData, .onTarget, .missed]) == 2)
    }

    @Test func leadingNoDataDoesNotBreakTheStreak() {
        #expect(currentStreak(statuses: [.noData, .onTarget, .onTarget]) == 2)
    }

    @Test func emptyHistoryIsZero() {
        #expect(currentStreak(statuses: []) == 0)
    }
}
