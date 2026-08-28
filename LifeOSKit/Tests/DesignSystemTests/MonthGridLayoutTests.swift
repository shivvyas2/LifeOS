import Testing
import Foundation
@testable import DesignSystem

@Suite struct MonthGridLayoutTests {
    /// Monday-first calendar, so grid columns read M T W T F S S like the reference design.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func augustTwentyTwentySixStartsWithFiveBlankCells() {
        // 1 Aug 2026 is a Saturday. Monday-first columns run M T W T F S S,
        // so Saturday is index 5 ⇒ five leading blanks.
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        #expect(cells.prefix(5).allSatisfy { $0.state == .blank })
        #expect(cells[5].date == date(2026, 8, 1))
    }

    @Test func cellCountCoversWholeMonthPlusPadding() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        // 5 blanks + 31 days = 36, padded to a whole number of 7-day rows.
        #expect(cells.count == 42)
        #expect(cells.filter { $0.date != nil }.count == 31)
    }

    /// 1 Feb 2026 is a Sunday, the worst case for a Monday-first grid, and the
    /// only month start that needs a full six blanks. Guards the `% 7` wraparound
    /// in the leading-blank maths, which an August-only test cannot distinguish.
    @Test func monthStartingOnSundayTakesSixBlankCells() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 2, 15),
            calendar: calendar,
            today: date(2026, 2, 15),
            status: { _ in .noData }
        )
        #expect(cells.prefix(6).allSatisfy { $0.state == .blank })
        #expect(cells[6].date == date(2026, 2, 1))
        // 6 blanks + 28 days = 34, padded to 35.
        #expect(cells.count == 35)
    }

    @Test func todayOverridesItsStatus() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .onTarget }
        )
        let todayCell = cells.first { $0.date == date(2026, 8, 10) }
        #expect(todayCell?.state == .today)
    }

    @Test func daysAfterTodayAreFutureRegardlessOfStatus() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .onTarget }
        )
        let tomorrow = cells.first { $0.date == date(2026, 8, 11) }
        #expect(tomorrow?.state == .future)
    }

    /// `DotGrid` decides whether a dot is tappable by checking `date != nil`,
    /// so padding cells and only padding cells must lack a date. A real day
    /// with a nil date would be silently unopenable.
    @Test func onlyPaddingCellsLackADate() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        #expect(cells.allSatisfy { ($0.date == nil) == ($0.state == .blank) })
    }

    // MARK: - Stepping between months

    @Test func steppingKeepsTheDayNumberWhenTheMonthIsLongEnough() {
        let moved = MonthGridLayout.stepping(
            from: date(2026, 3, 1), by: 1, day: 15, calendar: calendar
        )
        #expect(calendar.dateComponents([.year, .month, .day], from: moved) ==
                DateComponents(year: 2026, month: 4, day: 15))
    }

    /// The 31st has nowhere to land in February, so it lands on the last day
    /// rather than spilling into March.
    @Test func steppingClampsToTheLastDayOfAShorterMonth() {
        let moved = MonthGridLayout.stepping(
            from: date(2026, 1, 31), by: 1, day: 31, calendar: calendar
        )
        #expect(calendar.dateComponents([.year, .month, .day], from: moved) ==
                DateComponents(year: 2026, month: 2, day: 28))
    }

    @Test func steppingIntoALeapFebruaryReachesTheTwentyNinth() {
        let moved = MonthGridLayout.stepping(
            from: date(2028, 1, 31), by: 1, day: 31, calendar: calendar
        )
        #expect(calendar.dateComponents([.day], from: moved).day == 29)
    }

    /// The reason the day number is carried rather than re-read: stepping out
    /// of a short month must restore the day it went in with, so a walk
    /// forward and back returns where it started.
    @Test func steppingThroughAShortMonthDoesNotReduceTheDay() {
        let january = date(2026, 1, 31)
        let february = MonthGridLayout.stepping(from: january, by: 1, day: 31, calendar: calendar)
        let march = MonthGridLayout.stepping(from: february, by: 1, day: 31, calendar: calendar)
        #expect(calendar.dateComponents([.month, .day], from: march) ==
                DateComponents(month: 3, day: 31))
    }

    @Test func steppingBackwardsCrossesTheYearBoundary() {
        let moved = MonthGridLayout.stepping(
            from: date(2026, 1, 10), by: -1, day: 10, calendar: calendar
        )
        #expect(calendar.dateComponents([.year, .month, .day], from: moved) ==
                DateComponents(year: 2025, month: 12, day: 10))
    }
}
