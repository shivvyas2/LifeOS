import Testing
import Foundation
@testable import Integrations

/// Which days a Health sync should re-read.
///
/// Not simply "today": steps climb all day, a night's sleep lands the next
/// morning, and a phone that was off for a week owes a backfill. Getting this
/// wrong is invisible, because a day that is never re-read just quietly keeps
/// whatever it had.
@Suite struct HealthSyncWindowTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_787_700_000)   // a fixed afternoon

    private func days(since last: Date?) -> [Date] {
        HealthSyncWindow.days(since: last, now: now, calendar: calendar)
    }

    /// A first sync backfills, so the app does not open on a month of blanks
    /// next to a Whoop history that goes back years.
    @Test func aFirstSyncBackfillsAMonth() {
        let window = days(since: nil)

        #expect(window.count == 30)
    }

    /// Today is always included, even when it was synced a minute ago: the step
    /// count is still climbing.
    @Test func todayIsAlwaysIncluded() {
        let today = calendar.startOfDay(for: now)

        #expect(days(since: now).contains(today))
        #expect(days(since: nil).contains(today))
        #expect(days(since: calendar.date(byAdding: .day, value: -3, to: now)!).contains(today))
    }

    /// A sync minutes ago costs one day of work, not thirty.
    @Test func aRecentSyncOnlyRereadsToday() {
        #expect(days(since: now).count == 1)
    }

    /// A gap is re-read in full. Sleep for a night lands the following morning,
    /// so the day before the gap has to be revisited too.
    @Test func aGapIsBackfilledIncludingTheDayBeforeIt() {
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        let window = days(since: threeDaysAgo)

        // Three elapsed days, today, and the day the last sync itself covered.
        #expect(window.count == 4)
        #expect(window.contains(calendar.startOfDay(for: threeDaysAgo)))
    }

    /// A phone left off for a year does not re-read a year.
    @Test func averyOldSyncIsCappedAtTheBackfillLimit() {
        let longAgo = calendar.date(byAdding: .day, value: -400, to: now)!

        #expect(days(since: longAgo).count == 30)
    }

    /// Never tomorrow. HealthKit has nothing there, and writing a row for it
    /// would put an empty day on the calendar ahead of the user.
    @Test func theWindowNeverReachesIntoTheFuture() {
        let today = calendar.startOfDay(for: now)

        for day in days(since: nil) {
            #expect(day <= today)
        }
    }

    /// Oldest first, so a caller writing them in order leaves the newest write
    /// last and the day's row ends up reflecting today.
    @Test func daysRunOldestFirst() {
        let window = days(since: nil)

        #expect(window == window.sorted())
    }

    /// A clock that has gone backwards, or a last-sync stamp from the future,
    /// must not produce an empty window or a negative range.
    @Test func afutureLastSyncStillSyncsToday() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        let window = days(since: tomorrow)

        #expect(window == [calendar.startOfDay(for: now)])
    }
}
