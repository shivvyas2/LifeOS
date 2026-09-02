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
        try store.ingest([MoneyIngestRow(externalID: "txn_1", date: day, amount: -20,
                                         merchant: "Cafe", category: nil, categoryCode: nil,
                                         merchantID: nil, logoURL: nil, pending: true, accountID: nil, accountName: nil,
                                         currencyCode: "USD")])
        try store.ingest([MoneyIngestRow(externalID: "txn_1", date: day, amount: -22.5,
                                         merchant: "Cafe", category: "Food", categoryCode: nil,
                                         merchantID: nil, logoURL: nil, pending: false, accountID: nil, accountName: nil,
                                         currencyCode: "USD")])

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

    @Test func ingestUpsertsOnTheProviderIDRatherThanDuplicating() throws {
        let store = try makeStore()
        let row = MoneyIngestRow(externalID: "txn_1", date: day, amount: -42,
                                 merchant: "Cafe", category: "Food & drink",
                                 categoryCode: "FOOD_AND_DRINK_COFFEE", merchantID: nil, logoURL: nil, pending: true,
                                 accountID: "acc_1", accountName: "Checking",
                                 currencyCode: "USD")
        try store.ingest([row])

        let settled = MoneyIngestRow(externalID: "txn_1", date: day, amount: -44,
                                     merchant: "Cafe", category: "Food & drink",
                                     categoryCode: "FOOD_AND_DRINK_COFFEE", merchantID: nil, logoURL: nil, pending: false,
                                     accountID: "acc_1", accountName: "Checking",
                                     currencyCode: "USD")
        try store.ingest([settled])

        let entries = try store.entries(from: day, to: day)
        #expect(entries.count == 1)
        #expect(entries[0].amount == -44)
        #expect(entries[0].pending == false)
        #expect(entries[0].accountName == "Checking")
        #expect(entries[0].categoryCode == "FOOD_AND_DRINK_COFFEE")
    }

    @Test func removingAPendingChargeStopsItDoubleCountingOnceItSettles() throws {
        // Plaid gives a settled charge a different transaction_id from the pending
        // one and returns the pending id in `removed`. Ignore that and every card
        // charge eventually exists twice.
        let store = try makeStore()
        try store.ingest([
            MoneyIngestRow(externalID: "pending_1", date: day, amount: -30,
                           merchant: "Shop", category: nil, categoryCode: nil,
                           merchantID: nil, logoURL: nil, pending: true, accountID: nil, accountName: nil,
                           currencyCode: "USD"),
            MoneyIngestRow(externalID: "posted_1", date: day, amount: -30,
                           merchant: "Shop", category: nil, categoryCode: nil,
                           merchantID: nil, logoURL: nil, pending: false, accountID: nil, accountName: nil,
                           currencyCode: "USD"),
        ])

        try store.remove(externalIDs: ["pending_1"])

        let entries = try store.entries(from: day, to: day)
        #expect(entries.count == 1)
        #expect(entries[0].externalID == "posted_1")
    }

    @Test func removingAnUnknownIDIsHarmless() throws {
        // A replayed page can ask us to delete something already gone. That is the
        // normal cost of a device-owned cursor, not an error.
        let store = try makeStore()
        try store.remove(externalIDs: ["never_existed"])
        #expect(try store.entries(from: day, to: day).isEmpty)
    }

    @Test func accountsUpsertOnTheProviderIDSoBalancesMoveInsteadOfPilingUp() throws {
        let store = try makeStore()
        try store.upsertAccounts([
            MoneyAccountRow(externalID: "acc_1", name: "Checking", type: "depository",
                            subtype: nil, mask: nil,
                            currentBalance: 2_000, availableBalance: nil,
                            creditLimit: nil, currencyCode: "USD"),
        ])
        try store.upsertAccounts([
            MoneyAccountRow(externalID: "acc_1", name: "Checking", type: "depository",
                            subtype: nil, mask: nil,
                            currentBalance: 2_400, availableBalance: nil,
                            creditLimit: nil, currencyCode: "USD"),
            MoneyAccountRow(externalID: "acc_2", name: "Card", type: "credit",
                            subtype: nil, mask: nil,
                            currentBalance: 600, availableBalance: nil,
                            creditLimit: nil, currencyCode: "USD"),
        ])

        let accounts = try store.accounts()
        #expect(accounts.count == 2)
        // Net worth subtracts what is owed on the card.
        #expect(summarise(entries: [], accounts: accounts).netWorth == 1_800)
    }

    @Test func ingestStoresTheMerchantEntityAndUpdatesItOnResync() throws {
        // Plaid backfills a merchant entity onto a transaction it had not
        // resolved when it first sent it, so a re-sync must move the value
        // rather than keep the first answer.
        let store = try makeStore()
        let row = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: nil, logoURL: nil, pending: false,
            accountID: "acc_card", accountName: "Card", currencyCode: "USD"
        )
        try store.ingest([row])

        let resolved = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: "mch_bluebottle", logoURL: nil, pending: false,
            accountID: "acc_card", accountName: "Card", currencyCode: "USD"
        )
        try store.ingest([resolved])

        let entries = try store.monthEntries(containing: day)
        #expect(entries.count == 1)
        #expect(entries.first?.merchantID == "mch_bluebottle")
    }

    @Test func aManualEntryHasNoMerchantEntity() throws {
        let entry = MoneyEntry(date: day, amount: -12, merchant: "Cash")
        #expect(entry.merchantID == nil)
    }

    @Test func ingestStoresTheLogoAndMovesItOnResync() throws {
        // The one-time cursor reset replays history so old rows gain their
        // logo; that only works if a re-sync writes the field onto an
        // existing row rather than keeping the first nil.
        let store = try makeStore()
        let bare = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: "mch_bluebottle", logoURL: nil, pending: false,
            accountID: "acc_card", accountName: "Card", currencyCode: "USD"
        )
        try store.ingest([bare])
        #expect(try store.monthEntries(containing: day).first?.logoURL == nil)

        let withLogo = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: "mch_bluebottle", logoURL: "https://example.com/bb.png", pending: false,
            accountID: "acc_card", accountName: "Card", currencyCode: "USD"
        )
        try store.ingest([withLogo])

        let entries = try store.monthEntries(containing: day)
        #expect(entries.count == 1)
        #expect(entries.first?.logoURL == "https://example.com/bb.png")
    }

    @Test func aManualEntryHasNoLogo() {
        #expect(MoneyEntry(date: day, amount: -12, merchant: "Cash").logoURL == nil)
    }

    @Test func isSpendingMatchesWhatTheSummaryCountsAsExpense() {
        // The category list is built from this and the "Spent" figure from
        // summarise. If they ever disagree, the parts stop summing to the whole.
        let cases: [(MoneyEntry, Bool)] = [
            (MoneyEntry(date: day, amount: -40, merchant: "Coffee"), true),
            (MoneyEntry(date: day, amount: 3_000, merchant: "Salary"), false),
            (MoneyEntry(date: day, amount: -40, merchant: "Hold", pending: true), false),
            (MoneyEntry(date: day, amount: -400, merchant: "Card",
                        categoryCode: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"), false),
            (MoneyEntry(date: day, amount: -200, merchant: "Savings",
                        categoryCode: "TRANSFER_OUT_ACCOUNT_TRANSFER"), false),
            (MoneyEntry(date: day, amount: -900, merchant: "Car loan",
                        categoryCode: "LOAN_PAYMENTS_CAR_PAYMENT"), true),
        ]
        for (entry, expected) in cases {
            #expect(entry.isSpending == expected, "\(entry.merchant)")
            #expect(summarise(entries: [entry]).expenses == (expected ? -entry.amount : 0))
        }
    }

    @Test func upsertMovesABalanceAndALimitOnTheSameAccount() throws {
        // A limit rises when the issuer raises it, and a balance moves every
        // sync. Both must update in place rather than creating a second
        // account, which would double net worth.
        let store = try makeStore()
        try store.upsertAccounts([
            MoneyAccountRow(externalID: "acc_card", name: "Card", type: "credit",
                            subtype: "credit card", mask: "4127",
                            currentBalance: 610.25, availableBalance: nil,
                            creditLimit: 2_000, currencyCode: "USD")
        ])
        try store.upsertAccounts([
            MoneyAccountRow(externalID: "acc_card", name: "Card", type: "credit",
                            subtype: "credit card", mask: "4127",
                            currentBalance: 720.00, availableBalance: nil,
                            creditLimit: 3_000, currencyCode: "USD")
        ])

        let accounts = try store.accounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.currentBalance == 720.00)
        #expect(accounts.first?.creditLimit == 3_000)
    }

    @Test func netWorthStillReadsTypeNotSubtype() throws {
        // A mortgage is type loan with a balance and no utilisation. Net worth
        // must keep subtracting it, so this asserts the rule that must not
        // migrate to subtype.
        let mortgage = MoneyAccount(name: "Mortgage", type: "loan", currentBalance: 240_000)
        #expect(mortgage.netWorthContribution == -240_000)
    }
}
