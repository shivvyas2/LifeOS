import Foundation
import Persistence

/// Everything the six data-fed scorers need for one month, already fetched
/// from the stores and already filtered to the month window.
///
/// Built once per sector shown at close (`MonthlyCloseViewModel` builds it in
/// `advance()`), so `SectorEvidenceFactory` itself never touches a store,
/// throws, or awaits, and can be tested with plain values.
public struct MonthInputs: Sendable {
    /// One row per day that has any metrics logged, for Body and for
    /// Growth's targets rule.
    public var readings: [DayReading]
    public var targets: GoalTargets

    /// This month's transactions, signed per `MoneyEntry`: positive in,
    /// negative out.
    public var amounts: [Double]
    public var previousAmounts: [Double]

    /// Goals and habits whose status moved this month (`updatedAt` inside
    /// the month window).
    public var planStatuses: [PlanStatus]
    /// Goals only, whose status moved this month.
    public var goalStatuses: [PlanStatus]
    /// Share of habit-days ticked across the month. Nil when there were no
    /// habit-days to judge.
    public var habitTickRate: Double?

    /// Distinct dates a journal entry was written this month (`createdAt`
    /// inside the month window).
    public var journalDates: [Date]
    public var previousJournalCount: Int?

    public var daysInMonth: Int

    public init(
        readings: [DayReading] = [],
        targets: GoalTargets = .default,
        amounts: [Double] = [],
        previousAmounts: [Double] = [],
        planStatuses: [PlanStatus] = [],
        goalStatuses: [PlanStatus] = [],
        habitTickRate: Double? = nil,
        journalDates: [Date] = [],
        previousJournalCount: Int? = nil,
        daysInMonth: Int = 30
    ) {
        self.readings = readings
        self.targets = targets
        self.amounts = amounts
        self.previousAmounts = previousAmounts
        self.planStatuses = planStatuses
        self.goalStatuses = goalStatuses
        self.habitTickRate = habitTickRate
        self.journalDates = journalDates
        self.previousJournalCount = previousJournalCount
        self.daysInMonth = daysInMonth
    }
}
