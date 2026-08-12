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

    public init(
        stepsGoal: Int = 8000,
        sleepMinutesGoal: Int = 420,
        exerciseMinutesGoal: Int = 30,
        waterMLGoal: Double = 2500,
        requiredCount: Int = 3
    ) {
        self.stepsGoal = stepsGoal
        self.sleepMinutesGoal = sleepMinutesGoal
        self.exerciseMinutesGoal = exerciseMinutesGoal
        self.waterMLGoal = waterMLGoal
        self.requiredCount = requiredCount
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
