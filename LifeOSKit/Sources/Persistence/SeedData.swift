import Foundation

/// Deterministic, plausible data so screens can be built and reviewed before
/// HealthKit and Whoop exist. Seeded only when the store is empty.
public enum SeedData {
    @MainActor
    public static func populate(store: MetricsStore, days: Int = 60, from today: Date = .now) throws {
        let calendar = Calendar.current
        let dates = (0..<days).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }

        // One save for all 60 days rather than one per day.
        try store.upsertBatch(dates: dates) { date, row in
            let offset = calendar.dateComponents([.day], from: date, to: today).day ?? 0

            // Deterministic pseudo-variation — no randomness, so previews are stable.
            let wobble = Double((offset * 37) % 100) / 100.0
            let slowLoss = Double(offset) * 0.02

            row.weightKg = 77.9 + slowLoss + (wobble - 0.5) * 0.6
            row.steps = Int(5_500 + wobble * 7_000)
            row.activeEnergyKcal = 320 + wobble * 500
            row.exerciseMinutes = Int(12 + wobble * 55)
            row.sleepMinutes = Int(360 + wobble * 130)
            row.restingHR = 52 + wobble * 9
            row.hrvMs = 45 + wobble * 55

            // Water is only sometimes logged, so the UI's missing-data path
            // is exercised rather than theoretical.
            row.waterML = offset % 3 == 0 ? nil : 1_400 + wobble * 1_600

            // Whoop stays empty until Plan 3 — Recovery must render its
            // empty state convincingly before the integration exists.
            row.whoopRecoveryPct = nil
            row.whoopDayStrain = nil
            row.whoopSleepPerformancePct = nil
        }
    }
}
