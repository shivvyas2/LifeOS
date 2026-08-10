import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class WellnessViewModel {
    private(set) var snapshot = WellnessSnapshot()
    var selectedDate: Date = .now

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func select(_ date: Date) {
        selectedDate = date
        load()
    }

    /// A journal entry is dated so it can sit on the daily spine later; the
    /// text is the title because an entry has no separate name.
    func addJournal(_ text: String) {
        guard let context else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try PlanStore(context: context, calendar: calendar)
                .add(kind: .journal, title: trimmed, dueDate: .now)
            load()
        } catch {
            assertionFailure("Journal add failed: \(error)")
        }
    }

    func load() {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)

        do {
            let end = selectedDate
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            let rows = try store.metrics(from: start, to: end)

            let sleeps = rows.compactMap(\.sleepMinutes)
            let exercises = rows.compactMap(\.exerciseMinutes)
            let avgSleep = sleeps.isEmpty ? nil : sleeps.reduce(0, +) / sleeps.count
            let avgExercise = exercises.isEmpty ? nil : exercises.reduce(0, +) / exercises.count
            let workoutDays = exercises.count { $0 >= 20 }

            let planStore = PlanStore(context: context, calendar: calendar)
            let entries = try planStore.entries(kind: .journal)
            let journal = entries.compactMap { entry -> JournalEntry? in
                guard let date = entry.dueDate else { return nil }
                return JournalEntry(id: entry.id, text: entry.title, date: date)
            }.sorted { $0.date > $1.date }

            snapshot = WellnessSnapshot(
                averageSleepMinutes: avgSleep,
                workoutDays: workoutDays,
                workoutTarget: 7,
                averageExerciseMinutes: avgExercise,
                sleepVerdict: avgSleep.map { $0 >= 420 ? "Optimal" : ($0 >= 360 ? "Fair" : "Low") },
                trainingVerdict: workoutDays >= 4 ? "Consistent" : "Patchy",
                journal: journal,
                hasEntryToday: journal.contains { calendar.isDateInToday($0.date) }
            )
        } catch {
            assertionFailure("Wellness load failed: \(error)")
        }
    }
}
