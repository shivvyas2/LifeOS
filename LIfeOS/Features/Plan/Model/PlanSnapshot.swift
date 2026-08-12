import Foundation
import DesignSystem
import Persistence

/// The Plan tab's sections. Each renders `PlanItemSnapshot` values, the same
/// shape a block renderer would consume, which is what keeps a future
/// customizable dashboard from needing a migration.
enum PlanSection: String, CaseIterable, Identifiable {
    case goals, habits, notes, content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goals:   "Goals"
        case .habits:  "Habits"
        case .notes:   "Notes"
        case .content: "Content"
        }
    }

    var kind: PlanKind {
        switch self {
        case .goals:   .goal
        case .habits:  .habit
        case .notes:   .note
        case .content: .content
        }
    }

    var hue: ModuleHue {
        switch self {
        case .goals:   .habits
        case .habits:  .body
        case .notes:   .nutrition
        case .content: .recovery
        }
    }

    var addPrompt: String {
        switch self {
        case .goals:   "New goal"
        case .habits:  "New habit"
        case .notes:   "Quick note"
        case .content: "New content item"
        }
    }
}

struct PlanSnapshot: Equatable {
    var goals: [PlanItemSnapshot] = []
    var habits: [PlanItemSnapshot] = []
    var notes: [PlanItemSnapshot] = []
    var content: [PlanItemSnapshot] = []
    /// Consecutive completed days, keyed by habit id.
    var streaks: [UUID: Int] = [:]

    func items(for section: PlanSection) -> [PlanItemSnapshot] {
        switch section {
        case .goals:   goals
        case .habits:  habits
        case .notes:   notes
        case .content: content
        }
    }
}
