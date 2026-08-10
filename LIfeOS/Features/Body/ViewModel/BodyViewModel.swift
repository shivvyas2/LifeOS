import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class BodyViewModel {
    private(set) var snapshot = BodySnapshot()

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
            let start = calendar.date(byAdding: .day, value: -60, to: .now) ?? .distantPast
            let rows = try store.metrics(from: start, to: .now)   // most-recent-first

            let weighed = rows.compactMap { row in row.weightKg.map { (date: row.date, kg: $0) } }
            var delta: Double?
            if let newest = weighed.first,
               let weekAgo = weighed.first(where: { $0.date <= newest.date.addingTimeInterval(-6 * 86_400) }) {
                delta = newest.kg - weekAgo.kg
            }

            snapshot = BodySnapshot(
                weightKg: weighed.first?.kg,
                weeklyDeltaKg: delta,
                recentWeights: rows.prefix(14).reversed().map {
                    WeightPoint(id: $0.date, weightKg: $0.weightKg)
                }
            )
        } catch {
            assertionFailure("Body load failed: \(error)")
        }
    }
}
