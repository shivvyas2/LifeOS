import Foundation
import Persistence

/// Alternate versions of one month's inputs: what the month becomes if the
/// remaining days go one way rather than another.
///
/// Nothing here scores anything. Every projection is handed back to
/// `SectorEvidenceFactory`, which is the only thing in the app that turns
/// inputs into a number, so a projected score and a closed score are produced
/// by the same arithmetic and cannot drift apart.
public enum ProjectedInputs {

    /// The floor: the rest of the month looks like the part already lived.
    ///
    /// Deliberately not an empty tail. For Body the two are nearly the same,
    /// since `BodyScorer` counts only days that carry data. For Money they
    /// are opposites: spending nothing for the rest of the month is the best
    /// case, so an empty tail would put the floor above the ceiling and
    /// invert the card. One definition serves every sector, and this is the
    /// one that reads correctly for spend.
    public static func coasting(
        _ inputs: MonthInputs, progress: MonthProgress, calendar: Calendar = .current
    ) -> MonthInputs {
        guard progress.remainingDays > 0, progress.elapsedDays > 0 else { return inputs }
        let remaining = Double(progress.remainingDays)
        let elapsed = Double(progress.elapsedDays)

        var projected = inputs

        if let average = averageReading(inputs.readings) {
            projected.readings += Array(repeating: average, count: progress.remainingDays)
        }

        let earned = inputs.amounts.filter { $0 > 0 }.reduce(0, +)
        let spent = -inputs.amounts.filter { $0 < 0 }.reduce(0, +)
        if earned > 0 { projected.amounts.append(earned / elapsed * remaining) }
        if spent > 0 { projected.amounts.append(-(spent / elapsed * remaining)) }

        projected.budget = inputs.budget.map { report in
            scaled(report, by: (elapsed + remaining) / elapsed)
        }

        let daysWritten = Set(inputs.journalDates.map { calendar.startOfDay(for: $0) }).count
        let extraDays = Int((Double(daysWritten) / elapsed * remaining).rounded())
        projected.journalDates += progress.remainingDates(calendar: calendar).prefix(extraDays)

        return projected
    }

    /// The mean of every metric that was logged at all this month. A metric
    /// never logged stays nil rather than becoming a zero, so an untracked
    /// number cannot start arguing against the person in the projection when
    /// it was excluded from the real score.
    static func averageReading(_ readings: [DayReading]) -> DayReading? {
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        let steps = mean(readings.compactMap { $0.steps.map(Double.init) })
        let sleep = mean(readings.compactMap { $0.sleepMinutes.map(Double.init) })
        let exercise = mean(readings.compactMap { $0.exerciseMinutes.map(Double.init) })
        let water = mean(readings.compactMap(\.waterML))

        guard steps != nil || sleep != nil || exercise != nil || water != nil else { return nil }
        return DayReading(
            steps: steps.map { Int($0.rounded()) },
            sleepMinutes: sleep.map { Int($0.rounded()) },
            exerciseMinutes: exercise.map { Int($0.rounded()) },
            waterML: water
        )
    }

    /// Every bucket's spend grown by the same factor, with adherence
    /// recomputed through `BudgetPeriod`'s own rule rather than a second copy
    /// of it.
    static func scaled(_ report: BudgetReport, by factor: Double) -> BudgetReport {
        BudgetReport(
            rows: report.rows.map { row in
                let spent = row.spent * factor
                return BudgetReport.Row(
                    id: row.id, name: row.name, limit: row.limit, spent: spent,
                    adherence: BudgetPeriod.adherence(spent: spent, limit: row.limit)
                )
            },
            unclaimed: report.unclaimed
        )
    }
}
