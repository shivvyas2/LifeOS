import Foundation

struct BodySnapshot: Equatable {
    var weightKg: Double?
    /// Change over the last seven days, nil when there isn't enough history.
    var weeklyDeltaKg: Double?
    /// Oldest-first, so the chart reads left to right. `nil` marks an unweighed day.
    var recentWeights: [WeightPoint] = []
}

struct WeightPoint: Equatable, Identifiable {
    let id: Date
    let weightKg: Double?
}
