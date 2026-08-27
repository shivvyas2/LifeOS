import Foundation
import SwiftData

/// Removes the fabricated health history the app used to seed on first launch.
///
/// Until this ran, a fresh install wrote sixty days of plausible-looking
/// weight, sleep, resting heart rate and HRV so the screens had something to
/// draw before HealthKit and Whoop existed. Leaving that in place once the
/// integrations were real did more than look wrong.
///
/// It actively suppressed the real numbers. Most of those fields are
/// `fillGapsOnly` in `HealthFill`, meaning Apple Health writes them only where
/// the day has no value yet, because a background sync must not overwrite
/// something a person typed. A seeded value is indistinguishable from a typed
/// one, so every seeded day refused the real reading for as long as it existed.
/// Steps, active energy and exercise minutes were corrected on the next sync,
/// being `healthIsTheSource`; nothing else ever was.
///
/// Only `DailyMetrics` is removed, and it is the one table safe to remove:
/// the schema calls it derived state, recomputable from the workout, sleep and
/// Whoop records that roll up into it. Those are left untouched, so a resync
/// rebuilds the days from the same sources that produced them.
///
/// The cost, stated plainly: water and weight entered by hand through Quick Log
/// are the only values with no source behind them, and they go too. There is no
/// way to tell a hand-typed weight from a seeded one, and leaving the seeded
/// ones behind to protect the typed ones would defeat the purpose.
@MainActor
public enum SampleMetricsPurge {

    /// Deletes every daily row. Returns how many were removed, for the log
    /// line: a purge that silently did nothing is the failure worth seeing.
    @discardableResult
    public static func run(context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<DailyMetrics>())
        guard !rows.isEmpty else { return 0 }

        rows.forEach(context.delete)
        try context.save()
        return rows.count
    }
}
