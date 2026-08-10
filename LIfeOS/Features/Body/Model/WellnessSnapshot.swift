import Foundation

/// Wellness rolls up the week rather than reporting a single day — sleep and
/// training only mean something as a pattern.
struct WellnessSnapshot: Equatable {
    var averageSleepMinutes: Int?
    var workoutDays: Int = 0
    var workoutTarget: Int = 7
    var averageExerciseMinutes: Int?

    /// Plain-language verdicts, so the view never re-derives judgement.
    var sleepVerdict: String?
    var trainingVerdict: String?
}
