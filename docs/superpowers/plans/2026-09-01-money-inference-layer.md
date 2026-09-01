# Money Inference Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store five Plaid fields the device already receives and currently discards, so every later inference slice can be built against complete history.

**Architecture:** Purely additive. `plaid-sync` is untouched, because it already passes Plaid's JSON through whole. The change is `PlaidWireFormat` decoding more keys, two row structs carrying them, two `@Model` types gaining optional properties, and `MoneyStore` writing them on upsert. No UI reads any of it when this is done.

**Tech Stack:** Swift 6, SwiftData, swift-testing (`@Test` / `#expect` / `#require`), Xcode 26, iOS 26 deployment target.

**Spec:** `docs/superpowers/specs/2026-09-01-money-inference-layer-design.md`

## Global Constraints

- **Every new stored property is `Optional` and defaults to `nil`.** A missing credit limit is not a limit of zero, and a missing available balance is not an empty account. Spec Sections 7.1 and 7.2.
- **No non-optional property may be added to `MoneyEntry` or `MoneyAccount`.** `LifeOSContainer.swift:5` builds a plain `Schema([...])` with no `VersionedSchema` and no migration plan, so the app relies on SwiftData's automatic lightweight migration. Adding optionals is what that mechanism supports; adding a required property is what breaks it.
- **`netWorthContribution` keys off `type` and must keep doing so.** Utilization will key off `subtype`. Neither rule may be rewritten in terms of the other. Spec Section 7.3.
- **Existing assertions must not move.** The fixture tests for sign, removals, and transfer exclusion are the guard on this slice being additive. If a number in them changes, the change is wrong.
- **No new Plaid product, no new Edge Function call, no server change.** Spec Section 3.
- **Commit style:** `type(scope): imperative summary`, no em dashes, no attribution trailer. Branch is `feat/money-inference-layer`, already created.

---

### Task 1: Decode the new fields off the wire

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/PlaidWireFormat.swift`
- Modify: `LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/PlaidWireFormatTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `PlaidTransaction.merchant_entity_id: String?`; `PlaidAccount.mask: String?`; `PlaidAccount.subtype: String?`; `PlaidBalances.available: Double?`; `PlaidBalances.limit: Double?`. Task 2 reads the first, Task 3 reads the other four.

**Why the fixture changes first:** `PlaidFixtures.syncPage` is currently trimmed to the fields the decoder already reads, which is exactly why it could not answer "what else does Plaid send". It gains the new keys on *some* rows and not others, because mixed presence is the real shape and the nil handling is the part worth testing.

- [ ] **Step 1: Extend the fixture with mixed presence**

In `LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift`, make exactly these four edits inside `syncPage`. Add no other keys.

Add `merchant_entity_id` to the `txn_coffee` object only, after its `merchant_name` line:

```json
              "merchant_name": "Blue Bottle Coffee",
              "merchant_entity_id": "mch_bluebottle",
```

`txn_payroll`, `txn_card_payment` and `txn_uncategorised` get no `merchant_entity_id`. That absence is the test for Spec Section 7.4.

Replace the whole `acc_checking` object with:

```json
            {
              "account_id": "acc_checking",
              "name": "Plaid Checking",
              "type": "depository",
              "subtype": "checking",
              "mask": "0000",
              "balances": {
                "current": 2450.75,
                "available": 2100.50,
                "iso_currency_code": "USD"
              }
            },
```

Replace the whole `acc_card` object with:

```json
            {
              "account_id": "acc_card",
              "name": "Plaid Credit Card",
              "type": "credit",
              "subtype": "credit card",
              "mask": "4127",
              "balances": {
                "current": 610.25,
                "limit": 2000.00,
                "iso_currency_code": "USD"
              }
            }
```

Note what is deliberately absent: `acc_checking` has no `limit`, and `acc_card` has no `available`. Both omissions are load-bearing. A checking account has no credit limit and a decoder that invents one is the bug in Spec Section 7.1.

Finally, update the doc comment at the top of the file. It currently claims the fixture is a real Sandbox page; it is now a real page plus fields chosen to exercise absence. Replace the sentence "A real Sandbox `/transactions/sync` page, wrapped in the per-Item envelope `plaid-sync` returns." with:

```
/// A real Sandbox `/transactions/sync` page, wrapped in the per-Item envelope
/// `plaid-sync` returns, with optional fields present on some rows and absent
/// on others on purpose: `txn_coffee` carries a merchant entity and the other
/// three do not, `acc_card` reports a credit limit and `acc_checking` does not,
/// and `acc_checking` reports an available balance while `acc_card` does not.
/// Uniform presence would let a decoder that mishandles absence pass.
```

- [ ] **Step 2: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/PlaidWireFormatTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite @MainActor struct PlaidWireFormatTests {
    private func delta() throws -> PlaidItemDelta {
        let response = try JSONDecoder().decode(
            PlaidSyncResponse.self, from: Data(PlaidFixtures.syncPage.utf8)
        )
        return try #require(response.items.first)
    }

    @Test func aMerchantEntityIsDecodedWhenPlaidResolvedOne() throws {
        let coffee = try #require(delta().added.first { $0.transaction_id == "txn_coffee" })
        #expect(coffee.merchant_entity_id == "mch_bluebottle")
    }

    @Test func anUnresolvedDescriptorHasNoMerchantEntity() throws {
        // Plaid does not resolve every descriptor. Nil means "not known", and
        // grouping every nil together would invent one fictitious merchant out
        // of every unresolved row.
        let payroll = try #require(delta().added.first { $0.transaction_id == "txn_payroll" })
        #expect(payroll.merchant_entity_id == nil)
    }

    @Test func anAccountCarriesItsMaskAndSubtype() throws {
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })
        #expect(card.mask == "4127")
        #expect(card.subtype == "credit card")
        // type stays coarse and unchanged: netWorthContribution reads it.
        #expect(card.type == "credit")
    }

    @Test func aCreditLimitIsDecodedAndACheckingAccountHasNone() throws {
        // The distinction this whole slice exists for. A checking account with
        // a limit of 0 would render as fully utilised, which is arithmetically
        // true and factually meaningless.
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })
        let checking = try #require(delta().accounts.first { $0.account_id == "acc_checking" })

        #expect(card.balances.limit == 2_000)
        #expect(checking.balances.limit == nil)
    }

    @Test func anAvailableBalanceIsDecodedAndItsAbsenceIsNotZero() throws {
        let checking = try #require(delta().accounts.first { $0.account_id == "acc_checking" })
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })

        #expect(checking.balances.available == 2_100.50)
        #expect(card.balances.available == nil)
    }
}
```

- [ ] **Step 3: Run the test and verify it fails**

```bash
cd LifeOSKit && swift test --filter PlaidWireFormatTests
```

Expected: compilation failure, `value of type 'PlaidTransaction' has no member 'merchant_entity_id'` and the same for `mask`, `subtype`, `available` and `limit`.

- [ ] **Step 4: Add the properties**

In `LifeOSKit/Sources/Integrations/PlaidWireFormat.swift`, add to `PlaidTransaction`, immediately after the `merchant_name` property:

```swift
    /// Plaid's stable identifier for the merchant behind this descriptor.
    ///
    /// Nil when Plaid could not resolve one, which is common enough that no
    /// caller may assume presence. It is the right grouping key for recurring
    /// detection because it survives a descriptor changing spelling, which a
    /// merchant name does not: `NETFLIX.COM` and `Netflix` are one entity here
    /// and two strings anywhere else.
    public let merchant_entity_id: String?
```

Add the parameter to the memberwise `init`, **with a `nil` default**, so the two direct constructions in `PlaidMappingTests.swift:84` and `:100` keep compiling untouched. Put it after `merchant_name:` in both the signature and the assignment list:

```swift
    public init(transaction_id: String, account_id: String, amount: Double,
                iso_currency_code: String?, date: String, name: String,
                merchant_name: String?, merchant_entity_id: String? = nil,
                pending: Bool,
                personal_finance_category: PlaidPFC?) {
```

and in the body, after `self.merchant_name = merchant_name`:

```swift
        self.merchant_entity_id = merchant_entity_id
```

Add to `PlaidAccount`, after `type`:

```swift
    /// The last two to four characters of the account number. What tells two
    /// cards apart on screen.
    public let mask: String?
    /// Plaid's fine classification: checking, savings, credit card, mortgage.
    ///
    /// Kept alongside `type` rather than replacing it. `type` answers "is this
    /// money owed", which is what net worth needs; `subtype` answers "is this a
    /// credit card", which is what utilisation needs, and a mortgage is a loan
    /// with a balance and no meaningful utilisation.
    public let subtype: String?
```

Add to `PlaidBalances`, after `current`:

```swift
    /// What can actually be withdrawn, as opposed to what the account holds.
    /// Nil where the institution does not distinguish the two.
    public let available: Double?
    /// The credit limit on a card, or the overdraft limit on a depository
    /// account. Nil at institutions that do not report it, and nil is not zero:
    /// utilisation against a limit of zero is 100% by arithmetic and unknowable
    /// in fact.
    public let limit: Double?
```

No `CodingKeys` are needed anywhere. Swift's synthesised `Decodable` uses `decodeIfPresent` for `Optional` properties, so a missing key decodes as nil rather than throwing, which is exactly the behaviour the fixture's deliberate omissions test.

- [ ] **Step 5: Run the tests and verify they pass**

```bash
cd LifeOSKit && swift test --filter Plaid
```

Expected: PASS, including every pre-existing `PlaidMappingTests`, `PlaidSyncTests` and `PlaidClientTests` case unchanged. If any of those moved, the change was not additive and is wrong.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/PlaidWireFormat.swift \
        LifeOSKit/Tests/IntegrationsTests/PlaidWireFormatTests.swift \
        LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift
git commit -m "feat(money): decode the merchant entity, mask, subtype and both balances

All five already arrive on every sync and were being dropped by the
decoder, so this costs no Plaid call. The fixture gains them on some
rows and not others because absence is the case that matters: a null
credit limit is not a limit of zero."
```

---

### Task 2: Carry the merchant entity through to a stored transaction

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift:12-40` (`MoneyIngestRow`), and `ingest` at `:139`
- Modify: `LifeOSKit/Sources/Persistence/MoneyEntry.swift` (`MoneyEntry`)
- Modify: `LifeOSKit/Sources/Integrations/PlaidMapping.swift` (`ingestRows`)
- Test: `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`, `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`

**Interfaces:**
- Consumes: `PlaidTransaction.merchant_entity_id` from Task 1.
- Produces: `MoneyIngestRow.merchantID: String?`, `MoneyEntry.merchantID: String?`. Nothing in this slice reads them; the recurring-detection slice does.

- [ ] **Step 1: Write the failing tests**

Append to `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`, inside the suite:

```swift
    @Test func aResolvedMerchantCarriesItsEntityID() throws {
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let coffee = try #require(rows.first { $0.externalID == "txn_coffee" })
        #expect(coffee.merchantID == "mch_bluebottle")
    }

    @Test func anUnresolvedMerchantCarriesNoEntityID() throws {
        // Not an empty string. Recurring detection falls back per row to the
        // merchant name; a shared empty key would merge every unresolved
        // descriptor into one merchant that does not exist.
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let payroll = try #require(rows.first { $0.externalID == "txn_payroll" })
        #expect(payroll.merchantID == nil)
    }
```

Append to `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`, inside the suite:

```swift
    @Test func ingestStoresTheMerchantEntityAndUpdatesItOnResync() throws {
        // Plaid backfills a merchant entity onto a transaction it had not
        // resolved when it first sent it, so a re-sync must move the value
        // rather than keep the first answer.
        let store = try makeStore()
        let row = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: nil, pending: false,
            accountID: "acc_card", accountName: "Card", currencyCode: "USD"
        )
        try store.ingest([row])

        let resolved = MoneyIngestRow(
            externalID: "txn_1", date: day, amount: -6.75, merchant: "Blue Bottle Coffee",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE",
            merchantID: "mch_bluebottle", pending: false,
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
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
cd LifeOSKit && swift test --filter "MoneyTests|PlaidMappingTests"
```

Expected: compilation failure, `extra argument 'merchantID' in call` and `value of type 'MoneyEntry' has no member 'merchantID'`.

- [ ] **Step 3: Add the property to the model**

In `LifeOSKit/Sources/Persistence/MoneyEntry.swift`, add to `MoneyEntry` after `categoryCode`:

```swift
    /// Plaid's `merchant_entity_id`: one stable id for a merchant across every
    /// spelling of its descriptor. Nil for a manual entry, and nil when Plaid
    /// could not resolve one.
    ///
    /// Optional on purpose, and a lightweight SwiftData migration because of
    /// it: rows written before this existed read back nil rather than needing
    /// a migration step.
    public var merchantID: String?
```

Add the parameter to `init`, after `categoryCode:`, defaulted so every existing call site keeps compiling:

```swift
        merchantID: String? = nil,
```

and in the body, after `self.categoryCode = categoryCode`:

```swift
        self.merchantID = merchantID
```

- [ ] **Step 4: Add the field to the row type and the store**

In `LifeOSKit/Sources/Persistence/MoneyStore.swift`, add to `MoneyIngestRow` after `categoryCode`:

```swift
    public let merchantID: String?
```

Add `merchantID: String?,` to its `init` signature after `categoryCode: String?,` and `self.merchantID = merchantID` to the body. **No default value here.** `MoneyIngestRow` is constructed in exactly one place in the app, `PlaidMapping.ingestRows`, which Step 5 updates; a default would let a future caller silently forget the field.

In `ingest`, add one line to the property-copy block, after `entry.categoryCode = row.categoryCode`:

```swift
            entry.merchantID = row.merchantID
```

It belongs in the copy block rather than the constructor because the block is what runs for a row that already exists, and Plaid backfills a merchant entity onto a transaction it sent unresolved.

- [ ] **Step 5: Map it**

In `LifeOSKit/Sources/Integrations/PlaidMapping.swift`, inside `ingestRows`, add to the `MoneyIngestRow` construction after the `categoryCode:` line:

```swift
                merchantID: transaction.merchant_entity_id,
```

- [ ] **Step 6: Run the tests and verify they pass**

```bash
cd LifeOSKit && swift test
```

Expected: PASS, whole suite. Not just the filtered subset: this task touches `MoneyEntry`'s initialiser, which the sample data and several other suites construct.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyEntry.swift \
        LifeOSKit/Sources/Persistence/MoneyStore.swift \
        LifeOSKit/Sources/Integrations/PlaidMapping.swift \
        LifeOSKit/Tests/PersistenceTests/MoneyTests.swift \
        LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift
git commit -m "feat(money): store the merchant entity behind each transaction

Recurring detection currently groups on the display name, which splits
NETFLIX.COM from Netflix and merges two different branches of one shop.
This stores the key that fixes it. The value is written in the update
block, not the constructor, because Plaid backfills an entity onto a
transaction it first sent unresolved."
```

---

### Task 3: Carry mask, subtype and both balances through to a stored account

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift:42-58` (`MoneyAccountRow`), and `upsertAccounts` at `:193`
- Modify: `LifeOSKit/Sources/Persistence/MoneyEntry.swift` (`MoneyAccount`)
- Modify: `LifeOSKit/Sources/Integrations/PlaidMapping.swift` (`accountRows`)
- Test: `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`, `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`

**Interfaces:**
- Consumes: `PlaidAccount.mask`, `.subtype`, `PlaidBalances.available`, `.limit` from Task 1.
- Produces: `MoneyAccountRow.mask/subtype/availableBalance/creditLimit`, all `String?`/`Double?`, and the same four on `MoneyAccount`. The Accounts UI slice reads them.

- [ ] **Step 1: Write the failing tests**

Append to `LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift`:

```swift
    @Test func aCardCarriesItsLimitAndACheckingAccountCarriesNone() throws {
        // The pair that matters. currentBalance already falls back to 0 for a
        // null, which is right for a balance and catastrophic for a limit:
        // 610.25 against a limit of 0 renders as fully utilised.
        let rows = PlaidMapping.accountRows(from: delta().accounts)
        let card = try #require(rows.first { $0.externalID == "acc_card" })
        let checking = try #require(rows.first { $0.externalID == "acc_checking" })

        #expect(card.creditLimit == 2_000)
        #expect(card.mask == "4127")
        #expect(card.subtype == "credit card")
        #expect(checking.creditLimit == nil)
    }

    @Test func anAvailableBalanceIsCarriedAndItsAbsenceStaysAbsent() throws {
        let rows = PlaidMapping.accountRows(from: delta().accounts)
        let checking = try #require(rows.first { $0.externalID == "acc_checking" })
        let card = try #require(rows.first { $0.externalID == "acc_card" })

        #expect(checking.availableBalance == 2_100.50)
        #expect(card.availableBalance == nil)
        // The existing fallback is unchanged: a null current balance is still 0.
        #expect(checking.currentBalance == 2_450.75)
    }
```

Append to `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
cd LifeOSKit && swift test --filter "MoneyTests|PlaidMappingTests"
```

Expected: compilation failure, `extra argument 'creditLimit' in call`.

- [ ] **Step 3: Add the properties to the model**

In `LifeOSKit/Sources/Persistence/MoneyEntry.swift`, add to `MoneyAccount` after `type`:

```swift
    /// Plaid's fine classification: checking, savings, credit card, mortgage.
    ///
    /// Kept beside `type` rather than replacing it because the two answer
    /// different questions. `netWorthContribution` asks "is this money owed"
    /// and reads `type`; utilisation asks "is this a credit card" and reads
    /// this. A mortgage is a loan with a balance and no meaningful utilisation,
    /// so neither rule can be written in terms of the other.
    public var subtype: String?
    /// The last two to four characters of the account number, for telling two
    /// cards apart on screen.
    public var mask: String?
    /// What can actually be spent, as opposed to what the account holds.
    ///
    /// Nil where the institution does not report it, and nil is not zero: an
    /// account summed as holding nothing understates available cash, and that
    /// is the direction that makes someone spend money they do not have.
    public var availableBalance: Double?
    /// The card's credit limit. Nil where the institution does not report it.
    ///
    /// Never defaulted to zero. Utilisation against a limit of zero computes to
    /// 100% and means nothing, and a screen that states it is confidently wrong
    /// rather than visibly broken.
    public var creditLimit: Double?
```

Add the four to `init` after `type:`, all defaulted, so the existing call sites in `MoneyStore` and any sample data keep compiling:

```swift
        subtype: String? = nil,
        mask: String? = nil,
        availableBalance: Double? = nil,
        creditLimit: Double? = nil,
```

and assign each in the body.

Leave `netWorthContribution` exactly as it is. It reads `type` and that is correct.

- [ ] **Step 4: Add the fields to the row type and the store**

In `LifeOSKit/Sources/Persistence/MoneyStore.swift`, add to `MoneyAccountRow` after `type`:

```swift
    /// checking, savings, credit card, mortgage. See MoneyAccount.subtype.
    public let subtype: String?
    public let mask: String?
    public let availableBalance: Double?
    /// Nil where the institution does not report one. Never zero. See
    /// MoneyAccount.creditLimit.
    public let creditLimit: Double?
```

Add them to its `init` with **no defaults**, for the reason given in Task 2 Step 4, and assign each. The full signature, in the order the tests above call it:

```swift
    public init(externalID: String, name: String, type: String,
                subtype: String?, mask: String?,
                currentBalance: Double, availableBalance: Double?,
                creditLimit: Double?, currencyCode: String) {
```

Note that `currentBalance` stays where it is, between `mask` and `availableBalance`, so the two balances read in the order a person would say them.

In `upsertAccounts`, add to the property-copy block after `account.type = row.type`:

```swift
            account.subtype = row.subtype
            account.mask = row.mask
            account.availableBalance = row.availableBalance
            account.creditLimit = row.creditLimit
```

- [ ] **Step 5: Map them**

In `LifeOSKit/Sources/Integrations/PlaidMapping.swift`, rewrite `accountRows` to:

```swift
    public static func accountRows(from accounts: [PlaidAccount]) -> [MoneyAccountRow] {
        accounts.map { account in
            MoneyAccountRow(
                externalID: account.account_id,
                name: account.name,
                type: account.type,
                subtype: account.subtype,
                mask: account.mask,
                // A null balance means Plaid could not read it this time. Zero is
                // the honest placeholder; the next sync corrects it.
                currentBalance: account.balances.current ?? 0,
                // Deliberately NOT given the same fallback. A zero balance is a
                // wrong number that the next sync fixes; a zero limit is a wrong
                // number that renders as 100% utilised and looks like a fact.
                availableBalance: account.balances.available,
                creditLimit: account.balances.limit,
                currencyCode: account.balances.iso_currency_code ?? "USD"
            )
        }
    }
```

- [ ] **Step 6: Run the whole suite and verify it passes**

```bash
cd LifeOSKit && swift test
```

Expected: PASS, all suites.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyEntry.swift \
        LifeOSKit/Sources/Persistence/MoneyStore.swift \
        LifeOSKit/Sources/Integrations/PlaidMapping.swift \
        LifeOSKit/Tests/PersistenceTests/MoneyTests.swift \
        LifeOSKit/Tests/IntegrationsTests/PlaidMappingTests.swift
git commit -m "feat(money): store account masks, subtypes and both balances

Utilisation cannot be computed at all without a limit, and safe-to-spend
needs available rather than current. Neither gets the zero fallback the
current balance has: a zero balance is corrected by the next sync, while
a zero limit renders as fully utilised and reads as a fact."
```

---

### Task 4: Prove the migration is lightweight against a real store

**Files:**
- Modify: none. This task adds no code.

**Interfaces:**
- Consumes: everything from Tasks 1 to 3.
- Produces: nothing.

**Why this is a task and not an assertion:** every test above runs against an in-memory container built from the current schema, so none of them proves that a database written by build 17 opens under this one. `LifeOSContainer.swift:5` uses a plain `Schema` with no `VersionedSchema` and no migration plan, which means SwiftData attempts automatic lightweight migration and throws at container creation if it cannot. Adding optional properties is inside what that supports, but "inside what it supports" is a claim, and the app failing to launch is what it costs if the claim is wrong. A unit test cannot check this; an install over an existing container can.

- [ ] **Step 1: Install the current main build and give it data**

```bash
xcrun simctl boot 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 || true
open -a Simulator
git stash --include-untracked
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' \
  -derivedDataPath build/dd build
xcrun simctl install 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 \
  build/dd/Build/Products/Debug-iphonesimulator/LIfeOS.app
xcrun simctl launch 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 com.shivvyas.lifeos
```

In the simulator, add at least one manual money entry so the store is not empty. An empty database migrates trivially and proves nothing.

- [ ] **Step 2: Build this branch over it without uninstalling**

```bash
git stash pop
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' \
  -derivedDataPath build/dd build
xcrun simctl install 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 \
  build/dd/Build/Products/Debug-iphonesimulator/LIfeOS.app
xcrun simctl launch 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 com.shivvyas.lifeos
```

**Do not uninstall between the two.** Uninstalling deletes the container, which is the exact thing under test.

- [ ] **Step 3: Confirm the app launched with its data intact**

```bash
xcrun simctl io 780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4 screenshot /tmp/migration-check.png
```

Look at the screenshot. Pass is the app on its normal screen with the entry from Step 1 still present. Fail is a crash on launch or an empty Money tab, either of which means the migration was not lightweight and this slice needs a `VersionedSchema` and an explicit migration plan before it can ship.

Note on driving the simulator if a tap is needed: `idb` is not installed and `simctl` cannot tap. Use `cliclick`, and set the Simulator frontmost immediately before every click, or clicks are silently swallowed.

- [ ] **Step 4: Run the full suite one last time and push**

```bash
cd LifeOSKit && swift test
cd .. && git push origin feat/money-inference-layer
```

---

## Definition of done

- `swift test` passes in full, with every pre-existing assertion on sign, removals and transfer exclusion unmoved.
- An app installed over a database from build 17 launches with its data intact.
- No UI reads any of the five new properties. If a screen changed, this slice did too much.
- A bank connected after this ships carries `merchantID` on its transactions and `mask`, `subtype`, `availableBalance` and `creditLimit` on its accounts, for the full history Plaid returns.
