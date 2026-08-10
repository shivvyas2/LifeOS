import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class RecoveryViewModel {
    private(set) var snapshot = RecoverySnapshot()
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
            let today = try store.metrics(from: selectedDate, to: selectedDate).first
            // Whoop fields stay nil until Plan 3; the empty state is the real
            // first-run experience, not a placeholder.
            snapshot = RecoverySnapshot(
                recoveryPct: today?.whoopRecoveryPct,
                hrvMs: today?.hrvMs,
                dayStrain: today?.whoopDayStrain,
                sleepMinutes: today?.sleepMinutes
            )
        } catch {
            assertionFailure("Recovery load failed: \(error)")
        }
    }
}
