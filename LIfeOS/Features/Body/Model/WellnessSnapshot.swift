import Foundation
import Integrations

/// Wellness rolls up the week rather than reporting a single day. Sleep and
/// training only mean something as a pattern.
struct WellnessSnapshot: Equatable {
    var averageSleepMinutes: Int?
    var workoutDays: Int = 0
    var workoutTarget: Int = 7
    var averageExerciseMinutes: Int?

    /// Plain-language verdicts, so the view never re-derives judgement.
    var sleepVerdict: String?
    var trainingVerdict: String?

    /// Journal lives in Body because it is a wellness signal, not a task:
    /// how the day felt, next to how the body performed.
    var journal: [JournalEntry] = []
    /// Every reading Apple Health had for the selected day, grouped for
    /// display. Empty until something is connected, and it lists only what
    /// exists: the screen does not decide which metrics a person has.
    var healthGroups: [HealthDaySummary.Group] = []
    var hasEntryToday = false
}

struct JournalEntry: Equatable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
}
