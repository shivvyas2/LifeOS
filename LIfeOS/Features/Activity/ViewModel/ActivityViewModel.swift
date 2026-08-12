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
            // One day only. This section shows no history.
            let today = try store.metrics(from: selectedDate, to: selectedDate).first
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
                }
            )
        } catch {
            assertionFailure("Activity load failed: \(error)")
        }
    }
}
