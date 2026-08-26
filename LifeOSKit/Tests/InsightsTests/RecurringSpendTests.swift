import Foundation
import Testing
@testable import Insights

@Suite struct RecurringSpendTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func line(_ merchant: String, _ amount: Double, _ month: Int,
                      day: Int = 12, category: String? = "Entertainment") -> RecurringSpend.Line {
        RecurringSpend.Line(merchant: merchant, category: category,
                            amount: amount, date: date(2026, month, day))
    }

    @Test func aMerchantChargingTwoMonthsRunningIsRecurring() {
        let charges = RecurringSpend.charges(
            in: [line("Netflix", -19.99, 6), line("Netflix", -19.99, 7)],
            calendar: calendar
        )
        #expect(charges.count == 1)
        #expect(charges.first?.merchant == "Netflix")
        #expect(charges.first?.months == 2)
    }

    /// Two coffees in one week are not a standing payment. Counting rows
    /// rather than distinct months is the easy way to get this wrong.
    @Test func twoChargesInOneMonthAreNotRecurring() {
        let charges = RecurringSpend.charges(
            in: [line("Blue Bottle", -6.50, 6, day: 3),
                 line("Blue Bottle", -6.50, 6, day: 9)],
            calendar: calendar
        )
        #expect(charges.isEmpty)
    }

    /// A merchant visited monthly at wildly different amounts is a habit, not
    /// a subscription, and telling someone to cancel it sends them hunting for
    /// a charge that does not exist.
    @Test func amountsThatWanderAreNotASubscription() {
        let charges = RecurringSpend.charges(
            in: [line("Whole Foods", -40, 6), line("Whole Foods", -180, 7)],
            calendar: calendar
        )
        #expect(charges.isEmpty)
    }

    /// A salary is the steadiest monthly line there is and would otherwise
    /// top the list of things to cancel.
    @Test func incomeIsNeverASubscription() {
        let charges = RecurringSpend.charges(
            in: [line("Payroll", 6_200, 6), line("Payroll", 6_200, 7)],
            calendar: calendar
        )
        #expect(charges.isEmpty)
    }

    /// The median, not the mean: one price rise must not move the figure to
    /// something no month actually charged.
    @Test func theTypicalAmountResistsASinglePriceRise() {
        let charges = RecurringSpend.charges(
            in: [line("Spotify", -10.99, 5), line("Spotify", -10.99, 6),
                 line("Spotify", -12.99, 7)],
            calendar: calendar
        )
        #expect(charges.first?.typicalAmount == 10.99)
    }

    @Test func theBiggestStandingCostLeads() {
        let charges = RecurringSpend.charges(
            in: [line("Spotify", -10.99, 6), line("Spotify", -10.99, 7),
                 line("Netflix", -19.99, 6), line("Netflix", -19.99, 7)],
            calendar: calendar
        )
        #expect(charges.map(\.merchant) == ["Netflix", "Spotify"])
        // Compared with a tolerance rather than for equality: these are binary
        // floats and 10.99 + 19.99 does not land exactly on 30.98.
        #expect(abs(RecurringSpend.monthlyTotal(of: charges) - 30.98) < 0.001)
    }

    @Test func nothingRepeatingYieldsNothing() {
        #expect(RecurringSpend.charges(in: [], calendar: calendar).isEmpty)
        #expect(RecurringSpend.monthlyTotal(of: []) == 0)
    }
}
