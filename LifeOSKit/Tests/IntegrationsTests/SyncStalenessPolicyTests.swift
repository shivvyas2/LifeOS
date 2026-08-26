import Testing
import Foundation
@testable import Integrations

@Suite struct SyncStalenessPolicyTests {
    /// Fixed calendar so a test never depends on the machine it runs on.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    @Test func neverHavingSyncedSyncs() {
        #expect(SyncStalenessPolicy.shouldSync(lastSync: nil, now: date(25, 9), calendar: calendar))
    }

    @Test func aRecentSyncFromEarlierTodayDoesNotSync() {
        #expect(SyncStalenessPolicy.shouldSync(
            lastSync: date(25, 9, 0), now: date(25, 9, 30), calendar: calendar
        ) == false)
    }

    @Test func aSyncOlderThanTheStaleWindowSyncs() {
        #expect(SyncStalenessPolicy.shouldSync(
            lastSync: date(25, 7, 0), now: date(25, 9, 30), calendar: calendar
        ))
    }

    /// The first open of the morning must pull the night's sleep even when the
    /// last sync was minutes before midnight. Staleness alone cannot see that
    /// a day boundary passed.
    @Test func aSyncFromYesterdaySyncsEvenWhenRecent() {
        #expect(SyncStalenessPolicy.shouldSync(
            lastSync: date(24, 23, 50), now: date(25, 0, 20), calendar: calendar
        ))
    }

    /// A last-sync in the future means the clock moved backwards. The record
    /// is meaningless, and syncing is the recovery that costs nothing.
    @Test func aLastSyncInTheFutureSyncs() {
        #expect(SyncStalenessPolicy.shouldSync(
            lastSync: date(25, 12, 0), now: date(25, 9, 0), calendar: calendar
        ))
    }
}
