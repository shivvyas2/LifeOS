import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class SettingsViewModel {
    /// Bound directly by the form's steppers. Writes are committed by `save()`.
    var draft = GoalsDraft()

    /// Derived, not hardcoded: the Supabase row previously always read
    /// "Not configured", which became a lie the moment the project was linked.
    var connections: [ConnectionStatus] {
        [
            ConnectionStatus(id: "health", name: "Apple Health", detail: "Not connected"),
            ConnectionStatus(id: "whoop", name: "Whoop", detail: "Not connected"),
            ConnectionStatus(
                id: "supabase",
                name: "Supabase",
                detail: AppConfig.supabaseURL == nil ? "Not configured" : "Connected"
            ),
        ]
    }

    private var context: ModelContext?

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load() {
        guard let context else { return }
        do {
            let goals = try MetricsStore(context: context).goals()
            draft = GoalsDraft(
                steps: goals.stepsGoal,
                sleepMinutes: goals.sleepMinutesGoal,
                exerciseMinutes: goals.exerciseMinutesGoal,
                waterML: goals.waterMLGoal,
                requiredCount: goals.requiredCount
            )
        } catch {
            assertionFailure("Settings load failed: \(error)")
        }
    }

    /// Writes the draft back to the singleton goals row. Saving here is what
    /// makes the dot grid re-evaluate: the rule is the user's, not hard-coded.
    func save() {
        guard let context else { return }
        do {
            let goals = try MetricsStore(context: context).goals()
            goals.stepsGoal = draft.steps
            goals.sleepMinutesGoal = draft.sleepMinutes
            goals.exerciseMinutesGoal = draft.exerciseMinutes
            goals.waterMLGoal = draft.waterML
            goals.requiredCount = draft.requiredCount
            try context.save()
        } catch {
            assertionFailure("Settings save failed: \(error)")
        }
    }
}
