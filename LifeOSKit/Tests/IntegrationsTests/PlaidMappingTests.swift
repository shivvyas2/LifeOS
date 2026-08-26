import Testing
import Foundation
import SwiftData
import Persistence
@testable import Integrations

@Suite @MainActor struct PlaidMappingTests {
    private func delta() throws -> PlaidItemDelta {
        let response = try JSONDecoder().decode(
            PlaidSyncResponse.self, from: Data(PlaidFixtures.syncPage.utf8)
        )
        return try #require(response.items.first)
    }

    @Test func aPayrollDepositComesOutAsIncome() throws {
        // The one that matters. Plaid's amount is positive for money leaving, so
        // a deposit arrives negative. Fail to negate and salary becomes the
        // largest expense of the month and every rollup lies.
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let payroll = try #require(rows.first { $0.externalID == "txn_payroll" })

        #expect(payroll.amount == 3_200)
        #expect(payroll.category == "Income")
        #expect(payroll.categoryCode == "INCOME_WAGES")
    }

    @Test func aCardPurchaseComesOutAsSpending() throws {
        let rows = try PlaidMapping.ingestRows(from: delta().added, accounts: delta().accounts)
        let coffee = try #require(rows.first { $0.externalID == "txn_coffee" })

        #expect(coffee.amount == -6.75)
        #expect(coffee.pending)
        #expect(coffee.category == "Food & drink")
        // merchant_name is the clean one. `name` is the raw bank descriptor.
        #expect(coffee.merchant == "Blue Bottle Coffee")
        #expect(coffee.accountName == "Plaid Credit Card")
    }

    @Test func aTransactionWithoutAMerchantNameFallsBackToTheBankDescriptor() throws {
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let payroll = try #require(rows.first { $0.externalID == "txn_payroll" })
        #expect(payroll.merchant == "ACME PAYROLL DIRECT DEP")
    }

    @Test func anUncategorisedTransactionStillIngests() throws {
        // A null category is ordinary. Dropping the row would quietly lose money.
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let unknown = try #require(rows.first { $0.externalID == "txn_uncategorised" })

        #expect(unknown.category == nil)
        #expect(unknown.categoryCode == nil)
        #expect(unknown.currencyCode == "USD")
    }

    @Test func theWholePageRollsUpToTheRightSummary() throws {
        // End to end through the real store: decode, map, ingest, summarise.
        // Income is the payroll. Expenses are the 12 unknown vendor charge only:
        // the coffee is pending and the 400 is a card payment, which would
        // otherwise double count the purchases already on that card.
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MoneyStore(context: ModelContext(container))
        let delta = try delta()

        try store.ingest(PlaidMapping.ingestRows(from: delta.added, accounts: delta.accounts))
        try store.upsertAccounts(PlaidMapping.accountRows(from: delta.accounts))

        let entries = try store.entries(from: Date(timeIntervalSince1970: 0), to: .now)
        let summary = summarise(entries: entries, accounts: try store.accounts())

        #expect(summary.income == 3_200)
        #expect(summary.expenses == 12)
        // 2450.75 in checking, less 610.25 owed on the card.
        #expect(summary.netWorth == 1_840.50)
    }

    @Test func removalsAreCarriedThroughAsIDs() throws {
        #expect(try delta().removed.map(\.transaction_id) == ["txn_stale_pending"])
    }

    @Test func anUnparseableDateFailsLoudlyRatherThanDroppingTheRow() throws {
        // Silently skipping a row a date parser did not like means a wrong total
        // with no error anywhere. Better to fail the sync and keep the last
        // known-good snapshot on screen.
        let broken = PlaidTransaction(
            transaction_id: "txn_bad", account_id: "acc", amount: 1,
            iso_currency_code: "USD", date: "24/08/2026", name: "X",
            merchant_name: nil, pending: false, personal_finance_category: nil
        )
        #expect(throws: PlaidMappingError.self) {
            _ = try PlaidMapping.ingestRows(from: [broken])
        }
    }
}
