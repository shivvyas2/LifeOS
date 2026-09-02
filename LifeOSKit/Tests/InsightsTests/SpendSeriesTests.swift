import Foundation
import Testing
@testable import Insights

@Suite struct SpendSeriesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func line(_ amount: Double, _ month: Int, _ day: Int) -> SpendSeries.Line {
        SpendSeries.Line(amount: amount, date: date(2026, month, day))
    }

    // MARK: week

    @Test func aWeekStartsOnTheCalendarsFirstWeekdayAndHasSevenDays() {
        // Wednesday 2 September 2026. Monday is 31 August.
        let week = SpendSeries.week(of: date(2026, 9, 2), lines: [], calendar: calendar)
        #expect(week.count == 7)
        #expect(week.first?.date == date(2026, 8, 31))
        #expect(week.last?.date == date(2026, 9, 6))
    }

    @Test func aWeekSumsOutflowsPerDayAndIgnoresIncome() {
        let week = SpendSeries.week(
            of: date(2026, 9, 2),
            lines: [line(-10, 8, 31), line(-5.5, 8, 31), line(2_000, 9, 1), line(-3, 9, 2)],
            calendar: calendar
        )
        #expect(week[0].amount == 15.5)
        #expect(week[1].amount == 0)
        #expect(week[2].amount == 3)
    }

    @Test func daysAfterTodayAreFutureAndDaysBeforeAreNot() {
        let week = SpendSeries.week(of: date(2026, 9, 2), lines: [], calendar: calendar)
        #expect(week.map(\.isFuture) == [false, false, false, true, true, true, true])
    }

    @Test func aChargeOutsideTheWeekIsNotCounted() {
        let week = SpendSeries.week(
            of: date(2026, 9, 2), lines: [line(-99, 8, 30), line(-99, 9, 7)], calendar: calendar
        )
        #expect(week.allSatisfy { $0.amount == 0 })
    }

    // MARK: months

    @Test func sixMonthsComeOldestFirstWithAnEmptyMonthAtZero() {
        let months = SpendSeries.months(
            endingIn: date(2026, 9, 2), count: 6,
            lines: [line(-100, 4, 3), line(-40, 6, 20), line(-7, 9, 1)],
            calendar: calendar
        )
        #expect(months.count == 6)
        #expect(months.map(\.monthStart) == [
            date(2026, 4, 1), date(2026, 5, 1), date(2026, 6, 1),
            date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1),
        ])
        #expect(months.map(\.amount) == [100, 0, 40, 0, 0, 7])
    }

    @Test func aMonthBeforeTheWindowIsDropped() {
        let months = SpendSeries.months(
            endingIn: date(2026, 9, 2), count: 3, lines: [line(-100, 4, 3)], calendar: calendar
        )
        #expect(months.map(\.amount) == [0, 0, 0])
    }

    // MARK: fold

    private func shares(_ amounts: [Double]) -> [SpendSeries.Share] {
        amounts.enumerated().map { SpendSeries.Share(name: "C\($0.offset)", amount: $0.element) }
    }

    @Test func foldKeepsTheLargestAndSumsTheRestIntoOther() {
        let folded = SpendSeries.fold(shares([50, 40, 30, 20, 10, 5, 4]), keep: 5)
        #expect(folded.map(\.name) == ["C0", "C1", "C2", "C3", "C4", "Other"])
        #expect(folded.last?.amount == 9)
    }

    @Test func foldLeavesAListAtOrUnderKeepPlusOneAlone() {
        // An "Other" made of one category is that category with the wrong name.
        #expect(SpendSeries.fold(shares([5, 4, 3, 2, 1, 0.5]), keep: 5).map(\.name)
                == ["C0", "C1", "C2", "C3", "C4", "C5"])
        #expect(SpendSeries.fold(shares([5, 4]), keep: 5).count == 2)
    }

    @Test func foldSortsLargestFirstBeforeCutting() {
        let folded = SpendSeries.fold(shares([1, 50, 2, 40, 3, 30, 4]), keep: 3)
        #expect(folded.map(\.name) == ["C1", "C3", "C5", "Other"])
        #expect(folded.last?.amount == 10)
    }
}
