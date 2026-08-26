import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct MoneyTests {
    private func makeStore() throws -> MoneyStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MoneyStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func summaryUsesOurSignConventionNotPlaids() {
        // Positive is money in. Plaid is the opposite and the ingestion layer
        // negates; if that ever regresses, income and expenses swap.
        let entries = [
            MoneyEntry(date: day, amount: 5_200, merchant: "Salary"),
            MoneyEntry(date: day, amount: -1_500, merchant: "Rent"),
            MoneyEntry(date: day, amount: -650, merchant: "Groceries"),
        ]
        let summary = summarise(entries: entries)

        #expect(summary.income == 5_200)
        #expect(summary.expenses == 2_150)
        #expect(summary.net == 3_050)
    }

    @Test func savingsRateIsUndefinedWithoutIncome() {
        // Not 0% but undefined. A savings rate against no income is a number this
        // app must not invent.
        let summary = summarise(entries: [MoneyEntry(date: day, amount: -40, merchant: "Coffee")])
        #expect(summary.savingsRate == nil)
        #expect(summary.income == 0)
    }

    @Test func pendingTransactionsAreExcludedFromTheRollup() {
        let settled = MoneyEntry(date: day, amount: -100, merchant: "Shop")
        let pending = MoneyEntry(date: day, amount: -999, merchant: "Hold", pending: true)
        let summary = summarise(entries: [settled, pending])
        #expect(summary.expenses == 100)
    }

    @Test func creditAndLoanBalancesSubtractFromNetWorth() {
        let accounts = [
            MoneyAccount(name: "Checking", type: "depository", currentBalance: 4_000),
            MoneyAccount(name: "Card", type: "credit", currentBalance: 1_200),
        ]
        let summary = summarise(entries: [], accounts: accounts)
        #expect(summary.netWorth == 2_800)
    }

    @Test func ingestUpdatesAPendingTransactionRatherThanDuplicatingIt() throws {
        let store = try makeStore()
        try store.ingest([(externalID: "txn_1", date: day, amount: -20,
                           merchant: "Cafe", category: nil, pending: true)])
        try store.ingest([(externalID: "txn_1", date: day, amount: -22.5,
                           merchant: "Cafe", category: "Food", pending: false)])

        let rows = try store.entries(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].amount == -22.5)
        #expect(rows[0].pending == false)
    }

    @Test func transfersBetweenOwnAccountsDoNotCountAsIncomeOrSpending() {
        // Moving 500 from savings to checking is not a 500 raise and not a 500
        // shopping trip. Counting it as both leaves net correct while dragging the
        // savings rate toward zero, which is the number the screen leads with.
        let entries = [
            MoneyEntry(date: day, amount: 4_000, merchant: "Salary",
                       categoryCode: "INCOME_WAGES"),
            MoneyEntry(date: day, amount: 500, merchant: "Transfer from Savings",
                       categoryCode: "TRANSFER_IN_ACCOUNT_TRANSFER"),
            MoneyEntry(date: day, amount: -500, merchant: "Transfer to Checking",
                       categoryCode: "TRANSFER_OUT_ACCOUNT_TRANSFER"),
            MoneyEntry(date: day, amount: -1_000, merchant: "Rent",
                       categoryCode: "RENT_AND_UTILITIES_RENT"),
        ]
        let summary = summarise(entries: entries)

        #expect(summary.income == 4_000)
        #expect(summary.expenses == 1_000)
        #expect(summary.savingsRate == 0.75)
    }

    @Test func payingTheCreditCardIsNotSpendingOnTopOfTheCardsPurchases() {
        // The purchases already landed on the card. Counting the payment too bills
        // the same money twice.
        let entries = [
            MoneyEntry(date: day, amount: 3_000, merchant: "Salary",
                       categoryCode: "INCOME_WAGES"),
            MoneyEntry(date: day, amount: -300, merchant: "Groceries",
                       categoryCode: "FOOD_AND_DRINK_GROCERIES"),
            MoneyEntry(date: day, amount: -300, merchant: "Card Payment",
                       categoryCode: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"),
        ]
        let summary = summarise(entries: entries)

        #expect(summary.expenses == 300)
    }

    @Test func manualEntriesHaveNoCategoryCodeAndAreNeverExcluded() {
        let summary = summarise(entries: [
            MoneyEntry(date: day, amount: -75, merchant: "Cash"),
        ])
        #expect(summary.expenses == 75)
    }

    @Test func otherLoanPaymentsAreRealSpending() {
        // Only the credit card payment is a double count. A car loan payment is
        // money genuinely leaving.
        let summary = summarise(entries: [
            MoneyEntry(date: day, amount: -450, merchant: "Auto Loan",
                       categoryCode: "LOAN_PAYMENTS_CAR_PAYMENT"),
        ])
        #expect(summary.expenses == 450)
    }

    @Test func aCategoryThatMerelyStartsLikeATransferIsStillSpending() {
        // TRANSFER_IN is a primary category, and its detail codes extend it with an
        // underscore. Matching the bare prefix would swallow any future code that
        // happens to begin with the same letters and quietly erase real spending.
        let summary = summarise(entries: [
            MoneyEntry(date: day, amount: -220, merchant: "Advisory fee",
                       categoryCode: "TRANSFER_INVESTMENT_ADVISORY_FEE"),
        ])
        #expect(summary.expenses == 220)
    }
}
