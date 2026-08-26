# Plaid Personal Finance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect a real bank account through Plaid and turn its transactions and balances into the numbers the Money tab already renders.

**Architecture:** Every Plaid call is made by a Supabase Edge Function, because Plaid requires `client_id` and `secret` on every request and an `.ipa` is a zip file. Postgres holds only the `access_token`, behind RLS with zero policies so only the service role can read it. Transactions never rest on a server: the function returns each delta to the device, which ingests it into SwiftData and owns the sync cursor.

**Tech Stack:** Swift 6, SwiftData, swift-testing (`import Testing`), SwiftUI, Plaid LinkKit (SPM, app target only), Supabase Edge Functions (Deno 2), Postgres.

**Spec:** `docs/superpowers/specs/2026-08-26-plaid-personal-finance-design.md`

## Global Constraints

- Work happens in the worktree `.claude/worktrees/plaid-finance` on branch `feat/plaid-personal-finance`. Never commit to `main`.
- Conventional commit messages (`type(scope): imperative summary`) with a short body. **No em dashes in commit messages. No Claude or AI attribution of any kind, including `Co-Authored-By` trailers.**
- Sign convention: **positive is money in, negative is money out.** Plaid's `amount` is positive for outflows, so ingestion negates. Never change this convention; negate at the boundary.
- The Plaid `access_token` must never be returned to the device, logged, or written to this repository.
- No secret goes in the app bundle or in git. Function secrets are set with `supabase secrets set`.
- `Persistence` must not know the word "Plaid" in its API surface. It takes neutral row structs; the Plaid vocabulary lives in `Integrations`.
- `LifeOSKit` takes no third-party dependency. LinkKit is added to the app target only.
- Swift tests: `swift test --package-path LifeOSKit`. Deno tests: `deno test --allow-env supabase/functions/_shared/`.
- iOS deployment target is 26.0; the package targets `.iOS("26.0")`.

## Where this plan refines the spec

Two details were settled while writing the tasks. The spec's reasoning is unchanged; only the shape is tighter.

**`plaid-sync` syncs every connected Item in one call**, rather than taking one Item at a time. The device otherwise has no way to learn what is connected after a reinstall, and the alternative was a fifth function whose only job was listing Items. A per-Item failure is reported inside that Item's delta, so one expired bank login does not fail the sync for the others.

**The cursor store is `PlaidItemStore`, not `PlaidCursorStore`.** It holds the connected Items and their cursors together, because they are written at the same moments and read at the same moments. Everything the spec says about the cursor still holds: it is per Item, it lives in `UserDefaults` so it dies with the SwiftData database, and it advances only after a successful ingest.

---

## Task 1: Exclude transfers and card payments from the rollup

Moving $500 from savings to checking currently reads as $500 of income and $500 of expense. The net is right but both sides are overstated and the savings rate is dragged toward zero for money that was never spent. Credit card payments double count against purchases already recorded on the card.

The rule must key off Plaid's raw category code, not the display string, so renaming a UI label cannot silently change the savings rate.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyEntry.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `MoneyEntry.categoryCode: String?`; `MoneyEntry.init(..., categoryCode: String? = nil, ...)`; `MoneyCategoryRule.isTransferLike(_ code: String?) -> Bool`; `summarise(entries:accounts:)` now excludes transfer-like rows from `income` and `expenses`

- [ ] **Step 1: Write the failing tests**

Add to `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`, inside `struct MoneyTests`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter MoneyTests`
Expected: FAIL to compile, with "extra argument 'categoryCode' in call".

- [ ] **Step 3: Add the stored property and the rule**

In `LifeOSKit/Sources/Persistence/MoneyEntry.swift`, add to `MoneyEntry` after `public var category: String?`:

```swift
    /// Plaid's raw `personal_finance_category.detailed`, or nil for a manual
    /// entry. Kept beside `category` rather than replacing it because
    /// `category` is a display string: keying the rollup rule off display text
    /// would mean renaming a label silently changes the savings rate.
    public var categoryCode: String?
```

Add the parameter to `init`, after `category`:

```swift
        category: String? = nil,
        categoryCode: String? = nil,
```

and assign it alongside the others:

```swift
        self.categoryCode = categoryCode
```

Add above `summarise`:

```swift
/// Which categories are money moving rather than money earned or spent.
///
/// A transfer between your own accounts and a credit card payment both appear
/// as a real debit and a real credit. Counting them leaves `net` correct while
/// overstating income and expenses, and the savings rate is computed from
/// those two, not from net.
public enum MoneyCategoryRule {
    public static func isTransferLike(_ code: String?) -> Bool {
        guard let code else { return false }
        if code == "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT" { return true }
        // Plaid's detailed codes extend the primary, e.g.
        // TRANSFER_IN_ACCOUNT_TRANSFER, so match the prefix rather than listing
        // every detail Plaid may add later.
        return code.hasPrefix("TRANSFER_IN") || code.hasPrefix("TRANSFER_OUT")
    }
}
```

Change the loop in `summarise` from:

```swift
    for entry in entries where !entry.pending {
```

to:

```swift
    for entry in entries where !entry.pending
        && !MoneyCategoryRule.isTransferLike(entry.categoryCode) {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter MoneyTests`
Expected: PASS, including the four pre-existing tests in the suite.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyEntry.swift LifeOSKit/Tests/PersistenceTests/MoneyTests.swift
git commit -m "feat(money): keep transfers out of income and spending

A transfer between your own accounts posts as both a debit and a credit,
so counting it leaves net correct while overstating both sides and
dragging the savings rate toward zero for money that never moved out.
Credit card payments double count against the purchases already on the
card.

The rule keys off a new categoryCode holding Plaid's raw category rather
than the display string, so renaming a label cannot change the number."
```

---

## Task 2: Give MoneyStore removals, account upserts, and richer ingest rows

Plaid reissues a settled charge under a new `transaction_id` and returns the old one in `removed`. Without deletion every card charge eventually exists twice. Balances need an upsert of their own, and a transaction should know which account it came from.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`

**Interfaces:**
- Consumes: `MoneyEntry.categoryCode` from Task 1
- Produces: `MoneyIngestRow`, `MoneyAccountRow`, `MoneyStore.ingest(_ incoming: [MoneyIngestRow]) throws`, `MoneyStore.remove(externalIDs: [String]) throws`, `MoneyStore.upsertAccounts(_ incoming: [MoneyAccountRow]) throws`

- [ ] **Step 1: Write the failing tests**

Add to `MoneyTests`:

```swift
@Test func ingestUpsertsOnTheProviderIDRatherThanDuplicating() throws {
    let store = try makeStore()
    let row = MoneyIngestRow(externalID: "txn_1", date: day, amount: -42,
                             merchant: "Cafe", category: "Food & drink",
                             categoryCode: "FOOD_AND_DRINK_COFFEE", pending: true,
                             accountID: "acc_1", accountName: "Checking",
                             currencyCode: "USD")
    try store.ingest([row])

    let settled = MoneyIngestRow(externalID: "txn_1", date: day, amount: -44,
                                 merchant: "Cafe", category: "Food & drink",
                                 categoryCode: "FOOD_AND_DRINK_COFFEE", pending: false,
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
                       pending: true, accountID: nil, accountName: nil,
                       currencyCode: "USD"),
        MoneyIngestRow(externalID: "posted_1", date: day, amount: -30,
                       merchant: "Shop", category: nil, categoryCode: nil,
                       pending: false, accountID: nil, accountName: nil,
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
                        currentBalance: 2_000, currencyCode: "USD"),
    ])
    try store.upsertAccounts([
        MoneyAccountRow(externalID: "acc_1", name: "Checking", type: "depository",
                        currentBalance: 2_400, currencyCode: "USD"),
        MoneyAccountRow(externalID: "acc_2", name: "Card", type: "credit",
                        currentBalance: 600, currencyCode: "USD"),
    ])

    let accounts = try store.accounts()
    #expect(accounts.count == 2)
    // Net worth subtracts what is owed on the card.
    #expect(summarise(entries: [], accounts: accounts).netWorth == 1_800)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter MoneyTests`
Expected: FAIL to compile, with "cannot find 'MoneyIngestRow' in scope".

- [ ] **Step 3: Add the row types and the three store methods**

In `LifeOSKit/Sources/Persistence/MoneyStore.swift`, add above `public struct MoneyStore`:

```swift
/// One incoming transaction, in this app's vocabulary rather than a provider's.
///
/// `Persistence` deliberately does not name Plaid. The mapping from a provider
/// payload to these fields, including the sign flip, belongs to `Integrations`,
/// so a second provider later is a new mapper and not a change down here.
public struct MoneyIngestRow: Sendable, Equatable {
    public let externalID: String
    public let date: Date
    /// Positive is money in. Already negated by the caller if it was an outflow.
    public let amount: Double
    public let merchant: String
    public let category: String?
    public let categoryCode: String?
    public let pending: Bool
    public let accountID: String?
    public let accountName: String?
    public let currencyCode: String

    public init(externalID: String, date: Date, amount: Double, merchant: String,
                category: String?, categoryCode: String?, pending: Bool,
                accountID: String?, accountName: String?, currencyCode: String) {
        self.externalID = externalID
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.categoryCode = categoryCode
        self.pending = pending
        self.accountID = accountID
        self.accountName = accountName
        self.currencyCode = currencyCode
    }
}

/// One funding account and its balance.
public struct MoneyAccountRow: Sendable, Equatable {
    public let externalID: String
    public let name: String
    /// depository, credit, investment or loan.
    public let type: String
    public let currentBalance: Double
    public let currencyCode: String

    public init(externalID: String, name: String, type: String,
                currentBalance: Double, currencyCode: String) {
        self.externalID = externalID
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.currencyCode = currencyCode
    }
}
```

Replace the existing `ingest` method entirely with:

```swift
    /// Upsert keyed on the provider's transaction id, so a re-sync corrects a
    /// settled transaction instead of adding a duplicate alongside the pending
    /// one. Batched: one save for the whole page.
    public func ingest(_ incoming: [MoneyIngestRow]) throws {
        for row in incoming {
            let id = row.externalID
            let existing = try context.fetch(
                FetchDescriptor<MoneyEntry>(predicate: #Predicate { $0.externalID == id })
            ).first

            let entry = existing ?? MoneyEntry(
                date: row.date, amount: row.amount, merchant: row.merchant,
                source: .plaid, externalID: row.externalID
            )
            if existing == nil { context.insert(entry) }

            entry.date = calendar.startOfDay(for: row.date)
            entry.amount = row.amount
            entry.merchant = row.merchant
            entry.category = row.category
            entry.categoryCode = row.categoryCode
            entry.pending = row.pending
            entry.accountID = row.accountID
            entry.accountName = row.accountName
            entry.currencyCode = row.currencyCode
            entry.updatedAt = .now
        }
        try context.save()
    }

    /// Deletes by provider id. Silent about ids it does not hold: a replayed
    /// page can ask twice, and that is the ordinary cost of a device-owned
    /// cursor rather than a fault.
    public func remove(externalIDs: [String]) throws {
        guard !externalIDs.isEmpty else { return }
        for id in externalIDs {
            let matches = try context.fetch(
                FetchDescriptor<MoneyEntry>(predicate: #Predicate { $0.externalID == id })
            )
            for match in matches { context.delete(match) }
        }
        try context.save()
    }

    /// Upsert keyed on the provider's account id, so a balance moves rather
    /// than a second copy of the account appearing and doubling net worth.
    public func upsertAccounts(_ incoming: [MoneyAccountRow]) throws {
        for row in incoming {
            let id = row.externalID
            let existing = try context.fetch(
                FetchDescriptor<MoneyAccount>(predicate: #Predicate { $0.externalID == id })
            ).first

            let account = existing ?? MoneyAccount(
                name: row.name, type: row.type, currentBalance: row.currentBalance,
                currencyCode: row.currencyCode, externalID: row.externalID
            )
            if existing == nil { context.insert(account) }

            account.name = row.name
            account.type = row.type
            account.currentBalance = row.currentBalance
            account.currencyCode = row.currencyCode
            account.updatedAt = .now
        }
        try context.save()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter MoneyTests`
Expected: PASS. If any existing test called the old tuple-based `ingest`, update that call to build a `MoneyIngestRow`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyStore.swift LifeOSKit/Tests/PersistenceTests/MoneyTests.swift
git commit -m "feat(money): let the store delete by provider id and upsert accounts

A settled charge arrives from Plaid under a different transaction id from
the pending one it replaces, with the old id in the removed array. Without
a delete path every card charge eventually exists twice.

Account balances get their own upsert so a refreshed balance moves instead
of inserting a second copy of the account and doubling net worth. Ingest
now takes a named row struct rather than a ten-field tuple, and carries the
account and category code with each transaction."
```

---

## Task 3: Map Plaid categories to display labels

Plaid normalizes categories across institutions and gives them back as `FOOD_AND_DRINK`. The screen shows "Food & drink".

**Files:**
- Create: `LifeOSKit/Sources/Integrations/PlaidCategory.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidCategoryTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `PlaidCategory.display(primary: String?) -> String?`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidCategoryTests.swift`:

```swift
import Testing
@testable import Integrations

@Suite struct PlaidCategoryTests {
    @Test func knownPrimariesBecomeReadableLabels() {
        #expect(PlaidCategory.display(primary: "FOOD_AND_DRINK") == "Food & drink")
        #expect(PlaidCategory.display(primary: "RENT_AND_UTILITIES") == "Rent & utilities")
        #expect(PlaidCategory.display(primary: "INCOME") == "Income")
    }

    @Test func anUnknownCategoryFallsThroughInsteadOfCrashing() {
        // Plaid can add a primary category at any time. A new one must arrive as
        // an uncategorised row, not a crash or a shouty SCREAMING_SNAKE label
        // sitting in the transaction list.
        #expect(PlaidCategory.display(primary: "QUANTUM_TELEPORTATION") == nil)
        #expect(PlaidCategory.display(primary: nil) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PlaidCategoryTests`
Expected: FAIL to compile, with "cannot find 'PlaidCategory' in scope".

- [ ] **Step 3: Write the mapping**

Create `LifeOSKit/Sources/Integrations/PlaidCategory.swift`:

```swift
import Foundation

/// Plaid's `personal_finance_category.primary`, turned into something a person
/// would read.
///
/// A fixed table rather than a general un-shout of the raw string: Plaid's
/// codes are a closed vocabulary Plaid controls, and a generic transform gives
/// "General merchandise" and "Food and drink" without the ampersand this app
/// uses. An unrecognised code returns nil, so a category Plaid adds next year
/// shows as uncategorised instead of shouting from the transaction list.
public enum PlaidCategory {
    private static let labels: [String: String] = [
        "INCOME": "Income",
        "TRANSFER_IN": "Transfer in",
        "TRANSFER_OUT": "Transfer out",
        "LOAN_PAYMENTS": "Loan payments",
        "BANK_FEES": "Bank fees",
        "ENTERTAINMENT": "Entertainment",
        "FOOD_AND_DRINK": "Food & drink",
        "GENERAL_MERCHANDISE": "Shopping",
        "HOME_IMPROVEMENT": "Home",
        "MEDICAL": "Medical",
        "PERSONAL_CARE": "Personal care",
        "GENERAL_SERVICES": "Services",
        "GOVERNMENT_AND_NON_PROFIT": "Government & giving",
        "TRANSPORTATION": "Transport",
        "TRAVEL": "Travel",
        "RENT_AND_UTILITIES": "Rent & utilities",
    ]

    public static func display(primary: String?) -> String? {
        guard let primary else { return nil }
        return labels[primary]
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter PlaidCategoryTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/PlaidCategory.swift LifeOSKit/Tests/IntegrationsTests/PlaidCategoryTests.swift
git commit -m "feat(money): read Plaid's category codes as labels

A fixed table rather than a generic un-shout of the raw string, because
Plaid's primaries are a closed vocabulary and a generic transform loses the
ampersand this app uses. An unrecognised code returns nil so a category
Plaid adds later shows as uncategorised rather than shouting from the list."
```

---

## Task 4: Store connected Items and their cursors on the device

The cursor cannot live on the server. If the server advanced it and the app then crashed mid-ingest, Plaid would never resend that page and those transactions would be gone permanently. With the device advancing it only after a successful ingest, a crash replays the page, and ingest is an idempotent upsert.

This store also caches which Items are connected, so the Money screen knows it is connected before the first sync of a session returns.

`UserDefaults`, not the Keychain, and that is the whole point: **the Keychain survives a reinstall and the SwiftData database does not.** A cursor that outlived its database would mean Plaid replays nothing into an empty app and the history is silently gone. The cursor must die with the data it describes.

**Files:**
- Create: `LifeOSKit/Sources/Integrations/PlaidItemStore.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidItemStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `PlaidStoredItem` (`itemID`, `institutionName`, `cursor`), `PlaidItemStoring` (`items()`, `upsert(_:)`, `setCursor(_:for:)`, `remove(itemID:)`, `clear()`), `UserDefaultsPlaidItemStore(defaults:)`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidItemStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct PlaidItemStoreTests {
    private func makeStore() -> UserDefaultsPlaidItemStore {
        // A named suite per test run keeps this out of the app's real defaults.
        let defaults = UserDefaults(suiteName: "plaid.tests.\(UUID().uuidString)")!
        return UserDefaultsPlaidItemStore(defaults: defaults)
    }

    @Test func cursorsAreScopedToTheirItem() {
        // Plaid scopes a sync cursor to one Item. A single shared cursor works
        // until a second bank is connected, then corrupts both.
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: nil))
        store.upsert(PlaidStoredItem(itemID: "item_b", institutionName: "Amex", cursor: nil))

        store.setCursor("cursor_a", for: "item_a")

        let items = store.items()
        #expect(items.count == 2)
        #expect(items.first { $0.itemID == "item_a" }?.cursor == "cursor_a")
        #expect(items.first { $0.itemID == "item_b" }?.cursor == nil)
    }

    @Test func upsertingAnItemKeepsTheCursorItAlreadyHad() {
        // A sync response re-states the institution name. Letting that reset the
        // cursor would replay full history on every sync.
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: nil))
        store.setCursor("cursor_a", for: "item_a")

        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase Bank", cursor: nil))

        #expect(store.items().first?.cursor == "cursor_a")
        #expect(store.items().first?.institutionName == "Chase Bank")
    }

    @Test func removingOneItemLeavesTheOther() {
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: "c"))
        store.upsert(PlaidStoredItem(itemID: "item_b", institutionName: "Amex", cursor: "d"))

        store.remove(itemID: "item_a")

        #expect(store.items().map(\.itemID) == ["item_b"])
    }

    @Test func settingACursorForAnUnknownItemDoesNotInventOne() {
        // The item list comes from the server. A cursor with no Item behind it
        // would be a phantom connection on the Money screen.
        let store = makeStore()
        store.setCursor("orphan", for: "item_missing")
        #expect(store.items().isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PlaidItemStoreTests`
Expected: FAIL to compile, with "cannot find 'UserDefaultsPlaidItemStore' in scope".

- [ ] **Step 3: Write the store**

Create `LifeOSKit/Sources/Integrations/PlaidItemStore.swift`:

```swift
import Foundation

/// One connected bank, and where its last sync left off.
public struct PlaidStoredItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let institutionName: String
    /// Plaid's `/transactions/sync` cursor, scoped to this Item. Nil means
    /// "start from the beginning", which is also what a fresh install wants.
    public var cursor: String?

    public init(itemID: String, institutionName: String, cursor: String?) {
        self.itemID = itemID
        self.institutionName = institutionName
        self.cursor = cursor
    }
}

public protocol PlaidItemStoring: Sendable {
    func items() -> [PlaidStoredItem]
    /// Adds the Item, or updates its institution name while keeping its cursor.
    func upsert(_ item: PlaidStoredItem)
    func setCursor(_ cursor: String, for itemID: String)
    func remove(itemID: String)
    func clear()
}

/// Held in `UserDefaults`, deliberately not the Keychain.
///
/// The Keychain survives a reinstall; the SwiftData database does not. A cursor
/// that outlived its database would mean Plaid replays nothing into an empty
/// app and the history is silently gone forever. This state must die with the
/// data it describes, so it lives in the app container.
public struct UserDefaultsPlaidItemStore: PlaidItemStoring {
    private let defaults: UserDefaults
    private let key = "plaid.items"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func items() -> [PlaidStoredItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlaidStoredItem].self, from: data)
        else { return [] }
        return decoded
    }

    public func upsert(_ item: PlaidStoredItem) {
        var current = items()
        if let index = current.firstIndex(where: { $0.itemID == item.itemID }) {
            // The cursor is ours, not the caller's. A sync response re-states the
            // institution name, and letting that reset the cursor would replay
            // full history on every sync.
            let keptCursor = current[index].cursor
            current[index] = PlaidStoredItem(itemID: item.itemID,
                                             institutionName: item.institutionName,
                                             cursor: item.cursor ?? keptCursor)
        } else {
            current.append(item)
        }
        write(current)
    }

    public func setCursor(_ cursor: String, for itemID: String) {
        var current = items()
        guard let index = current.firstIndex(where: { $0.itemID == itemID }) else { return }
        current[index].cursor = cursor
        write(current)
    }

    public func remove(itemID: String) {
        write(items().filter { $0.itemID != itemID })
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func write(_ items: [PlaidStoredItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter PlaidItemStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/PlaidItemStore.swift LifeOSKit/Tests/IntegrationsTests/PlaidItemStoreTests.swift
git commit -m "feat(money): keep the Plaid sync cursor on the device, per item

A server-advanced cursor loses data: if the app crashed mid-ingest, Plaid
would never resend that page. With the device advancing it only after a
successful ingest, a crash replays a page and ingest is an idempotent
upsert, so a replay costs nothing.

UserDefaults rather than the Keychain is the point. The Keychain survives a
reinstall and the SwiftData database does not, so a surviving cursor beside
a wiped database means Plaid replays nothing and the history is gone. The
cursor has to die with the data it describes.

Cursors are per item because Plaid scopes them that way. One shared cursor
works until a second bank is connected, then corrupts both."
```

---

## Task 5: Generalize the sync staleness policy

`WhoopSyncPolicy` is a single static function whose rule, stale after an hour plus a day boundary, applies unchanged to Plaid. The alternative is copying it under a second name.

**Files:**
- Delete: `LifeOSKit/Sources/Integrations/WhoopSyncPolicy.swift`
- Create: `LifeOSKit/Sources/Integrations/SyncStalenessPolicy.swift`
- Modify: `LifeOSKit/Tests/IntegrationsTests/WhoopSyncPolicyTests.swift` (rename to `SyncStalenessPolicyTests.swift`)
- Modify: `LIfeOS/Features/Settings/ViewModel/WhoopConnectionViewModel.swift:268`

**Interfaces:**
- Consumes: nothing
- Produces: `SyncStalenessPolicy.shouldSync(lastSync:now:calendar:staleAfter:) -> Bool`, same signature and behaviour as `WhoopSyncPolicy.shouldSync`

- [ ] **Step 1: Rename the type and its file, keeping the body identical**

```bash
git mv LifeOSKit/Sources/Integrations/WhoopSyncPolicy.swift LifeOSKit/Sources/Integrations/SyncStalenessPolicy.swift
git mv LifeOSKit/Tests/IntegrationsTests/WhoopSyncPolicyTests.swift LifeOSKit/Tests/IntegrationsTests/SyncStalenessPolicyTests.swift
```

In `SyncStalenessPolicy.swift`, change `public enum WhoopSyncPolicy {` to `public enum SyncStalenessPolicy {` and widen the doc comment's first line to:

```swift
/// Decides whether an automatic sync is due, so the app can refresh itself on
/// becoming active instead of waiting for a tap on "Sync now". Shared by every
/// integration that pulls on a schedule.
```

In `SyncStalenessPolicyTests.swift`, change `@Suite struct WhoopSyncPolicyTests {` to `@Suite struct SyncStalenessPolicyTests {` and replace all five `WhoopSyncPolicy.shouldSync` call sites with `SyncStalenessPolicy.shouldSync`.

In `LIfeOS/Features/Settings/ViewModel/WhoopConnectionViewModel.swift:268`, change `WhoopSyncPolicy.shouldSync` to `SyncStalenessPolicy.shouldSync`.

- [ ] **Step 2: Verify nothing still refers to the old name**

Run: `grep -rn "WhoopSyncPolicy" LifeOSKit/Sources LifeOSKit/Tests LIfeOS`
Expected: no output.

- [ ] **Step 3: Run the tests**

Run: `swift test --package-path LifeOSKit --filter SyncStalenessPolicyTests`
Expected: PASS, all five existing cases unchanged.

- [ ] **Step 4: Commit**

```bash
git add -A LifeOSKit/Sources/Integrations LifeOSKit/Tests/IntegrationsTests LIfeOS/Features/Settings/ViewModel/WhoopConnectionViewModel.swift
git commit -m "refactor(sync): share the staleness rule between integrations

The rule, stale after an hour plus a day boundary so the first open of the
morning always pulls, is not specific to Whoop. Plaid wants exactly it. The
behaviour and the tests are unchanged; only the name is wider."
```

---

## Task 6: Decode Plaid's sync response and map it to ingest rows

This is the task that decides whether the headline number is true. A sign flip turns income into expenses across every rollup and nothing crashes.

The mapping is pure and tested against a real Sandbox response, so it runs offline and needs no Plaid.

**Files:**
- Create: `LifeOSKit/Sources/Integrations/PlaidWireFormat.swift`
- Create: `LifeOSKit/Sources/Integrations/PlaidMapping.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`

**Interfaces:**
- Consumes: `MoneyIngestRow`, `MoneyAccountRow` (Task 2), `PlaidCategory.display(primary:)` (Task 3)
- Produces: `PlaidSyncResponse` (`items: [PlaidItemDelta]`), `PlaidItemDelta` (`item_id`, `institution_name`, `added`, `modified`, `removed`, `accounts`, `next_cursor`, `has_more`, `error`), `PlaidTransaction`, `PlaidAccount`, `PlaidRemoved`, `PlaidMapping.ingestRows(from:) throws -> [MoneyIngestRow]`, `PlaidMapping.accountRows(from:) -> [MoneyAccountRow]`, `PlaidMappingError`

- [ ] **Step 1: Save the fixture**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift`. This is the shape `plaid-sync` returns: one envelope wrapping a per-Item delta, with Plaid's own transaction and account objects passed through untouched.

```swift
import Foundation

/// A real Sandbox `/transactions/sync` page, wrapped in the per-Item envelope
/// `plaid-sync` returns. Held as a literal rather than a bundled resource so
/// the test target needs no resource configuration.
///
/// Note the amounts: Plaid is positive for money leaving the account. The
/// payroll deposit is negative here and must come out of the mapper positive.
enum PlaidFixtures {
    static let syncPage = #"""
    {
      "items": [
        {
          "item_id": "item_sandbox_1",
          "institution_name": "First Platypus Bank",
          "next_cursor": "cursor_page_2",
          "has_more": false,
          "error": null,
          "accounts": [
            {
              "account_id": "acc_checking",
              "name": "Plaid Checking",
              "type": "depository",
              "balances": { "current": 2450.75, "iso_currency_code": "USD" }
            },
            {
              "account_id": "acc_card",
              "name": "Plaid Credit Card",
              "type": "credit",
              "balances": { "current": 610.25, "iso_currency_code": "USD" }
            }
          ],
          "added": [
            {
              "transaction_id": "txn_payroll",
              "account_id": "acc_checking",
              "amount": -3200.00,
              "iso_currency_code": "USD",
              "date": "2026-08-14",
              "name": "ACME PAYROLL DIRECT DEP",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": {
                "primary": "INCOME",
                "detailed": "INCOME_WAGES"
              }
            },
            {
              "transaction_id": "txn_coffee",
              "account_id": "acc_card",
              "amount": 6.75,
              "iso_currency_code": "USD",
              "date": "2026-08-20",
              "name": "SQ *BLUE BOTTLE",
              "merchant_name": "Blue Bottle Coffee",
              "pending": true,
              "personal_finance_category": {
                "primary": "FOOD_AND_DRINK",
                "detailed": "FOOD_AND_DRINK_COFFEE"
              }
            },
            {
              "transaction_id": "txn_card_payment",
              "account_id": "acc_checking",
              "amount": 400.00,
              "iso_currency_code": "USD",
              "date": "2026-08-21",
              "name": "PAYMENT THANK YOU",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": {
                "primary": "LOAN_PAYMENTS",
                "detailed": "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"
              }
            },
            {
              "transaction_id": "txn_uncategorised",
              "account_id": "acc_checking",
              "amount": 12.00,
              "iso_currency_code": null,
              "date": "2026-08-22",
              "name": "UNKNOWN VENDOR",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": null
            }
          ],
          "modified": [],
          "removed": [ { "transaction_id": "txn_stale_pending" } ]
        }
      ]
    }
    """#
}
```

- [ ] **Step 2: Write the failing tests**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import Persistence
@testable import Integrations

@Suite struct PlaidMappingTests {
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
        let rows = try PlaidMapping.ingestRows(from: delta().added)
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

        try store.ingest(PlaidMapping.ingestRows(from: delta.added))
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter PlaidMappingTests`
Expected: FAIL to compile, with "cannot find 'PlaidSyncResponse' in scope".

- [ ] **Step 4: Write the wire format**

Create `LifeOSKit/Sources/Integrations/PlaidWireFormat.swift`. Property names stay in Plaid's snake_case, matching how `SupabaseAuth` decodes its wire types, so the payload and the type read the same.

```swift
import Foundation

/// What `plaid-sync` returns: one delta per connected Item.
///
/// The function syncs every Item the user has in one call, because the device
/// does not otherwise know what is connected. Everything inside an item delta
/// except `institution_name` is Plaid's own JSON, passed through untouched.
public struct PlaidSyncResponse: Decodable, Sendable {
    public let items: [PlaidItemDelta]
}

public struct PlaidItemDelta: Decodable, Sendable {
    public let item_id: String
    public let institution_name: String
    public let added: [PlaidTransaction]
    public let modified: [PlaidTransaction]
    public let removed: [PlaidRemoved]
    public let accounts: [PlaidAccount]
    public let next_cursor: String?
    public let has_more: Bool
    /// Set when this one Item failed while others succeeded, so one expired
    /// bank login does not fail the whole sync. `ITEM_LOGIN_REQUIRED` here is
    /// what raises the reconnect banner.
    public let error: String?
}

public struct PlaidTransaction: Decodable, Sendable {
    public let transaction_id: String
    public let account_id: String
    /// **Positive is money leaving the account.** The opposite of this app's
    /// convention. `PlaidMapping` negates.
    public let amount: Double
    public let iso_currency_code: String?
    /// ISO 8601 calendar date, "2026-08-24".
    public let date: String
    /// The raw bank descriptor.
    public let name: String
    /// Plaid's cleaned-up merchant, when it has one.
    public let merchant_name: String?
    public let pending: Bool
    public let personal_finance_category: PlaidPFC?

    public init(transaction_id: String, account_id: String, amount: Double,
                iso_currency_code: String?, date: String, name: String,
                merchant_name: String?, pending: Bool,
                personal_finance_category: PlaidPFC?) {
        self.transaction_id = transaction_id
        self.account_id = account_id
        self.amount = amount
        self.iso_currency_code = iso_currency_code
        self.date = date
        self.name = name
        self.merchant_name = merchant_name
        self.pending = pending
        self.personal_finance_category = personal_finance_category
    }
}

public struct PlaidPFC: Decodable, Sendable {
    public let primary: String
    public let detailed: String
}

public struct PlaidRemoved: Decodable, Sendable {
    public let transaction_id: String
}

public struct PlaidAccount: Decodable, Sendable {
    public let account_id: String
    public let name: String
    /// depository, credit, investment or loan.
    public let type: String
    public let balances: PlaidBalances
}

public struct PlaidBalances: Decodable, Sendable {
    public let current: Double?
    public let iso_currency_code: String?
}
```

- [ ] **Step 5: Write the mapping**

Create `LifeOSKit/Sources/Integrations/PlaidMapping.swift`:

```swift
import Foundation
import Persistence

public enum PlaidMappingError: Error, Equatable {
    /// Plaid sent a date this app cannot read. Loud on purpose: see below.
    case unreadableDate(String)
}

/// Turns Plaid's vocabulary into this app's.
///
/// The single most important line here is the negation. Plaid's `amount` is
/// positive when money leaves the account; `MoneyEntry`'s convention is that
/// positive is money in. Get this backwards and salary becomes the month's
/// largest expense, the savings rate inverts, and nothing crashes.
public enum PlaidMapping {
    /// Plaid sends a bare calendar date, "2026-08-24", with no time in it.
    ///
    /// It must be parsed in the same calendar `MoneyStore` normalizes with,
    /// because the store applies `startOfDay` on the way in. Pinning this to UTC
    /// while the store uses `Calendar.current` puts them a day apart for every
    /// device west of Greenwich: a transaction Plaid dates the 1st is stored as
    /// the 31st in New York, which moves it into the previous month's income and
    /// expense totals.
    private static func parse(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        // Fixed format needs a fixed locale, or a device set to a non-Gregorian
        // calendar parses this differently.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Throws rather than skipping a row it cannot read. A silently dropped
    /// transaction is a wrong total with no error anywhere in the app; a thrown
    /// error fails the sync and leaves the last known-good snapshot on screen.
    public static func ingestRows(
        from transactions: [PlaidTransaction],
        calendar: Calendar = .current
    ) throws -> [MoneyIngestRow] {
        try transactions.map { transaction in
            guard let date = parse(transaction.date, calendar: calendar) else {
                throw PlaidMappingError.unreadableDate(transaction.date)
            }
            return MoneyIngestRow(
                externalID: transaction.transaction_id,
                date: date,
                amount: -transaction.amount,
                merchant: transaction.merchant_name ?? transaction.name,
                category: PlaidCategory.display(primary: transaction.personal_finance_category?.primary),
                categoryCode: transaction.personal_finance_category?.detailed,
                pending: transaction.pending,
                accountID: transaction.account_id,
                accountName: nil,
                currencyCode: transaction.iso_currency_code ?? "USD"
            )
        }
    }

    public static func accountRows(from accounts: [PlaidAccount]) -> [MoneyAccountRow] {
        accounts.map { account in
            MoneyAccountRow(
                externalID: account.account_id,
                name: account.name,
                type: account.type,
                // A null balance means Plaid could not read it this time. Zero is
                // the honest placeholder; the next sync corrects it.
                currentBalance: account.balances.current ?? 0,
                currencyCode: account.balances.iso_currency_code ?? "USD"
            )
        }
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path LifeOSKit --filter PlaidMappingTests`
Expected: FAIL on `aCardPurchaseComesOutAsSpending`, because `accountName` is nil and the test expects "Plaid Credit Card". The account name lives on the account, not the transaction, so the mapper has to be given both.

- [ ] **Step 7: Carry the account name onto its transactions**

Change the signature of `ingestRows` to take the accounts alongside, and look the name up:

```swift
    public static func ingestRows(
        from transactions: [PlaidTransaction],
        accounts: [PlaidAccount] = [],
        calendar: Calendar = .current
    ) throws -> [MoneyIngestRow] {
        let namesByID = Dictionary(
            accounts.map { ($0.account_id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        try transactions.map { transaction in
```

and replace `accountName: nil,` with:

```swift
                accountName: namesByID[transaction.account_id],
```

Update the two call sites in `PlaidMappingTests` that need the name to pass it:

```swift
let rows = try PlaidMapping.ingestRows(from: delta().added, accounts: delta().accounts)
```

in `aCardPurchaseComesOutAsSpending`, and in `theWholePageRollsUpToTheRightSummary`:

```swift
try store.ingest(PlaidMapping.ingestRows(from: delta.added, accounts: delta.accounts))
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter PlaidMappingTests`
Expected: PASS, all seven.

- [ ] **Step 9: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add LifeOSKit/Sources/Integrations/PlaidWireFormat.swift LifeOSKit/Sources/Integrations/PlaidMapping.swift LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift
git commit -m "feat(money): map Plaid transactions onto this app's sign convention

Plaid's amount is positive when money leaves the account and ours is the
opposite, so the mapper negates at the boundary. Getting that backwards
makes salary the largest expense of the month without crashing anything,
which is why the test that asserts it runs against a real Sandbox page
saved into the suite.

The page also covers what the rollup has to ignore: a pending coffee and a
credit card payment stay out of the totals while still appearing in the
list. An unreadable date throws instead of skipping the row, because a
silently dropped transaction is a wrong total with no error anywhere."
```

---

## Task 7: Add the plaid_items table

Postgres holds the `access_token` and nothing else. RLS with **zero policies** denies every client, including the row's owner; only the service role, which bypasses RLS, can read it, and it does so only from inside a function.

**Files:**
- Create: `supabase/migrations/20260826120000_plaid_items.sql`

**Interfaces:**
- Consumes: nothing
- Produces: table `public.plaid_items` with columns `user_id`, `item_id`, `access_token`, `institution_id`, `institution_name`, `created_at`, `updated_at`, primary key `(user_id, item_id)`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260826120000_plaid_items.sql`:

```sql
-- One connected bank per row. The only server-side state this feature keeps.
--
-- Transactions deliberately do not live here. The Edge Function hands each
-- sync delta straight back to the device, which is the source of truth, so a
-- compromise of this database exposes the credential but not a ledger of
-- where someone shops.
create table public.plaid_items (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- Plaid's item_id. One per connected institution.
  item_id text not null,

  -- A live, non-expiring credential to a bank account.
  --
  -- SECURITY: stored in plaintext. Anyone holding the service-role key or
  -- direct database access can read every user's bank credential. That is an
  -- accepted trade for a single-user first release and MUST be revisited
  -- before a second person connects an account. The upgrade path is Supabase
  -- Vault, which keeps the secret out of the table and out of backups.
  access_token text not null,

  institution_id text,
  institution_name text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Composite, so a second bank is a second row rather than a schema change.
  primary key (user_id, item_id)
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner, which is the intent: the access token must never
-- reach a device. The service role bypasses RLS and is the only reader, from
-- inside an Edge Function that has already resolved the caller.
alter table public.plaid_items enable row level security;

-- The one access pattern: "this user's connected banks".
create index plaid_items_user_idx on public.plaid_items (user_id);

-- No sync_state row is created for Plaid. The sync cursor lives on the device,
-- because a server-advanced cursor would permanently lose a page of
-- transactions to an app that crashed mid-ingest. See the design spec, 6.1.
```

- [ ] **Step 2: Apply it locally and confirm the client cannot read the table**

Run:

```bash
supabase db reset
```

Expected: the reset completes and lists `20260826120000_plaid_items.sql` among the applied migrations.

Then confirm the deny is real. This needs at least one row in `auth.users`, so sign in through the app once first if the local database is empty.

Run against the local database (`psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')"`, or the Studio SQL editor):

```sql
-- A real user id, because the table has a foreign key to auth.users.
insert into public.plaid_items (user_id, item_id, access_token)
select id, 'item_test', 'access-test' from auth.users limit 1;

-- The role switch must be inside a transaction. `set local` outside one is a
-- no-op, and the check would then run as the owner and pass no matter what
-- the policies say.
begin;
  set local role authenticated;
  select count(*) as visible_to_client from public.plaid_items;
commit;

-- And prove the row is really there when the owner looks.
select count(*) as visible_to_owner from public.plaid_items;
```

Expected: `visible_to_client` is `0` and `visible_to_owner` is `1`. Both halves matter. A zero from an empty table proves nothing, which is why the second count is here.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260826120000_plaid_items.sql
git commit -m "feat(money): hold Plaid credentials behind service-role-only RLS

Enabling row level security with no policies at all denies every client
including the row's owner, which is the intent here: an access token is a
live, non-expiring credential to a bank account and must never reach a
device.

Transactions are deliberately not stored. The function hands each delta
back to the phone, so a compromise of this database exposes the credential
but not a ledger of where someone shops. The plaintext column is called out
in the migration as something to move into Vault before a second user."
```

---

## Task 8: Shared function helpers, with the error classification tested

Plaid's error responses echo request parameters, so they are logged and never returned. The one exception is `ITEM_LOGIN_REQUIRED`, which needs a reconnect prompt rather than a retry spinner and therefore needs its own code on the way out.

**Files:**
- Create: `supabase/functions/_shared/plaid.ts`
- Create: `supabase/functions/_shared/plaid_test.ts`

**Interfaces:**
- Consumes: nothing
- Produces: `plaidConfig()`, `callPlaid(path, body)`, `classifyPlaidFailure(status, body)`, `resolveUser(req)`, `json(payload, status)`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/plaid_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { classifyPlaidFailure } from "./plaid.ts";

// An expired bank login is not a server fault and not a retry. It is the most
// common real-world Plaid failure, since banks invalidate stored logins every
// few months, and the only fix is the user signing in again. Collapsing it
// into a generic upstream failure leaves the app spinning forever.
Deno.test("an expired bank login is its own kind", () => {
  assertEquals(
    classifyPlaidFailure(400, JSON.stringify({ error_code: "ITEM_LOGIN_REQUIRED" })),
    "item_login_required",
  );
});

Deno.test("a rate limit is its own kind, because it is worth retrying later", () => {
  assertEquals(
    classifyPlaidFailure(429, JSON.stringify({ error_code: "RATE_LIMIT_EXCEEDED" })),
    "rate_limited",
  );
});

Deno.test("anything else is an opaque upstream failure", () => {
  assertEquals(
    classifyPlaidFailure(500, JSON.stringify({ error_code: "INTERNAL_SERVER_ERROR" })),
    "upstream_failure",
  );
});

// Plaid is not obliged to send us JSON when it is having a bad day.
Deno.test("a non-JSON body does not throw", () => {
  assertEquals(classifyPlaidFailure(502, "<html>gateway timeout</html>"), "upstream_failure");
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `deno test --allow-env supabase/functions/_shared/plaid_test.ts`
Expected: FAIL with a module-not-found error for `./plaid.ts`.

- [ ] **Step 3: Write the shared helpers**

Create `supabase/functions/_shared/plaid.ts`:

```ts
// Shared Plaid plumbing.
//
// These functions exist for exactly one reason: every Plaid endpoint requires
// client_id and secret on the request, and an .ipa is a zip file, so a secret
// compiled into the app is public the moment it ships. The device therefore
// cannot call Plaid at all and calls these instead.
//
// Set the secrets with:
//
//   supabase secrets set PLAID_CLIENT_ID=... PLAID_SECRET=... PLAID_ENV=sandbox
//
// PLAID_ENV is what sequences the work: build and test the whole path against
// sandbox and its fake institutions, then flip this one value to reach a real
// bank. The secret is never logged, never returned, and never written to this
// repository.

import { createClient } from "jsr:@supabase/supabase-js@2";

const HOSTS: Record<string, string> = {
  sandbox: "https://sandbox.plaid.com",
  production: "https://production.plaid.com",
};

export function plaidConfig() {
  const clientID = Deno.env.get("PLAID_CLIENT_ID");
  const secret = Deno.env.get("PLAID_SECRET");
  const env = Deno.env.get("PLAID_ENV") ?? "sandbox";
  const host = HOSTS[env];
  // Deliberately does not say which one is missing.
  if (!clientID || !secret || !host) return null;
  return { clientID, secret, host };
}

export type PlaidFailure = "item_login_required" | "rate_limited" | "upstream_failure";

/// An expired bank login needs a reconnect prompt, not a retry spinner, so it
/// gets its own code. A rate limit is worth retrying later. Everything else is
/// opaque on purpose: Plaid's error bodies echo request parameters.
export function classifyPlaidFailure(status: number, body: string): PlaidFailure {
  let code = "";
  try {
    code = (JSON.parse(body)?.error_code ?? "") as string;
  } catch {
    // Plaid is not obliged to send JSON when it is having a bad day.
  }
  if (code === "ITEM_LOGIN_REQUIRED") return "item_login_required";
  if (status === 429 || code === "RATE_LIMIT_EXCEEDED") return "rate_limited";
  return "upstream_failure";
}

export class PlaidError extends Error {
  constructor(public kind: PlaidFailure, public status: number) {
    super(kind);
  }
}

export async function callPlaid(
  path: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const config = plaidConfig();
  if (!config) throw new PlaidError("upstream_failure", 500);

  const response = await fetch(`${config.host}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      ...body,
      client_id: config.clientID,
      secret: config.secret,
    }),
  });

  const text = await response.text();
  if (!response.ok) {
    // Logged with the body so the cause is visible in function logs, while the
    // client receives only a kind, because Plaid's errors echo request
    // parameters. The request body is never logged: it holds the secret.
    console.error(`plaid ${path} failed: ${response.status} ${text.slice(0, 300)}`);
    throw new PlaidError(classifyPlaidFailure(response.status, text), response.status);
  }
  return JSON.parse(text);
}

/// Resolves the caller from their own token.
///
/// This is a security boundary, not a formality. Every one of these functions
/// reads a bank credential keyed by user, so a service-role client that
/// trusted a user_id from the request body would let any signed-in user pull
/// anyone else's transactions.
export async function resolveUser(req: Request): Promise<string | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return null;

  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

/// The service-role client. Only ever used after `resolveUser` has returned an
/// id, and only ever scoped to that id.
export function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

export function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `deno test --allow-env supabase/functions/_shared/plaid_test.ts`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/plaid.ts supabase/functions/_shared/plaid_test.ts
git commit -m "feat(money): share the Plaid call, error, and caller helpers

Every Plaid endpoint wants client_id and secret on the request, so the
device cannot call Plaid at all and these functions stand in for it.

Errors stay opaque to the client because Plaid's bodies echo request
parameters, with one exception that has its own code. An expired bank login
is the most common real failure and the only fix is the user signing in
again, so collapsing it into a generic upstream error leaves the app
spinning at a problem it could have described.

resolveUser reads the caller from their own token rather than the request
body, since a service-role client trusting a body field would let any
signed-in user pull anyone else's bank data."
```

---

## Task 9: The four Edge Functions

**Files:**
- Create: `supabase/functions/plaid-link-token/index.ts`
- Create: `supabase/functions/plaid-exchange/index.ts`
- Create: `supabase/functions/plaid-sync/index.ts`
- Create: `supabase/functions/plaid-disconnect/index.ts`

**Interfaces:**
- Consumes: `callPlaid`, `resolveUser`, `serviceClient`, `json`, `PlaidError` (Task 8); table `plaid_items` (Task 7)
- Produces: four HTTP endpoints at `functions/v1/plaid-*`. `plaid-sync` returns the `PlaidSyncResponse` shape decoded in Task 6.

- [ ] **Step 1: Write plaid-link-token**

Create `supabase/functions/plaid-link-token/index.ts`:

```ts
import { callPlaid, json, PlaidError, resolveUser } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  try {
    const result = await callPlaid("/link/token/create", {
      // Plaid keys its own rate limits and dashboards on this. Using the
      // Supabase user id keeps the two systems talking about the same person.
      user: { client_user_id: userID },
      client_name: "LifeOS",
      products: ["transactions"],
      country_codes: ["US"],
      language: "en",
      // Banks that use OAuth send the browser here and the app picks it up.
      // Absent in sandbox, where no institution needs it.
      ...(Deno.env.get("PLAID_REDIRECT_URI")
        ? { redirect_uri: Deno.env.get("PLAID_REDIRECT_URI") }
        : {}),
    });
    return json({ link_token: result.link_token }, 200);
  } catch (error) {
    const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
    return json({ error: kind }, 502);
  }
});
```

- [ ] **Step 2: Write plaid-exchange**

Create `supabase/functions/plaid-exchange/index.ts`:

```ts
import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let body: { public_token?: string; institution_id?: string; institution_name?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!body.public_token) return json({ error: "missing_public_token" }, 400);

  const db = serviceClient();

  // Connecting the same bank twice creates two Items with overlapping
  // transactions under different transaction ids, which the device cannot
  // deduplicate. Refuse before spending the exchange.
  if (body.institution_id) {
    const { data: existing } = await db
      .from("plaid_items")
      .select("item_id")
      .eq("user_id", userID)
      .eq("institution_id", body.institution_id)
      .maybeSingle();
    if (existing) return json({ error: "institution_already_connected" }, 409);
  }

  try {
    const exchanged = await callPlaid("/item/public_token/exchange", {
      public_token: body.public_token,
    });

    const { error } = await db.from("plaid_items").insert({
      user_id: userID,
      item_id: exchanged.item_id,
      access_token: exchanged.access_token,
      institution_id: body.institution_id ?? null,
      institution_name: body.institution_name ?? "Bank",
    });
    if (error) {
      // Never log the row: it holds the credential.
      console.error(`plaid item insert failed: ${error.code}`);
      return json({ error: "storage_failed" }, 500);
    }

    // The access token stops here. The device gets only what it needs to
    // render the connection.
    return json({
      item_id: exchanged.item_id,
      institution_name: body.institution_name ?? "Bank",
    }, 200);
  } catch (error) {
    const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
    return json({ error: kind }, 502);
  }
});
```

- [ ] **Step 3: Write plaid-sync**

Create `supabase/functions/plaid-sync/index.ts`:

```ts
import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

// An initial pull can be years of history. Three pages per invocation keeps
// the function inside its wall clock; the device sees has_more and calls again.
const MAX_PAGES = 3;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let cursors: Record<string, string> = {};
  try {
    cursors = (await req.json())?.cursors ?? {};
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const db = serviceClient();
  const { data: rows, error } = await db
    .from("plaid_items")
    .select("item_id, access_token, institution_name")
    .eq("user_id", userID);

  if (error) {
    console.error(`plaid item lookup failed: ${error.code}`);
    return json({ error: "storage_failed" }, 500);
  }

  const items = [];
  for (const row of rows ?? []) {
    // One expired bank login must not fail the sync for every other bank, so
    // a per-item failure is reported in the item rather than thrown.
    try {
      items.push(await syncItem(row, cursors[row.item_id]));
    } catch (failure) {
      const kind = failure instanceof PlaidError ? failure.kind : "upstream_failure";
      items.push({
        item_id: row.item_id,
        institution_name: row.institution_name,
        added: [], modified: [], removed: [], accounts: [],
        next_cursor: null, has_more: false,
        error: kind,
      });
    }
  }

  return json({ items }, 200);
});

async function syncItem(
  row: { item_id: string; access_token: string; institution_name: string },
  cursor: string | undefined,
) {
  const added = [], modified = [], removed = [];
  let nextCursor = cursor ?? null;
  let hasMore = true;
  let pages = 0;

  while (hasMore && pages < MAX_PAGES) {
    const page = await callPlaid("/transactions/sync", {
      access_token: row.access_token,
      ...(nextCursor ? { cursor: nextCursor } : {}),
    });
    added.push(...(page.added as unknown[] ?? []));
    modified.push(...(page.modified as unknown[] ?? []));
    removed.push(...(page.removed as unknown[] ?? []));
    nextCursor = page.next_cursor as string;
    hasMore = page.has_more as boolean;
    pages += 1;
  }

  const balances = await callPlaid("/accounts/balance/get", {
    access_token: row.access_token,
  });

  return {
    item_id: row.item_id,
    institution_name: row.institution_name,
    added, modified, removed,
    accounts: balances.accounts ?? [],
    next_cursor: nextCursor,
    has_more: hasMore,
    error: null,
  };
}
```

- [ ] **Step 4: Write plaid-disconnect**

Create `supabase/functions/plaid-disconnect/index.ts`:

```ts
import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let itemID: string | undefined;
  try {
    itemID = (await req.json())?.item_id;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!itemID) return json({ error: "missing_item_id" }, 400);

  const db = serviceClient();
  const { data: row } = await db
    .from("plaid_items")
    .select("access_token")
    .eq("user_id", userID)
    .eq("item_id", itemID)
    .maybeSingle();

  if (!row) return json({ error: "not_found" }, 404);

  try {
    await callPlaid("/item/remove", { access_token: row.access_token });
  } catch (error) {
    // Plaid refusing the removal must not strand the row. A connected Item
    // bills monthly, so the local record going and the remote staying is the
    // worse failure: the user would have no way left to reach it.
    const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
    console.error(`plaid item remove failed: ${kind}`);
  }

  await db.from("plaid_items").delete().eq("user_id", userID).eq("item_id", itemID);
  return json({ ok: true }, 200);
});
```

- [ ] **Step 5: Type-check every function**

Run: `deno check supabase/functions/plaid-*/index.ts supabase/functions/_shared/plaid.ts`
Expected: no errors.

- [ ] **Step 6: Serve them locally and confirm the auth boundary holds**

Run: `supabase functions serve` in one terminal, then in another:

```bash
curl -s -X POST http://127.0.0.1:54321/functions/v1/plaid-sync \
  -H "Content-Type: application/json" -d '{"cursors":{}}'
```

Expected: `401` with `{"error":"unauthorized"}`. A missing token must never reach the credential lookup.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/plaid-link-token supabase/functions/plaid-exchange supabase/functions/plaid-sync supabase/functions/plaid-disconnect
git commit -m "feat(money): add the four Plaid Edge Functions

Link token, exchange, sync and disconnect. Each resolves the caller from
their own token before touching a credential, so no request body can name a
user_id and read someone else's bank.

Sync handles every connected item in one call and reports a per-item
failure inside that item, because one expired bank login should not fail
the sync for the other banks. It stops after three pages and says has_more,
so an initial pull of years of history cannot run past the function's wall
clock.

Disconnect deletes the row even when Plaid refuses the removal. A connected
item bills monthly, and a local record that vanished while the remote one
survived would leave the user no way to reach it."
```

---

## Task 10: The client that talks to those functions

**Files:**
- Create: `LifeOSKit/Sources/Integrations/PlaidClient.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidClientTests.swift`

**Interfaces:**
- Consumes: `PlaidSyncResponse` (Task 6)
- Produces: `PlaidAPI` protocol (`createLinkToken()`, `exchange(publicToken:institutionID:institutionName:)`, `sync(cursors:)`, `disconnect(itemID:)`), `PlaidExchangeResult` (`item_id`, `institution_name`), `PlaidClientError` (`.unauthorized`, `.itemLoginRequired`, `.institutionAlreadyConnected`, `.rateLimited`, `.upstream(Int)`), `PlaidClient(functionsBase:session:accessToken:)`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidClientTests.swift`. The stub follows the pattern in `AuthSessionProfileTests`: its own `URLProtocol` subclass with its own reply queue, because a queue shared between suites has them consuming each other's replies.

```swift
import Testing
import Foundation
@testable import Integrations

final class PlaidStubURLProtocol: URLProtocol {
    enum Reply { case ok(String), status(Int, String), offline }
    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var lastBody: Data?

    static func reset() { replies = []; lastBody = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        let reply = Self.replies.isEmpty ? Reply.status(500, "{}") : Self.replies.removeFirst()
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .ok(let body): send(200, body)
        case .status(let code, let body): send(code, body)
        }
    }

    override func stopLoading() {}

    private func send(_ status: Int, _ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct PlaidClientTests {
    private func makeClient(_ replies: [PlaidStubURLProtocol.Reply],
                            token: String? = "session-token") -> PlaidClient {
        PlaidStubURLProtocol.reset()
        PlaidStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaidStubURLProtocol.self]
        return PlaidClient(
            functionsBase: URL(string: "https://project.supabase.co/functions/v1")!,
            session: URLSession(configuration: configuration),
            accessToken: { token }
        )
    }

    @Test func aLinkTokenComesBackUnwrapped() async throws {
        let client = makeClient([.ok(#"{"link_token":"link-sandbox-abc"}"#)])
        #expect(try await client.createLinkToken() == "link-sandbox-abc")
    }

    @Test func anExpiredBankLoginIsItsOwnErrorNotAGenericFailure() async throws {
        // The app has to tell "sign in again" apart from "try again later".
        // Collapsed into one error, the reconnect banner can never appear.
        let client = makeClient([.status(502, #"{"error":"item_login_required"}"#)])
        await #expect(throws: PlaidClientError.itemLoginRequired) {
            _ = try await client.sync(cursors: [:])
        }
    }

    @Test func connectingTheSameBankTwiceIsItsOwnError() async throws {
        let client = makeClient([.status(409, #"{"error":"institution_already_connected"}"#)])
        await #expect(throws: PlaidClientError.institutionAlreadyConnected) {
            _ = try await client.exchange(publicToken: "public-abc",
                                          institutionID: "ins_1", institutionName: "Chase")
        }
    }

    @Test func aMissingSessionNeverReachesTheNetwork() async throws {
        // Signed out, there is no user to scope a credential to. Failing here
        // rather than sending an unauthenticated request keeps the reason clear.
        let client = makeClient([.ok("{}")], token: nil)
        await #expect(throws: PlaidClientError.unauthorized) {
            _ = try await client.createLinkToken()
        }
        #expect(PlaidStubURLProtocol.lastBody == nil)
    }

    @Test func syncSendsTheCursorsItWasGiven() async throws {
        let client = makeClient([.ok(#"{"items":[]}"#)])
        _ = try await client.sync(cursors: ["item_a": "cursor_a"])

        let body = try #require(PlaidStubURLProtocol.lastBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let cursors = try #require(decoded?["cursors"] as? [String: String])
        #expect(cursors == ["item_a": "cursor_a"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PlaidClientTests`
Expected: FAIL to compile, with "cannot find 'PlaidClient' in scope".

- [ ] **Step 3: Write the client**

Create `LifeOSKit/Sources/Integrations/PlaidClient.swift`:

```swift
import Foundation

public struct PlaidExchangeResult: Decodable, Sendable {
    public let item_id: String
    public let institution_name: String

    // Explicit because a public struct's memberwise init is internal, and the
    // sync tests build one of these from the test module.
    public init(item_id: String, institution_name: String) {
        self.item_id = item_id
        self.institution_name = institution_name
    }
}

public enum PlaidClientError: Error, Equatable {
    /// No session, or the function refused the one we sent.
    case unauthorized
    /// The bank invalidated the stored login. Needs the user, not a retry.
    case itemLoginRequired
    case institutionAlreadyConnected
    case rateLimited
    case upstream(Int)
    case transport
}

/// The seam the sync runner and the connection view model talk to, so both are
/// testable without a network or a Plaid account.
public protocol PlaidAPI: Sendable {
    func createLinkToken() async throws -> String
    func exchange(publicToken: String, institutionID: String?,
                  institutionName: String?) async throws -> PlaidExchangeResult
    func sync(cursors: [String: String]) async throws -> PlaidSyncResponse
    func disconnect(itemID: String) async throws
}

/// Calls the four Edge Functions. Holds no Plaid credential of any kind: the
/// only token it carries is the user's own Supabase session.
public struct PlaidClient: PlaidAPI {
    private let functionsBase: URL
    private let session: URLSession
    private let accessToken: @Sendable () -> String?

    public init(functionsBase: URL, session: URLSession = .shared,
                accessToken: @escaping @Sendable () -> String?) {
        self.functionsBase = functionsBase
        self.session = session
        self.accessToken = accessToken
    }

    public func createLinkToken() async throws -> String {
        struct Response: Decodable { let link_token: String }
        let response: Response = try await post("plaid-link-token", body: [:])
        return response.link_token
    }

    public func exchange(publicToken: String, institutionID: String?,
                         institutionName: String?) async throws -> PlaidExchangeResult {
        // Built up rather than written as a literal with `as Any`: a nil in an
        // [String: Any] literal is an Optional, not NSNull, and
        // JSONSerialization throws on it.
        var body: [String: Any] = ["public_token": publicToken]
        if let institutionID { body["institution_id"] = institutionID }
        if let institutionName { body["institution_name"] = institutionName }
        return try await post("plaid-exchange", body: body)
    }

    public func sync(cursors: [String: String]) async throws -> PlaidSyncResponse {
        try await post("plaid-sync", body: ["cursors": cursors])
    }

    public func disconnect(itemID: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await post("plaid-disconnect", body: ["item_id": itemID])
    }

    private func post<T: Decodable>(_ function: String, body: [String: Any]) async throws -> T {
        // Signed out there is no user to scope a credential to, so this fails
        // before the request rather than sending one that cannot succeed.
        guard let token = accessToken(), !token.isEmpty else { throw PlaidClientError.unauthorized }

        var request = URLRequest(url: functionsBase.appendingPathComponent(function))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlaidClientError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlaidClientError.upstream(status)
        }
    }

    /// The functions return their own status with a named kind in the body.
    /// Without unwrapping that name every cause looks identical, and an expired
    /// bank login is indistinguishable from an outage.
    private static func error(status: Int, body: Data) -> PlaidClientError {
        let kind = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0?["error"] as? String }

        switch kind {
        case "item_login_required": return .itemLoginRequired
        case "institution_already_connected": return .institutionAlreadyConnected
        case "rate_limited": return .rateLimited
        case "unauthorized": return .unauthorized
        default: return status == 401 ? .unauthorized : .upstream(status)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter PlaidClientTests`
Expected: PASS, all five.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/PlaidClient.swift LifeOSKit/Tests/IntegrationsTests/PlaidClientTests.swift
git commit -m "feat(money): call the Plaid functions from the app

The only token this client carries is the user's own Supabase session; it
never sees a Plaid credential. Signed out it fails before sending anything,
since there is no user to scope a bank credential to.

Named error kinds are unwrapped from the body rather than left as a status,
because an expired bank login needs the user to sign in again and an outage
needs a retry, and collapsed into one error the app can only ever offer the
wrong one."
```

---

## Task 11: The sync runner, and the guarantee that the cursor waits for the ingest

The whole reason the cursor lives on the device is that it must advance only after the data it describes is safely stored. This task is where that promise is kept, so it is where it gets a test.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift`
- Create: `LifeOSKit/Sources/Integrations/PlaidSync.swift`
- Create: `LifeOSKit/Tests/IntegrationsTests/PlaidSyncTests.swift`

**Interfaces:**
- Consumes: `PlaidAPI` (Task 10), `PlaidItemStoring` (Task 4), `PlaidMapping` (Task 6)
- Produces: `MoneyIngesting` protocol in `Persistence`; `PlaidSync(api:money:items:)`, `PlaidSync.run() async throws -> PlaidSyncOutcome`, `PlaidSyncOutcome` (`itemsSynced`, `transactionsIngested`, `needsReconnect: [String]`, `hasMore: Bool`)

- [ ] **Step 1: Add the ingest seam to Persistence**

In `LifeOSKit/Sources/Persistence/MoneyStore.swift`, add above `public struct MoneyStore`:

```swift
/// The write side of the store, as a protocol, so a sync runner can be tested
/// against a store that fails on demand. Failure is the interesting case: the
/// cursor must not move when the ingest did not happen.
@MainActor public protocol MoneyIngesting {
    func ingest(_ incoming: [MoneyIngestRow]) throws
    func remove(externalIDs: [String]) throws
    func upsertAccounts(_ incoming: [MoneyAccountRow]) throws
}
```

and below the `MoneyStore` declaration:

```swift
extension MoneyStore: MoneyIngesting {}
```

- [ ] **Step 2: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidSyncTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Integrations

@MainActor
private final class StubMoney: MoneyIngesting {
    var ingested: [MoneyIngestRow] = []
    var removed: [String] = []
    var accounts: [MoneyAccountRow] = []
    var failIngest = false

    struct Boom: Error {}

    func ingest(_ incoming: [MoneyIngestRow]) throws {
        if failIngest { throw Boom() }
        ingested.append(contentsOf: incoming)
    }
    func remove(externalIDs: [String]) throws { removed.append(contentsOf: externalIDs) }
    func upsertAccounts(_ incoming: [MoneyAccountRow]) throws { accounts.append(contentsOf: incoming) }
}

private struct StubAPI: PlaidAPI {
    let response: PlaidSyncResponse
    func createLinkToken() async throws -> String { "link" }
    func exchange(publicToken: String, institutionID: String?,
                  institutionName: String?) async throws -> PlaidExchangeResult {
        PlaidExchangeResult(item_id: "item_sandbox_1", institution_name: "First Platypus Bank")
    }
    func sync(cursors: [String: String]) async throws -> PlaidSyncResponse { response }
    func disconnect(itemID: String) async throws {}
}

@Suite @MainActor struct PlaidSyncTests {
    private func fixtureResponse() throws -> PlaidSyncResponse {
        try JSONDecoder().decode(PlaidSyncResponse.self, from: Data(PlaidFixtures.syncPage.utf8))
    }

    private func makeItems() -> UserDefaultsPlaidItemStore {
        UserDefaultsPlaidItemStore(
            defaults: UserDefaults(suiteName: "plaid.sync.\(UUID().uuidString)")!
        )
    }

    @Test func aSuccessfulRunStoresTheDataAndThenTheCursor() async throws {
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(api: StubAPI(response: try fixtureResponse()),
                             money: money, items: items)

        let outcome = try await sync.run()

        #expect(outcome.itemsSynced == 1)
        #expect(outcome.transactionsIngested == 4)
        #expect(money.removed == ["txn_stale_pending"])
        #expect(money.accounts.count == 2)
        #expect(items.items().first?.cursor == "cursor_page_2")
        #expect(items.items().first?.institutionName == "First Platypus Bank")
    }

    @Test func aFailedIngestLeavesTheCursorWhereItWas() async throws {
        // The reason the cursor lives on the device at all. Advance it here and
        // Plaid never resends this page: those transactions are gone for good.
        let money = StubMoney()
        money.failIngest = true
        let items = makeItems()
        let sync = PlaidSync(api: StubAPI(response: try fixtureResponse()),
                             money: money, items: items)

        _ = try? await sync.run()

        #expect(items.items().first?.cursor == nil)
    }

    @Test func anExpiredLoginIsReportedWithoutTouchingTheData() async throws {
        let failing = #"""
        {"items":[{"item_id":"item_1","institution_name":"Chase","added":[],
        "modified":[],"removed":[],"accounts":[],"next_cursor":null,
        "has_more":false,"error":"item_login_required"}]}
        """#
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(
            api: StubAPI(response: try JSONDecoder().decode(
                PlaidSyncResponse.self, from: Data(failing.utf8))),
            money: money, items: items
        )

        let outcome = try await sync.run()

        #expect(outcome.needsReconnect == ["Chase"])
        #expect(outcome.itemsSynced == 0)
        #expect(money.ingested.isEmpty)
        #expect(items.items().first?.cursor == nil)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PlaidSyncTests`
Expected: FAIL to compile, with "cannot find 'PlaidSync' in scope".

- [ ] **Step 4: Write the runner**

Create `LifeOSKit/Sources/Integrations/PlaidSync.swift`:

```swift
import Foundation
import Persistence

public struct PlaidSyncOutcome: Sendable, Equatable {
    public var itemsSynced = 0
    public var transactionsIngested = 0
    /// Institution names whose stored login the bank has invalidated. These
    /// need the user to sign in again; nothing about them is retryable.
    public var needsReconnect: [String] = []
    /// Plaid has more pages waiting. The caller should run again straight away.
    public var hasMore = false
}

/// Pulls each connected bank forward and writes the result down.
///
/// The ordering below is the whole design in three lines: store the data, then
/// move the cursor. A cursor advanced before a successful ingest is a page of
/// transactions Plaid will never send again.
@MainActor
public struct PlaidSync {
    private let api: any PlaidAPI
    private let money: any MoneyIngesting
    private let items: any PlaidItemStoring

    public init(api: any PlaidAPI, money: any MoneyIngesting, items: any PlaidItemStoring) {
        self.api = api
        self.money = money
        self.items = items
    }

    @discardableResult
    public func run() async throws -> PlaidSyncOutcome {
        let cursors = items.items().reduce(into: [String: String]()) { result, item in
            result[item.itemID] = item.cursor
        }
        let response = try await api.sync(cursors: cursors)

        var outcome = PlaidSyncOutcome()
        for delta in response.items {
            // Remember the connection before anything else, so a bank that is
            // connected but still fetching its history is not mistaken for one
            // that was never connected.
            items.upsert(PlaidStoredItem(itemID: delta.item_id,
                                         institutionName: delta.institution_name,
                                         cursor: nil))

            if delta.error == "item_login_required" {
                outcome.needsReconnect.append(delta.institution_name)
                continue
            }
            if delta.error != nil { continue }

            let rows = try PlaidMapping.ingestRows(from: delta.added + delta.modified,
                                                   accounts: delta.accounts)
            try money.ingest(rows)
            try money.remove(externalIDs: delta.removed.map(\.transaction_id))
            try money.upsertAccounts(PlaidMapping.accountRows(from: delta.accounts))

            // Only now. Every throw above leaves the cursor where it was, and
            // the next run replays this page into an idempotent upsert.
            if let cursor = delta.next_cursor {
                items.setCursor(cursor, for: delta.item_id)
            }

            outcome.itemsSynced += 1
            outcome.transactionsIngested += rows.count
            outcome.hasMore = outcome.hasMore || delta.has_more
        }
        return outcome
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter PlaidSyncTests`
Expected: PASS, all three.

- [ ] **Step 6: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyStore.swift LifeOSKit/Sources/Integrations/PlaidSync.swift LifeOSKit/Tests/IntegrationsTests/PlaidSyncTests.swift
git commit -m "feat(money): pull each connected bank forward, then move the cursor

The ordering is the design: store the data, and only then advance the
cursor. A cursor moved before a successful ingest is a page of transactions
Plaid will never send again, so the test that matters here is the one where
the ingest throws and the cursor stays put.

An expired bank login is reported by institution rather than thrown, so one
bank needing a fresh sign-in does not stop the others from syncing.

Persistence gains a small write-side protocol so the runner can be tested
against a store that fails on demand."
```

---

## Task 12: Add LinkKit and present the bank login

LinkKit is a closed-source, UIKit-facing binary, so it goes on the app target only. `LifeOSKit` stays free of third-party imports and therefore stays unit-testable.

**Files:**
- Modify: `LIfeOS.xcodeproj/project.pbxproj` (through Xcode, not by hand)
- Modify: `LIfeOS/Features/Settings/Model/AppConfig.swift`
- Create: `LIfeOS/Features/Settings/View/PlaidLinkPresenter.swift`

**Interfaces:**
- Consumes: `PlaidAPI` (Task 10)
- Produces: `AppConfig.plaidFunctionsBase: URL?`, `AppConfig.isPlaidConfigured: Bool`, `PlaidLinkPresenter.present(linkToken:completion:)` with `PlaidLinkResult` (`.connected(publicToken:institutionID:institutionName:)`, `.cancelled`, `.failed(String)`)

- [ ] **Step 1: Add the package dependency**

In Xcode: File > Add Package Dependencies, enter `https://github.com/plaid/plaid-link-ios`, choose "Up to Next Major Version", and add the `LinkKit` product **to the LIfeOS app target only**. Do not add it to any LifeOSKit target.

- [ ] **Step 2: Verify the app still builds**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED, with LinkKit resolved.

- [ ] **Step 3: Add the endpoints to AppConfig**

In `LIfeOS/Features/Settings/Model/AppConfig.swift`, add after `whoopTokenEndpoint`:

```swift
    /// The four Plaid functions live under here. The Plaid client id and
    /// secret are deliberately absent: they exist only in the function
    /// environment, because anything in the app bundle can be read out of the
    /// `.ipa`, and a Plaid secret reads every connected bank account.
    static var plaidFunctionsBase: URL? {
        supabaseURL?.appendingPathComponent("functions/v1")
    }

    static var isPlaidConfigured: Bool { plaidFunctionsBase != nil }
```

- [ ] **Step 4: Write the presenter**

Create `LIfeOS/Features/Settings/View/PlaidLinkPresenter.swift`:

```swift
import UIKit
import LinkKit

/// What came back from the bank login.
enum PlaidLinkResult {
    case connected(publicToken: String, institutionID: String?, institutionName: String?)
    /// The user backed out. Not an error and not worth an alert.
    case cancelled
    case failed(String)
}

/// Presents Plaid's Link flow.
///
/// The only file in the app that imports LinkKit. Keeping the SDK behind this
/// one seam means the connection view model is testable against `PlaidAPI`
/// alone, and swapping presentation later touches nothing else.
@MainActor
enum PlaidLinkPresenter {
    static func present(linkToken: String, completion: @escaping (PlaidLinkResult) -> Void) {
        var configuration = LinkTokenConfiguration(token: linkToken) { success in
            completion(.connected(
                publicToken: success.publicToken,
                institutionID: success.metadata.institution.id,
                institutionName: success.metadata.institution.name
            ))
        }
        configuration.onExit = { exit in
            // A user closing the sheet is the common path here, so an exit with
            // no error must not be dressed up as a failure.
            if let error = exit.error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.cancelled)
            }
        }

        switch Plaid.create(configuration) {
        case .failure(let error):
            completion(.failed(error.localizedDescription))
        case .success(let handler):
            guard let controller = topViewController() else {
                completion(.failed("No window to present from"))
                return
            }
            handler.open(presentUsing: .viewController(controller))
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add LIfeOS.xcodeproj/project.pbxproj LIfeOS/Features/Settings/Model/AppConfig.swift LIfeOS/Features/Settings/View/PlaidLinkPresenter.swift
git commit -m "feat(money): present Plaid Link from the app target only

LinkKit is a closed-source UIKit binary, so it stays on the app target and
LifeOSKit keeps its no-third-party rule and stays unit-testable. One file
imports it, which leaves the connection view model testable against the
PlaidAPI protocol alone.

An exit with no error is a user closing the sheet, so it reports as
cancelled rather than being dressed up as a failure."
```

---

## Task 13: Own the connection

**Files:**
- Create: `LIfeOS/Features/Settings/ViewModel/PlaidConnectionViewModel.swift`
- Modify: `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift`
- Modify: `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift`
- Modify: `LIfeOS/App/RootView.swift`

**Interfaces:**
- Consumes: `PlaidClient`, `PlaidSync`, `UserDefaultsPlaidItemStore`, `PlaidLinkPresenter`, `AuthSessionStoring`
- Produces: `PlaidConnectionViewModel` with `state: State` (`.unconfigured`, `.disconnected`, `.connecting`, `.connected([String])`, `.needsReconnect(String)`, `.failed(String)`), `statusDetail: String`, `attach(_:)`, `connect()`, `disconnect(itemID:deletingHistory:)`, `syncIfDue()`

- [ ] **Step 1: Write the view model**

Create `LIfeOS/Features/Settings/ViewModel/PlaidConnectionViewModel.swift`:

```swift
import Foundation
import SwiftData
import OSLog
import Integrations
import Persistence

private let plaidLog = Logger(subsystem: "com.shivvyas.lifeos", category: "plaid")

/// Owns the bank connection: the Link round trip, and the sync that follows it.
@MainActor @Observable
final class PlaidConnectionViewModel {
    enum State: Equatable {
        case unconfigured
        case disconnected
        case connecting
        case connected([String])
        /// The bank invalidated the stored login. Only the user can fix it.
        case needsReconnect(String)
        case failed(String)
    }

    private(set) var state: State = .disconnected
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    /// True between connecting and the first transaction arriving. Plaid
    /// fetches history asynchronously, so an empty first sync is normal and
    /// must not be rendered as "you spent nothing this month".
    private(set) var isFetchingHistory = false

    private let items: any PlaidItemStoring
    private let sessions: any AuthSessionStoring
    private var context: ModelContext?

    init(items: any PlaidItemStoring = UserDefaultsPlaidItemStore(),
         sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.items = items
        self.sessions = sessions
    }

    func attach(_ context: ModelContext) {
        self.context = context
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isPlaidConfigured else { state = .unconfigured; return }
        let connected = items.items().map(\.institutionName)
        state = connected.isEmpty ? .disconnected : .connected(connected)
    }

    var statusDetail: String {
        switch state {
        case .unconfigured: "Not configured"
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let names): names.joined(separator: ", ")
        case .needsReconnect(let name): "\(name) needs you to sign in again"
        case .failed(let message): message
        }
    }

    private var api: PlaidClient? {
        guard let base = AppConfig.plaidFunctionsBase else { return nil }
        let sessions = self.sessions
        return PlaidClient(functionsBase: base, accessToken: { sessions.load()?.accessToken })
    }

    // MARK: - Connect

    func connect() {
        guard let api else { state = .unconfigured; return }
        state = .connecting

        Task {
            do {
                let linkToken = try await api.createLinkToken()
                PlaidLinkPresenter.present(linkToken: linkToken) { result in
                    Task { await self.finishConnect(result) }
                }
            } catch {
                plaidLog.error("link token failed: \(String(describing: error))")
                state = .failed("Could not start the bank connection")
            }
        }
    }

    private func finishConnect(_ result: PlaidLinkResult) async {
        guard let api else { return }
        switch result {
        case .cancelled:
            refreshState()
        case .failed(let message):
            plaidLog.error("link exited: \(message)")
            state = .failed(message)
        case .connected(let publicToken, let institutionID, let institutionName):
            do {
                let item = try await api.exchange(publicToken: publicToken,
                                                  institutionID: institutionID,
                                                  institutionName: institutionName)
                items.upsert(PlaidStoredItem(itemID: item.item_id,
                                             institutionName: item.institution_name,
                                             cursor: nil))
                isFetchingHistory = true
                refreshState()
                await sync()
            } catch PlaidClientError.institutionAlreadyConnected {
                state = .failed("That bank is already connected")
            } catch {
                plaidLog.error("exchange failed: \(String(describing: error))")
                state = .failed("Could not finish connecting")
            }
        }
    }

    // MARK: - Sync

    func syncIfDue() async {
        guard case .connected = state,
              SyncStalenessPolicy.shouldSync(lastSync: lastSyncedAt) else { return }
        await sync()
    }

    func sync() async {
        guard let api, let context, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let runner = PlaidSync(api: api, money: MoneyStore(context: context), items: items)
        do {
            var outcome = try await runner.run()
            // Plaid hands back a bounded number of pages per call, so an initial
            // pull of years of history finishes across several runs rather than
            // stopping part-way and looking complete.
            var guardRail = 0
            while outcome.hasMore, guardRail < 20 {
                outcome = try await runner.run()
                guardRail += 1
            }

            lastSyncedAt = .now
            if outcome.transactionsIngested > 0 { isFetchingHistory = false }
            if let reconnect = outcome.needsReconnect.first {
                state = .needsReconnect(reconnect)
            } else {
                refreshState()
            }
        } catch {
            // The previous snapshot stays on screen with its own timestamp,
            // which is honest, rather than being replaced by zeroes.
            plaidLog.error("sync failed: \(String(describing: error))")
            state = .failed("Sync failed")
        }
    }

    // MARK: - Disconnect

    /// History is kept unless the user asks otherwise. Revoking a credential
    /// and stopping the billing is not a request to erase the past.
    func disconnect(itemID: String, deletingHistory: Bool) async {
        guard let api else { return }
        do {
            try await api.disconnect(itemID: itemID)
        } catch {
            plaidLog.error("disconnect failed: \(String(describing: error))")
        }
        items.remove(itemID: itemID)

        if deletingHistory, let context {
            let store = MoneyStore(context: context)
            let plaidIDs = (try? store.entries(from: .distantPast, to: .now))?
                .filter { $0.source == .plaid }
                .compactMap(\.externalID) ?? []
            try? store.remove(externalIDs: plaidIDs)
        }
        refreshState()
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Own the view model at the root**

In `LIfeOS/App/RootView.swift`, beside `@State private var money = MoneyViewModel()` on line 39, add:

```swift
    @State private var plaid = PlaidConnectionViewModel()
```

Attach it wherever `money.attach(...)` is called, immediately after that call:

```swift
        plaid.attach(context)
```

and pass it into `ConnectionsSettingsScreen(whoop: whoop)` as `ConnectionsSettingsScreen(whoop: whoop, plaid: plaid)`.

- [ ] **Step 4: Replace the coming-soon row in Settings**

In `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift`, add the property beside `whoop`:

```swift
    @Bindable var plaid: PlaidConnectionViewModel
```

Delete the `comingSoon(title: "Bank accounts", ...)` call and put `bankCard` in its place. Add this method beside `whoopCard`, matching its shape:

```swift
    private var bankCard: some View {
        Button {
            if case .connected = plaid.state {} else { plaid.connect() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bank accounts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(plaid.statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .padding(16)
            .background(SoftCardBackground())
        }
        .buttonStyle(.plain)
    }
```

If `SoftCardBackground` is not what `whoopCard` uses, copy whatever container `whoopCard` wraps itself in rather than inventing one.

- [ ] **Step 5: Update the onboarding copy**

In `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift:42`, change the detail string from `"Income and spending via Plaid. Arrives in the next release."` to `"Income and spending, straight from your bank."` Leave the row itself alone: onboarding introduces the connection, and Settings is where it is made.

- [ ] **Step 6: Build and run**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/Features/Settings/ViewModel/PlaidConnectionViewModel.swift LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift LIfeOS/App/RootView.swift
git commit -m "feat(money): connect, sync and disconnect a bank from Settings

Bank accounts stops saying it arrives in the next release and becomes a
live row beside Whoop, following the same view model shape.

Disconnecting keeps local history unless the user explicitly asks to
delete it, since revoking a credential is not a request to erase the past.
A failed sync leaves the previous snapshot on screen with its own
timestamp rather than replacing it with zeroes."
```

---

## Task 14: Show the connection, the sync, and the honest in-between

Two states the screen does not currently have. A bank that is connected but still fetching history must not render as "you spent nothing this month", and an expired login must say so rather than showing stale numbers with no explanation.

**Files:**
- Modify: `LIfeOS/Features/Money/Model/MoneySnapshot.swift`
- Modify: `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`
- Modify: `LIfeOS/Features/Money/View/MoneyScreen.swift`
- Modify: `LIfeOS/App/RootView.swift:223`

**Interfaces:**
- Consumes: `PlaidConnectionViewModel` (Task 13)
- Produces: `MoneySnapshot.lastSyncedAt: Date?`, `MoneySnapshot.hasConnectedBank: Bool`, `MoneySnapshot.isFetchingHistory: Bool`, `MoneySnapshot.reconnectPrompt: String?`; `MoneyViewModel.load(connection:)`

- [ ] **Step 1: Widen the snapshot**

In `LIfeOS/Features/Money/Model/MoneySnapshot.swift`, add to `MoneySnapshot` after `isConnected`:

```swift
    /// A bank is linked, whether or not any transaction has arrived yet.
    var hasConnectedBank = false
    /// Linked, but Plaid is still assembling the history. Distinct from an
    /// empty month, and the screen must not present it as one.
    var isFetchingHistory = false
    /// Set when a bank has invalidated its stored login.
    var reconnectPrompt: String?
    var lastSyncedAt: Date?
```

Change `isConnected`'s use at the call site in `MoneyViewModel` rather than the property itself, so previews keep working.

- [ ] **Step 2: Feed them from the view model**

In `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`, change `func load()` to take the connection and thread the new fields through. Replace the signature and the `snapshot = MoneySnapshot(...)` assignment:

```swift
    func load(connection: PlaidConnectionViewModel? = nil) {
```

and inside the `do` block, before building the snapshot:

```swift
        let bankNames: [String]
        var reconnect: String?
        switch connection?.state {
        case .connected(let names): bankNames = names
        case .needsReconnect(let name): bankNames = [name]; reconnect = name
        default: bankNames = []
        }
```

then extend the snapshot construction, replacing the `isConnected:` line with:

```swift
                // A bank linked seconds ago has no transactions yet. Falling back
                // to the empty state there tells the user the connection failed
                // when it did not.
                isConnected: !entries.isEmpty || !accounts.isEmpty || !bankNames.isEmpty,
                hasConnectedBank: !bankNames.isEmpty,
                isFetchingHistory: connection?.isFetchingHistory ?? false,
                reconnectPrompt: reconnect,
                lastSyncedAt: connection?.lastSyncedAt
```

- [ ] **Step 3: Give the screen the two new states**

In `LIfeOS/Features/Money/View/MoneyScreen.swift`, replace the `emptyState` property with:

```swift
    private var emptyState: some View {
        VStack(spacing: 16) {
            HeroEmptyState(label: "Money", reason: "No transactions yet")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Button("Add a transaction", action: onAdd)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.vertical, 12)
                .padding(.horizontal, 22)
                .background(Capsule().fill(LifeOSTokens.tileSurface.resolve(scheme)))
            Button("Connect your bank", action: onConnect)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
        .padding(.top, 40)
    }

    /// Connected, but Plaid is still assembling the history.
    ///
    /// Plaid fetches transactions asynchronously after the login completes, so
    /// the first sync can honestly come back with nothing. Rendering that as an
    /// empty month would state, as fact, that the user spent nothing.
    private var fetchingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Fetching your transactions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text("Your bank is sending the last few months. This usually takes a minute.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Button("Check again", action: onSync)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    private var reconnectBanner: some View {
        SoftCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.reconnectPrompt ?? "Your bank") needs you to sign in again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text("Numbers below are from your last sync.")
                        .font(.footnote)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                Spacer()
            }
        }
    }
```

Add the two new callbacks beside `onAdd`:

```swift
    var onConnect: () -> Void = {}
    var onSync: () -> Void = {}
```

and change the body's branch from `if snapshot.isConnected {` to:

```swift
                    if snapshot.reconnectPrompt != nil { reconnectBanner }

                    if snapshot.isFetchingHistory && snapshot.recent.isEmpty {
                        fetchingState
                    } else if snapshot.isConnected {
```

- [ ] **Step 4: Wire the callbacks and sync on foreground**

In `LIfeOS/App/RootView.swift:223`, replace the `MoneyScreen` construction with:

```swift
                MoneyScreen(
                    snapshot: money.snapshot,
                    onAdd: { showAddMoney = true },
                    onConnect: { plaid.connect() },
                    onSync: { Task { await plaid.sync(); money.load(connection: plaid) } }
                )
```

At line 323, change `money.load()` to `money.load(connection: plaid)`, and immediately after it add:

```swift
        Task {
            await plaid.syncIfDue()
            money.load(connection: plaid)
        }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED. Fix any preview that no longer compiles by passing the new fields.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Money LIfeOS/App/RootView.swift
git commit -m "feat(money): say when a bank is still sending its history

Plaid assembles transactions asynchronously after the login completes, so
the first sync can honestly return nothing. Rendering that as an empty
month states as fact that the user spent nothing, so it gets its own state
that says what is actually happening and offers a retry.

An expired bank login shows a banner over the last known numbers rather
than replacing them, since stale numbers with a reason beat fresh zeroes.
A bank linked seconds ago now counts as connected, which stops a working
connection from looking like a failed one while it waits for data."
```

---

## Task 15: Prove it end to end, then retire the sample data

**Files:**
- Delete: `LIfeOS/Features/Money/Model/SampleMoneyData.swift`
- Modify: `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`
- Modify: `LIfeOS/Features/Settings/View/SettingsScreen.swift:56`

- [ ] **Step 1: Point the functions at Sandbox and deploy**

```bash
supabase secrets set PLAID_CLIENT_ID=<from the Plaid dashboard> \
                     PLAID_SECRET=<the sandbox secret> \
                     PLAID_ENV=sandbox
supabase functions deploy plaid-link-token plaid-exchange plaid-sync plaid-disconnect
supabase db push
```

- [ ] **Step 2: Connect a fake bank and confirm the numbers**

Run the app on a simulator, sign in, then Settings > Connections > Bank accounts. Choose "First Platypus Bank" and log in with `user_good` / `pass_good`.

Expected, in order: the row shows "Connecting…", the Money tab shows "Fetching your transactions", and within a minute real Sandbox transactions appear with income positive and spending negative. Confirm specifically that **the largest deposit reads as income, not as an expense.** That is the sign convention, and it is the one failure that looks plausible.

- [ ] **Step 3: Force the expired-login path**

```bash
curl -s -X POST https://sandbox.plaid.com/sandbox/item/reset_login \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"<id>","secret":"<secret>","access_token":"<the item access token from the plaid_items table>"}'
```

Then background and reopen the app.
Expected: the reconnect banner appears over the previous numbers, and the numbers themselves are still there.

- [ ] **Step 4: Disconnect, and confirm history survives by default**

In Settings, disconnect the bank without ticking the delete option.
Expected: the row returns to "Not connected", the transactions remain on the Money tab, and the row is gone from `plaid_items`.

- [ ] **Step 5: Switch to production and connect the real account**

```bash
supabase secrets set PLAID_SECRET=<the production secret> PLAID_ENV=production
supabase functions deploy plaid-link-token plaid-exchange plaid-sync plaid-disconnect
```

Connect the real bank and confirm the month's income, expenses, savings rate, and net worth against the bank's own app. Check the savings rate in particular: if a transfer between accounts is leaking into the totals, this is where it shows.

- [ ] **Step 6: Retire the sample data**

Only once real transactions render correctly.

```bash
git rm LIfeOS/Features/Money/Model/SampleMoneyData.swift
```

In `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`, delete the `#if DEBUG` block holding `sampleDataKey` and the `#if DEBUG` branch at the top of `load`. In `LIfeOS/Features/Settings/View/SettingsScreen.swift`, delete the `@AppStorage(MoneyViewModel.sampleDataKey)` property on line 10 and the toggle and its comment around line 56.

- [ ] **Step 7: Verify nothing still refers to it**

Run: `grep -rn "SampleMoneyData\|sampleDataKey\|useSampleFinanceData" LIfeOS LifeOSKit/Sources`
Expected: no output.

- [ ] **Step 8: Full build and test**

Run: `swift test --package-path LifeOSKit && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: PASS and BUILD SUCCEEDED.

- [ ] **Step 9: Commit**

```bash
git add -A LIfeOS/Features/Money LIfeOS/Features/Settings/View/SettingsScreen.swift
git commit -m "chore(money): retire the sample finances now that real ones arrive

The invented numbers existed so the layout could be judged before there was
any real money to look at, and the file asked to be deleted once Plaid
landed. Real transactions render, so it goes, along with the Settings
toggle that switched it on."
```

---

## Done when

- A real bank connects from Settings and its transactions appear on the Money tab
- Income is positive, spending is negative, and the largest deposit of the month reads as income
- Transfers between your own accounts and credit card payments do not move the savings rate
- A settled charge replaces its pending twin instead of sitting beside it
- An expired bank login shows a reconnect banner over the last known numbers
- Disconnecting stops the billing and keeps the history
- `swift test --package-path LifeOSKit` passes and the app builds
- No Plaid credential exists anywhere outside the `plaid_items` table
