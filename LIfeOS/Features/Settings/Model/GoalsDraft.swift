import Foundation

/// The editable goal values, detached from the SwiftData row so the form binds
/// to plain numbers and the write happens on commit.
struct GoalsDraft: Equatable {
    var steps: Int = 8000
    var sleepMinutes: Int = 420
    var exerciseMinutes: Int = 30
    var waterML: Double = 2500
    var requiredCount: Int = 3
}

struct ConnectionStatus: Equatable, Identifiable {
    let id: String
    let name: String
    let detail: String
}
