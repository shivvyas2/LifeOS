import Foundation
import Persistence

/// One dimension of a month a projection can perfect on its own.
///
/// Named rather than derived so the leverage readout can label a row without
/// the view knowing anything about how a scorer reads its inputs.
public enum Lever: String, Sendable, CaseIterable, Equatable {
    case sleep, exercise, steps, water, journal, habits, spend

    public var label: String {
        switch self {
        case .sleep:    "Sleep"
        case .exercise: "Exercise"
        case .steps:    "Steps"
        case .water:    "Water"
        case .journal:  "Journalling"
        case .habits:   "Habits"
        case .spend:    "Spending"
        }
    }

    /// The levers that can move a sector at all.
    ///
    /// Goal and plan statuses are absent by design: a ceiling must never
    /// assume a goal closes, because closing one is not something a
    /// remaining day guarantees and `progressFraction` already keeps blocked
    /// work out of the arithmetic for the same reason.
    public static func all(for sector: LifeSector) -> [Lever] {
        switch sector {
        case .body, .growth:    [.sleep, .exercise, .steps, .water]
        case .mission:          [.habits]
        case .mind, .soul:      [.journal]
        case .money:            [.spend]
        case .family, .romance, .friends: []
        }
    }

    /// Whether this month has anything to say about the lever.
    ///
    /// An untracked metric is not offered as something that moves the score,
    /// mirroring `BodyScorer` dropping an absent metric rather than scoring
    /// it a failure.
    public func tracked(in inputs: MonthInputs) -> Bool {
        switch self {
        case .sleep:    inputs.readings.contains { $0.sleepMinutes != nil }
        case .exercise: inputs.readings.contains { $0.exerciseMinutes != nil }
        case .steps:    inputs.readings.contains { $0.steps != nil }
        case .water:    inputs.readings.contains { $0.waterML != nil }
        case .journal:  !inputs.journalDates.isEmpty
        case .habits:   inputs.habitTickRate != nil
        case .spend:    inputs.budget != nil
        }
    }
}
