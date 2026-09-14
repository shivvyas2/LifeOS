import Foundation
import Testing
@testable import Sectors

struct WorkoutPlannerTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var wednesday: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9))! }
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: wednesday)! }

    @Test func redBatteryIsMobility() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 45, batteryPercent: 20, recentSplits: [], now: wednesday, calendar: calendar)
        #expect(plan.split == "mobility" && plan.maxIntensity == 1 && plan.minutes == 45)
    }
    @Test func strengthRotatesAfterTheMostRecentSplit() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: nil, batteryPercent: 80,
                                       recentSplits: [(day(2), "push"), (day(5), "legs")], now: wednesday, calendar: calendar)
        #expect(plan.split == "pull" && plan.maxIntensity == 3 && plan.minutes == 30)
        #expect(plan.reason == "You did push on Monday, so today is pull.")
        let afterLegs = WorkoutPlanner.plan(goal: "hypertrophy", sessionMinutes: 40, batteryPercent: 50, recentSplits: [(day(1), "legs")], now: wednesday, calendar: calendar)
        #expect(afterLegs.split == "push" && afterLegs.maxIntensity == 2)
    }
    @Test func firstSessionOfTheWeekIsPush() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 30, batteryPercent: 70, recentSplits: [(day(9), "pull")], now: wednesday, calendar: calendar)
        #expect(plan.split == "push" && plan.reason == "First session this week: push.")
    }
    @Test func enduranceAndMobilityGoals() {
        #expect(WorkoutPlanner.plan(goal: "endurance", sessionMinutes: 30, batteryPercent: 50, recentSplits: [], now: wednesday, calendar: calendar).split == "cardio")
        #expect(WorkoutPlanner.plan(goal: "endurance", sessionMinutes: 30, batteryPercent: 50, recentSplits: [], now: wednesday, calendar: calendar).maxIntensity == 2)
        #expect(WorkoutPlanner.plan(goal: "mobility", sessionMinutes: 20, batteryPercent: 90, recentSplits: [], now: wednesday, calendar: calendar).split == "mobility")
    }
    @Test func unknownGoalIsFullBody() {
        let plan = WorkoutPlanner.plan(goal: nil, sessionMinutes: nil, batteryPercent: nil, recentSplits: [], now: wednesday, calendar: calendar)
        #expect(plan.split == "full" && plan.maxIntensity == 2 && plan.reason == "Set a goal for a plan built around you.")
    }
    @Test func unknownBatteryAfterAHardDayIsMobility() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 30, batteryPercent: nil, recentSplits: [(day(1), "legs")], now: wednesday, calendar: calendar)
        #expect(plan.split == "mobility")
    }
}
