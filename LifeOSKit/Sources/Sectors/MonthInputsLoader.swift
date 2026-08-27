import Foundation
import SwiftData
import Persistence

/// One month's store reads, assembled into the value every scorer consumes.
///
/// Lives here rather than on a view model because two surfaces need it: the
/// monthly close, which reads a month that has ended, and the board's
/// in-flight mode, which reads the month being lived. It is also the only way
/// this assembly gets tested at all, since the app target has no test target.
@MainActor
public enum MonthInputsLoader {
    public static func load(
        context: ModelContext, month: Date, now: Date = .now, calendar: Calendar = .current
    ) throws -> MonthInputs {
        let metricsStore = MetricsStore(context: context, calendar: calendar)
        let moneyStore = MoneyStore(context: context, calendar: calendar)
        let planStore = PlanStore(context: context, calendar: calendar)

        let window = MonthWindow(for: month, calendar: calendar)
        let progress = MonthProgress(window: window, now: now, calendar: calendar)

        let readings = try metricsStore.metrics(from: window.start, to: window.lastDay).map(\.reading)
        let targets = try metricsStore.goals().targets

        let monthEntries = try moneyStore.entries(from: window.start, to: window.lastDay)
        let amounts = monthEntries.filter { !$0.pending }.map(\.amount)

        let buckets = try moneyStore.buckets().map(BudgetBucket.init)
        let budget = buckets.isEmpty
            ? nil
            : BudgetPeriod.assess(buckets: buckets, lines: BudgetPeriod.lines(from: monthEntries))

        let goals = try planStore.entries(kind: .goal)
        let habits = try planStore.entries(kind: .habit)
        // Project pages carry what goals used to, so both feed the number.
        let projectPages = try NoteEvidence.projectStatuses(context: context)
        let pageStatuses = window.filter(projectPages, on: \.updatedAt).map(\.status)
        let goalStatuses = window.filter(goals, on: \.updatedAt).map(\.status) + pageStatuses
        let planStatuses = window.filter(goals + habits, on: \.updatedAt).map(\.status) + pageStatuses

        // Habits are judged only on days that have happened. `recentTicks`
        // reads a day with no tick as a miss, so running the window to the
        // end of a month still being lived would score every day still to
        // come as a habit already broken.
        let judgedDays = max(progress.elapsedDays, 0)
        let lastJudgedDay = min(window.lastDay, calendar.startOfDay(for: now))
        let perHabitTicks = judgedDays == 0 ? [] : try habits.map {
            try planStore.recentTicks(for: $0, days: judgedDays, endingOn: lastJudgedDay)
        }
        let habitTickRate = SectorEvidenceFactory.habitTickRate(perHabitTicks: perHabitTicks)

        // Journalling moved to note pages. Legacy plan entries are still read
        // and summed in, because months already closed were scored against
        // them and a migration must not silently rewrite a past score.
        let journalEntries = try planStore.entries(kind: .journal)
        let noteJournalDates = try NoteEvidence.journalDates(context: context)
        let journalDates = window.filter(journalEntries, on: \.createdAt).map(\.createdAt)
            + window.filter(noteJournalDates) { $0 }

        var previousAmounts: [Double] = []
        var previousJournalCount: Int?
        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) {
            let previousWindow = MonthWindow(for: previousMonth, calendar: calendar)
            previousAmounts = try moneyStore.entries(from: previousWindow.start, to: previousWindow.lastDay)
                .filter { !$0.pending }
                .map(\.amount)
            previousJournalCount = previousWindow.filter(journalEntries, on: \.createdAt).count
        }

        return MonthInputs(
            readings: readings, targets: targets,
            amounts: amounts, previousAmounts: previousAmounts, budget: budget,
            planStatuses: planStatuses, goalStatuses: goalStatuses,
            habitTickRate: habitTickRate,
            journalDates: journalDates, previousJournalCount: previousJournalCount,
            daysInMonth: window.daysInMonth
        )
    }
}
