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

            snapshot = WellnessSnapshot(
                averageSleepMinutes: avgSleep,
                workoutDays: workoutDays,
                workoutTarget: 7,
                averageExerciseMinutes: avgExercise,
                sleepVerdict: avgSleep.map { $0 >= 420 ? "Optimal" : ($0 >= 360 ? "Fair" : "Low") },
                trainingVerdict: workoutDays >= 4 ? "Consistent" : "Patchy"
            )
        } catch {
            assertionFailure("Wellness load failed: \(error)")
        }
    }
}
