import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class ActivityViewModel {
    private(set) var snapshot = ActivitySnapshot()
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
            let today = rows.first { calendar.isDate($0.date, inSameDayAs: end) }

            var byDay: [Date: Double] = [:]
            for row in rows {
                if let kcal = row.whoopCalories ?? row.activeEnergyKcal {
                    byDay[calendar.startOfDay(for: row.date)] = kcal
                }
            }
            var weekCalories: [DayValue] = []
            var cursor = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: end)
            while cursor <= last {
                weekCalories.append(DayValue(id: cursor, value: byDay[cursor]))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }

            snapshot = ActivitySnapshot(
                steps: today?.steps,
                exerciseMinutes: today?.exerciseMinutes,
                activeEnergyKcal: today?.activeEnergyKcal,
                restingHR: today?.restingHR,
                workouts: try store.workouts(on: selectedDate).map {
                    WorkoutSummary(
                        id: $0.externalID,
                        sport: $0.activityName,
                        durationMinutes: $0.durationMinutes,
                        strain: $0.strain,
                        averageHR: $0.averageHR,
                        distanceMeters: $0.distanceMeters,
                        percentRecorded: $0.percentRecorded
                    )
                },
                weekCalories: weekCalories
            )
        } catch {
            assertionFailure("Activity load failed: \(error)")
        }
    }
}
