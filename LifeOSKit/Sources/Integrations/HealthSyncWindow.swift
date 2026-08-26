import Foundation

/// Which days a Health sync should re-read.
///
/// Pure, because the alternative is discovering the rule was wrong by noticing
/// that a week of steps stayed blank. A day that is never re-read keeps
/// whatever it had, silently.
public enum HealthSyncWindow {

    /// The furthest back a sync will ever go.
    ///
    /// Thirty days is the month the dot grid shows. Going further would spend
    /// ten queries a day on history no screen displays, and Health keeps the
    /// data regardless, so a longer backfill can be added the day something
    /// needs it.
    public static let backfillDays = 30

    /// Days to re-read, oldest first.
    ///
    /// Always includes today, because a step count climbs until midnight and a
    /// sync at breakfast is stale by lunch. Includes the day of the last sync
    /// as well as the days since: a night's sleep is recorded against the
    /// morning it ends, so the day already covered can still gain a value after
    /// it was read.
    public static func days(
        since lastSync: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)

        guard let lastSync else {
            return backfill(endingAt: today, calendar: calendar)
        }

        let lastDay = calendar.startOfDay(for: lastSync)
        // A stamp from the future means a clock change, not a sync that has not
        // happened. Trusting it would skip today entirely.
        guard lastDay <= today else { return [today] }

        let elapsed = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        guard elapsed < backfillDays else {
            return backfill(endingAt: today, calendar: calendar)
        }

        return (0...elapsed)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .sorted()
    }

    private static func backfill(endingAt today: Date, calendar: Calendar) -> [Date] {
        (0..<backfillDays)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .sorted()
    }
}
