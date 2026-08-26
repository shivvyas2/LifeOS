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

    /// Journal entries are note pages now, one per day.
    ///
    /// Appended to today's page rather than filed as a second entry: a person
    /// who writes twice in one evening means to add to what they said, and two
    /// rows dated the same day would break the "did I write today" question
    /// the streak is built on.
    func addJournal(_ text: String) {
        guard let context else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let store = NotesStore(context: context, calendar: calendar)
            let entry = try store.journalEntry()
            var blocks = entry.blocks.filter { !($0.kind == .paragraph && $0.isEmpty) }
            blocks.append(contentsOf: NoteBlockParser.blocks(fromMarkdown: trimmed))
            try store.update(entry, blocks: blocks)
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

            let notes = NotesStore(context: context, calendar: calendar)
            let journal = try notes.documents(includeArchived: false)
                .filter { $0.kind == .journal }
                .map { document in
                    JournalEntry(
                        id: document.id,
                        text: NoteBlockParser.excerpt(document.blocks, limit: 240),
                        date: document.entryDate ?? document.createdAt
                    )
                }
                .sorted { $0.date > $1.date }

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
