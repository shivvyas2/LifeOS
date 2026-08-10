import Foundation

public struct GoalTargets: Sendable, Equatable {
    public var steps: Int
    public var sleepMinutes: Int
    public var exerciseMinutes: Int
    public var waterML: Double
    public var requiredCount: Int

    public init(steps: Int, sleepMinutes: Int, exerciseMinutes: Int, waterML: Double, requiredCount: Int) {
        self.steps = steps
        self.sleepMinutes = sleepMinutes
        self.exerciseMinutes = exerciseMinutes
        self.waterML = waterML
        self.requiredCount = requiredCount
    }

    public static let `default` = GoalTargets(
        steps: 8000,
        sleepMinutes: 420,
        exerciseMinutes: 30,
        waterML: 2500,
        requiredCount: 3
    )
}
