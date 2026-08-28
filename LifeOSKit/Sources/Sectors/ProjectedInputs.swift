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

    /// The ceiling: every remaining day hits the person's own targets.
    ///
    /// Not a theoretical maximum. A ceiling built from `GoalTargets` is
    /// reachable by definition, which is the only kind of ceiling worth
    /// showing someone, and it is what makes setting a target consequential.
    public static func perfect(
        _ inputs: MonthInputs, progress: MonthProgress, calendar: Calendar = .current
    ) -> MonthInputs {
        apply(Lever.allCases, to: inputs, progress: progress, calendar: calendar)
    }

    /// One lever perfected, everything else coasting. The difference between
    /// this and `coasting` is what that lever is worth.
    public static func perfecting(
        _ lever: Lever, in inputs: MonthInputs, progress: MonthProgress,
        calendar: Calendar = .current
    ) -> MonthInputs {
        apply([lever], to: inputs, progress: progress, calendar: calendar)
    }

    /// Coast first, then overwrite only the dimensions named. Building every
    /// projection on the coast means a lever's delta is never contaminated by
    /// a second lever quietly improving alongside it.
    private static func apply(
        _ levers: [Lever], to inputs: MonthInputs, progress: MonthProgress, calendar: Calendar
    ) -> MonthInputs {
        guard progress.remainingDays > 0, progress.elapsedDays > 0 else { return inputs }
        let remaining = Double(progress.remainingDays)
        let elapsed = Double(progress.elapsedDays)
        let chosen = Set(levers)

        var projected = coasting(inputs, progress: progress, calendar: calendar)
        let targets = inputs.targets

        if let average = averageReading(inputs.readings) {
            var tail = average
            // Only a metric that was tracked gets raised. Perfecting a metric
            // the person never logs would invent days on target out of
            // nothing and hand back a ceiling they cannot act on.
            // `max` against the running average, never a bare assignment. A
            // person already averaging 20,000 steps against an 8,000 target
            // would otherwise be "perfected" down to 8,000, and a ceiling
            // that asks someone to do less than they are already doing is
            // not a ceiling.
            if chosen.contains(.sleep), Lever.sleep.tracked(in: inputs) {
                tail.sleepMinutes = max(average.sleepMinutes ?? 0, targets.sleepMinutes)
            }
            if chosen.contains(.exercise), Lever.exercise.tracked(in: inputs) {
                tail.exerciseMinutes = max(average.exerciseMinutes ?? 0, targets.exerciseMinutes)
            }
            if chosen.contains(.steps), Lever.steps.tracked(in: inputs) {
                tail.steps = max(average.steps ?? 0, targets.steps)
            }
            if chosen.contains(.water), Lever.water.tracked(in: inputs) {
                tail.waterML = max(average.waterML ?? 0, targets.waterML)
            }
            projected.readings = inputs.readings
                + Array(repeating: tail, count: progress.remainingDays)
        }

        if chosen.contains(.spend), let report = inputs.budget {
            // Spend up to each limit and no further. A bucket already blown
            // keeps the spend it has: a perfect finish cannot unspend money.
            let allowance = report.rows.reduce(0) { $0 + max(0, $1.limit - $1.spent) }
            projected.budget = BudgetReport(
                rows: report.rows.map { row in
                    let spent = max(row.spent, row.limit)
                    return BudgetReport.Row(
                        id: row.id, name: row.name, limit: row.limit, spent: spent,
                        adherence: BudgetPeriod.adherence(spent: spent, limit: row.limit)
                    )
                },
                unclaimed: report.unclaimed
            )

            // Income is not a lever, so it keeps coasting; only the outflow
            // is replaced, and the saving-rate row then describes the same
            // month the budget rows do.
            let earned = inputs.amounts.filter { $0 > 0 }.reduce(0, +)
            projected.amounts = inputs.amounts
            if earned > 0 { projected.amounts.append(earned / elapsed * remaining) }
            if allowance > 0 { projected.amounts.append(-allowance) }
        }

        if chosen.contains(.journal), Lever.journal.tracked(in: inputs) {
            projected.journalDates = inputs.journalDates
                + progress.remainingDates(calendar: calendar)
        }

        if chosen.contains(.habits), let rate = inputs.habitTickRate {
            // Assumes a habit-day per day, which is what `recentTicks`
            // produces: one flag per day per habit.
            projected.habitTickRate = ((rate * elapsed) + remaining) / (elapsed + remaining)
        }

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
