import Testing
import Foundation
@testable import Sectors

@Suite struct MonthProgressTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func progress(on day: Int, inMonth month: Int = 8) -> MonthProgress {
        let window = MonthWindow(for: date(2026, month, 1), calendar: calendar)
        return MonthProgress(window: window, now: date(2026, month, day), calendar: calendar)
    }

    /// Today counts as lived: it is a day already partly spent, and calling
    /// it remaining would offer the person a whole day they do not have.
    @Test func todayCountsAsElapsed() {
        let august = progress(on: 27)
        #expect(august.elapsedDays == 27)
        #expect(august.remainingDays == 4)
    }

    @Test func theLastDayOfTheMonthLeavesNothingRemaining() {
        let august = progress(on: 31)
        #expect(august.elapsedDays == 31)
        #expect(august.remainingDays == 0)
    }

    @Test func aMonthAlreadyOverLeavesNothingRemaining() {
        let window = MonthWindow(for: date(2026, 7, 1), calendar: calendar)
        let july = MonthProgress(window: window, now: date(2026, 8, 27), calendar: calendar)
        #expect(july.elapsedDays == 31)
        #expect(july.remainingDays == 0)
    }

    @Test func aMonthNotYetStartedIsEntirelyRemaining() {
        let window = MonthWindow(for: date(2026, 9, 1), calendar: calendar)
        let september = MonthProgress(window: window, now: date(2026, 8, 27), calendar: calendar)
        #expect(september.elapsedDays == 0)
        #expect(september.remainingDays == 30)
    }

    @Test func remainingDatesAreTheDaysAfterToday() {
        let dates = progress(on: 27).remainingDates(calendar: calendar)
        #expect(dates.count == 4)
        #expect(dates.first == date(2026, 8, 28))
        #expect(dates.last == date(2026, 8, 31))
    }

    @Test func aFinishedMonthHasNoRemainingDates() {
        #expect(progress(on: 31).remainingDates(calendar: calendar).isEmpty)
    }
}
