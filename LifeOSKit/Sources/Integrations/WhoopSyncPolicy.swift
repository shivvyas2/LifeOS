import Foundation

/// Decides whether an automatic sync is due, so the app can refresh itself on
/// becoming active instead of waiting for a tap on "Sync now".
///
/// Two clocks matter, not one. Staleness handles the common case: data older
/// than an hour is worth refreshing. The day boundary handles the one that
/// matters most: the first open of the morning must pull the night's sleep,
/// and a sync from 23:50 is only minutes old while still knowing nothing
/// about the night.
public enum WhoopSyncPolicy {
    public static func shouldSync(
        lastSync: Date?,
        now: Date = .now,
        calendar: Calendar = .current,
        staleAfter: TimeInterval = 3_600
    ) -> Bool {
        guard let lastSync else { return true }
        // A future last-sync means the clock moved backwards; the record is
        // meaningless and syncing is the recovery that costs nothing.
        guard lastSync <= now else { return true }
        if lastSync < calendar.startOfDay(for: now) { return true }
        return now.timeIntervalSince(lastSync) > staleAfter
    }
}
