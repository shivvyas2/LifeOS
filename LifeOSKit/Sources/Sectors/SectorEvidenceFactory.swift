import Foundation
import Persistence

/// The one place that decides which scorer serves which sector, and the
/// month-shaped rules — Growth's targets, Soul's merge — that belong to
/// neither a single scorer nor the view model.
public enum SectorEvidenceFactory {
    public static func evidence(
        for sector: LifeSector,
        inputs: MonthInputs,
        answers: [String: String],
        calendar: Calendar = .current
    ) -> Evidence {
        switch sector {
        case .body:
            return BodyScorer(readings: inputs.readings, targets: inputs.targets).evidence()

        case .money:
            return MoneyScorer(
                amounts: inputs.amounts, previousAmounts: inputs.previousAmounts,
                budget: inputs.budget
            ).evidence()

        case .mission:
            return MissionScorer(
                statuses: inputs.planStatuses, habitTickRate: inputs.habitTickRate
            ).evidence()

        case .growth:
            let (met, total) = growthTargets(readings: inputs.readings, targets: inputs.targets)
            return GrowthScorer(
                goalStatuses: inputs.goalStatuses, targetsMet: met, targetsTotal: total
            ).evidence()

        case .mind:
            // Mind asks a check-in question (`mind.clarity`) exactly the way
            // Soul does, so it merges the same way: journal rows plus
            // check-in rows, never just one. Routing Mind to the journal
            // scorer alone would ask the question, store the answer, and
            // then silently drop it from the score, which is worse than not
            // asking at all.
            let journal = JournalScorer(
                sector: .mind, entryDates: inputs.journalDates, daysInMonth: inputs.daysInMonth,
                previousEntryCount: inputs.previousJournalCount, calendar: calendar
            ).evidence()
            let checkIn = CheckInScorer(sector: .mind, answers: answers).evidence()
            return Evidence(journal.rows + checkIn.rows)

        case .soul:
            // Soul is the one sector with two live sources: what got written
            // and what got answered at close. Neither alone is the whole
            // picture, so both sets of rows are kept, each under its own
            // label, and folded into the same weighted mean every other
            // sector's rows go through. Nothing is double counted: journal
            // rows ("days written", "vs last month") and check-in rows
            // ("how settled did you feel?", "one thing worth remembering")
            // never share a label or read the same underlying data.
            let journal = JournalScorer(
                sector: .soul, entryDates: inputs.journalDates, daysInMonth: inputs.daysInMonth,
                previousEntryCount: inputs.previousJournalCount, calendar: calendar
            ).evidence()
            let checkIn = CheckInScorer(sector: .soul, answers: answers).evidence()
            return Evidence(journal.rows + checkIn.rows)

        case .family, .romance, .friends:
            return CheckInScorer(sector: sector, answers: answers).evidence()
        }
    }

    /// How many of the four daily numeric targets (steps, sleep, exercise,
    /// water) the month's *average* met or exceeded, and how many of the
    /// four were tracked at all this month.
    ///
    /// A metric never logged all month is excluded from both counts rather
    /// than counted as a miss: an untracked metric reducing `targetsTotal`
    /// keeps it out of the reasoning entirely, the same way `BodyScorer`
    /// drops a day with no data instead of scoring it a failure. When none
    /// of the four were logged at all, `targetsTotal` comes back 0 and
    /// `GrowthScorer` adds no "targets met" row for it.
    private static func growthTargets(
        readings: [DayReading], targets: GoalTargets
    ) -> (met: Int, total: Int) {
        var met = 0
        var total = 0

        func check(_ values: [Double], goal: Double) {
            guard !values.isEmpty, goal > 0 else { return }
            total += 1
            let mean = values.reduce(0, +) / Double(values.count)
            if mean >= goal { met += 1 }
        }

        check(readings.compactMap { $0.steps.map(Double.init) }, goal: Double(targets.steps))
        check(
            readings.compactMap { $0.sleepMinutes.map(Double.init) },
            goal: Double(targets.sleepMinutes)
        )
        check(
            readings.compactMap { $0.exerciseMinutes.map(Double.init) },
            goal: Double(targets.exerciseMinutes)
        )
        check(readings.compactMap { $0.waterML }, goal: targets.waterML)

        return (met, total)
    }

    /// The share of habit-days ticked across every habit read for the month,
    /// flattened into one rate.
    ///
    /// `nil` when there were no habit-days to judge at all — no habits, or
    /// none with any days in range — so a person who has not started
    /// tracking habits is not silently scored zero.
    public static func habitTickRate(perHabitTicks: [[Bool]]) -> Double? {
        let flattened = perHabitTicks.flatMap { $0 }
        guard !flattened.isEmpty else { return nil }
        return Double(flattened.filter { $0 }.count) / Double(flattened.count)
    }
}
