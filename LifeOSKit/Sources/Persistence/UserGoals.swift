import Foundation
import SwiftData

/// Singleton by convention: exactly one row. Editable in Settings.
@Model
public final class UserGoals {
    public var stepsGoal: Int
    public var sleepMinutesGoal: Int
    public var exerciseMinutesGoal: Int
    public var waterMLGoal: Double
    public var requiredCount: Int
    /// The workout library's preferences, asked on first open. Optional so
    /// the existing row migrates without a value.
    public var trainingGoal: String?
    public var equipmentRaw: [String]
    public var sessionMinutes: Int?

    public init(
        stepsGoal: Int = 8000,
        sleepMinutesGoal: Int = 420,
        exerciseMinutesGoal: Int = 30,
        waterMLGoal: Double = 2500,
        requiredCount: Int = 3,
        trainingGoal: String? = nil,
        equipmentRaw: [String] = [],
        sessionMinutes: Int? = nil
    ) {
        self.stepsGoal = stepsGoal
        self.sleepMinutesGoal = sleepMinutesGoal
        self.exerciseMinutesGoal = exerciseMinutesGoal
        self.waterMLGoal = waterMLGoal
        self.requiredCount = requiredCount
        self.trainingGoal = trainingGoal
        self.equipmentRaw = equipmentRaw
        self.sessionMinutes = sessionMinutes
    }

    public var targets: GoalTargets {
        GoalTargets(
            steps: stepsGoal,
            sleepMinutes: sleepMinutesGoal,
            exerciseMinutes: exerciseMinutesGoal,
            waterML: waterMLGoal,
            requiredCount: requiredCount
        )
    }
}
