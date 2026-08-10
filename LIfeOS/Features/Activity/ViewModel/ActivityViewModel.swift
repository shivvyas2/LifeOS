import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class ActivityViewModel {
    private(set) var snapshot = ActivitySnapshot()

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load() {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)

        do {
            // Today only — this screen shows no history.
            let today = try store.metrics(from: .now, to: .now).first
            snapshot = ActivitySnapshot(
                steps: today?.steps,
                exerciseMinutes: today?.exerciseMinutes,
                activeEnergyKcal: today?.activeEnergyKcal,
                restingHR: today?.restingHR
            )
        } catch {
            assertionFailure("Activity load failed: \(error)")
        }
    }
}
