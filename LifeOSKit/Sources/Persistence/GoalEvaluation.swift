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

public struct DayReading: Sendable, Equatable {
    public var steps: Int?
    public var sleepMinutes: Int?
    public var exerciseMinutes: Int?
    public var waterML: Double?

    public init(steps: Int?, sleepMinutes: Int?, exerciseMinutes: Int?, waterML: Double?) {
        self.steps = steps
        self.sleepMinutes = sleepMinutes
        self.exerciseMinutes = exerciseMinutes
        self.waterML = waterML
    }

    public var hasAnyData: Bool {
        steps != nil || sleepMinutes != nil || exerciseMinutes != nil || waterML != nil
    }
}

public enum DayStatus: Sendable, Equatable {
    case onTarget, missed, noData
}

/// A day with no metrics at all is excluded from judgement — leaving the watch
/// on the charger is not a failure. A day with *some* data is judged on what
/// it has, so an unlogged metric cannot launder a bad day into a blank one.
public func evaluate(_ reading: DayReading, against targets: GoalTargets) -> DayStatus {
    guard reading.hasAnyData else { return .noData }

    var met = 0
    if let steps = reading.steps, steps >= targets.steps { met += 1 }
    if let sleep = reading.sleepMinutes, sleep >= targets.sleepMinutes { met += 1 }
    if let exercise = reading.exerciseMinutes, exercise >= targets.exerciseMinutes { met += 1 }
    if let water = reading.waterML, water >= targets.waterML { met += 1 }

    return met >= targets.requiredCount ? .onTarget : .missed
}
