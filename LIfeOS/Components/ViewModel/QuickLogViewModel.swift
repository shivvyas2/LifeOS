import Foundation
import SwiftData
import Persistence

/// V1 logs only water and weight, the two metrics with no automatic source.
/// Writes to local `DailyMetrics` only; the app requests no HealthKit write
/// permissions in V1.
@MainActor @Observable
final class QuickLogViewModel {
    var waterML = 250.0
    var weightText = ""
    private(set) var errorMessage: String?

    private var context: ModelContext?

    func attach(_ context: ModelContext) {
        self.context = context
    }

    var canSaveWeight: Bool { Double(weightText) != nil }

    /// Water accumulates across the day rather than replacing: "add 250ml" is
    /// the intent, not "today's total is 250ml".
    func addWater() -> Bool {
        perform { store, amount in
            try store.upsert(date: .now) { $0.waterML = ($0.waterML ?? 0) + amount }
        }
    }

    func saveWeight() -> Bool {
        guard let kg = Double(weightText) else { return false }
        return perform { store, _ in
            try store.upsert(date: .now) { $0.weightKg = kg }
        }
    }

    private func perform(_ work: (MetricsStore, Double) throws -> Void) -> Bool {
        guard let context else { return false }
        do {
            try work(MetricsStore(context: context), waterML)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }
}
