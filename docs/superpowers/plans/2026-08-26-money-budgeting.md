# Money Budgeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monthly spending budgets: user-defined buckets that claim raw categories, a limit per bucket, an unclaimed-spend view, and budget adherence as the Money sector's primary evidence.

**Architecture:** One new `@Model` (`SpendBucket`) in `Persistence` with CRUD on `MoneyStore` that enforces a single-holder rule per claim key. All arithmetic is pure functions in the `Sectors` package (`BudgetPeriod`), fed by both the Money screen and the monthly close so the two cannot drift. `MoneyScorer` gains an optional `BudgetReport` and reweights when it is present.

**Tech Stack:** Swift 6, SwiftData, SwiftUI, Swift Testing (`swift test --package-path LifeOSKit`).

**Spec:** `docs/superpowers/specs/2026-08-26-money-budgeting-design.md`

## Global Constraints

- Work happens in a dedicated worktree (e.g. `.claude/worktrees/money-budgeting`) on branch `feat/money-budgeting`. Never commit to `main`.
- Conventional commit messages (`type(scope): imperative summary`) with a short body. **No em dashes in commit messages. No Claude or AI attribution of any kind, including `Co-Authored-By` trailers.**
- Sign convention: **positive is money in, negative is money out.** Refunds arrive positive and must net within their bucket, never inflate income or unclaimed spend.
- A claim key may be held by at most one bucket, enforced on write in `MoneyStore`.
- An entry's claim key is `categoryCode ?? category`. Display labels never key arithmetic.
- Unclaimed spend is always shown and never scored (weight 0).
- No buckets means the Money score is exactly today's: no adherence row, saving rate stays weight 3, nil-not-zero everywhere.
- `LifeOSKit` takes no third-party dependency. New app files need no pbxproj edits (file-system-synchronized groups).
- Swift tests: `swift test --package-path LifeOSKit`. App build check: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`.
- iOS deployment target is 26.0; the package targets `.iOS("26.0")`.

## Where this plan refines the spec

**`BudgetReport.Row` carries the bucket's `id`.** The screen needs an `Identifiable` row and the editor needs to find the bucket a row came from; threading the `UUID` through the report is cheaper than re-matching on name.

**The claimable-category list looks back three months**, not one. A category you spent in last month but not yet this month is exactly the one you are budgeting for; a one-month window would hide it from the editor.

---

## Task 1: `SpendBucket` model and store CRUD with the single-holder rule

**Files:**
- Create: `LifeOSKit/Sources/Persistence/SpendBucket.swift`
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift` (append bucket methods)
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift` (register the model)
- Test: `LifeOSKit/Tests/PersistenceTests/SpendBucketTests.swift`

**Interfaces:**
- Consumes: `MoneyStore`, `LifeOSContainer`, `MoneyEntry` (all existing).
- Produces: `SpendBucket` (`@Model`: `id: UUID`, `name: String`, `monthlyLimit: Double`, `claimedRaw: [String]`, `sortOrder: Int`), `MoneyEntry.claimKey: String?`, `SpendBucketError.limitNotPositive`, and on `MoneyStore`: `buckets() throws -> [SpendBucket]`, `addBucket(name:monthlyLimit:) throws -> SpendBucket`, `updateBucket(_:name:monthlyLimit:) throws`, `deleteBucket(_:) throws`, `claim(_:for:) throws -> String?`, `unclaim(_:from:) throws`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/PersistenceTests/SpendBucketTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SpendBucketTests {
    private func makeStore() throws -> MoneyStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MoneyStore(context: ModelContext(container))
    }

    @Test func aClaimKeyMovesRatherThanBeingHeldTwice() throws {
        let store = try makeStore()
        let eatingOut = try store.addBucket(name: "Eating out", monthlyLimit: 300)
        let groceries = try store.addBucket(name: "Groceries", monthlyLimit: 450)
        try store.claim("FOOD_AND_DRINK_FAST_FOOD", for: eatingOut)

        let movedFrom = try store.claim("FOOD_AND_DRINK_FAST_FOOD", for: groceries)

        #expect(movedFrom == "Eating out")
        #expect(!eatingOut.claimedRaw.contains("FOOD_AND_DRINK_FAST_FOOD"))
        #expect(groceries.claimedRaw == ["FOOD_AND_DRINK_FAST_FOOD"])
    }

    @Test func claimingAFreeKeyReportsNoPreviousHolder() throws {
        let store = try makeStore()
        let bucket = try store.addBucket(name: "Transport", monthlyLimit: 120)
        #expect(try store.claim("TRANSPORTATION_TAXIS", for: bucket) == nil)
        #expect(bucket.claimedRaw == ["TRANSPORTATION_TAXIS"])
    }

    @Test func claimingAKeyTwiceForTheSameBucketDoesNotDuplicateIt() throws {
        let store = try makeStore()
        let bucket = try store.addBucket(name: "Transport", monthlyLimit: 120)
        try store.claim("TRANSPORTATION_TAXIS", for: bucket)
        try store.claim("TRANSPORTATION_TAXIS", for: bucket)
        #expect(bucket.claimedRaw == ["TRANSPORTATION_TAXIS"])
    }

    @Test func aBucketLimitMustBePositive() throws {
        let store = try makeStore()
        #expect(throws: SpendBucketError.limitNotPositive) {
            try store.addBucket(name: "Nothing", monthlyLimit: 0)
        }
        let bucket = try store.addBucket(name: "Coffee", monthlyLimit: 60)
        #expect(throws: SpendBucketError.limitNotPositive) {
            try store.updateBucket(bucket, name: "Coffee", monthlyLimit: -5)
        }
    }

    @Test func deletingABucketFreesItsKeys() throws {
        let store = try makeStore()
        let doomed = try store.addBucket(name: "Doomed", monthlyLimit: 100)
        try store.claim("ENTERTAINMENT_MUSIC", for: doomed)
        try store.deleteBucket(doomed)

        let successor = try store.addBucket(name: "Successor", monthlyLimit: 100)
        #expect(try store.claim("ENTERTAINMENT_MUSIC", for: successor) == nil)
        #expect(try store.buckets().map(\.name) == ["Successor"])
    }

    @Test func bucketsComeBackInSortOrder() throws {
        let store = try makeStore()
        try store.addBucket(name: "First", monthlyLimit: 10)
        try store.addBucket(name: "Second", monthlyLimit: 10)
        try store.addBucket(name: "Third", monthlyLimit: 10)
        #expect(try store.buckets().map(\.name) == ["First", "Second", "Third"])
    }

    /// The claim key prefers the raw code: `category` is display text, and
    /// keying arithmetic off display text means renaming a label silently
    /// changes what a budget counts.
    @Test func claimKeyPrefersTheCodeOverTheDisplayLabel() {
        let coded = MoneyEntry(
            date: .now, amount: -10, merchant: "Cafe",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE"
        )
        let manual = MoneyEntry(date: .now, amount: -10, merchant: "Cafe", category: "Coffee")
        let bare = MoneyEntry(date: .now, amount: -10, merchant: "Mystery")
        #expect(coded.claimKey == "FOOD_AND_DRINK_COFFEE")
        #expect(manual.claimKey == "Coffee")
        #expect(bare.claimKey == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter SpendBucketTests`
Expected: compile failure, `SpendBucket` and `claimKey` do not exist.

- [ ] **Step 3: Add the model, the key, and the store methods**

Create `LifeOSKit/Sources/Persistence/SpendBucket.swift`:

```swift
import Foundation
import SwiftData

/// One budget: a name, a monthly limit, and the raw claim keys it counts.
///
/// A claim key may be held by at most one bucket. `MoneyStore` enforces that
/// on write; nothing resolves collisions at read time, because by then the
/// same transaction has already counted twice and every total is quietly
/// wrong.
@Model
public final class SpendBucket {
    public var id: UUID
    public var name: String
    /// Always positive; the store rejects anything else.
    public var monthlyLimit: Double
    /// Raw claim keys: `MoneyEntry.claimKey` values.
    public var claimedRaw: [String]
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String, monthlyLimit: Double, claimedRaw: [String] = [], sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.monthlyLimit = monthlyLimit
        self.claimedRaw = claimedRaw
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}

public enum SpendBucketError: Error, Equatable {
    case limitNotPositive
}

extension MoneyEntry {
    /// What a bucket claims. The raw Plaid detailed code when the entry has
    /// one, else a manual entry's free-form category. `category` is display
    /// text and never keys arithmetic; see the `categoryCode` note above.
    public var claimKey: String? { categoryCode ?? category }
}
```

Append to `MoneyStore` in `LifeOSKit/Sources/Persistence/MoneyStore.swift` (inside the struct, after `upsertAccounts`):

```swift
    // MARK: - Spend buckets

    public func buckets() throws -> [SpendBucket] {
        try context.fetch(
            FetchDescriptor<SpendBucket>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
            )
        )
    }

    @discardableResult
    public func addBucket(name: String, monthlyLimit: Double) throws -> SpendBucket {
        guard monthlyLimit > 0 else { throw SpendBucketError.limitNotPositive }
        let bucket = SpendBucket(
            name: name,
            monthlyLimit: monthlyLimit,
            sortOrder: (try buckets().last?.sortOrder ?? -1) + 1
        )
        context.insert(bucket)
        try context.save()
        return bucket
    }

    public func updateBucket(_ bucket: SpendBucket, name: String, monthlyLimit: Double) throws {
        guard monthlyLimit > 0 else { throw SpendBucketError.limitNotPositive }
        bucket.name = name
        bucket.monthlyLimit = monthlyLimit
        bucket.updatedAt = .now
        try context.save()
    }

    public func deleteBucket(_ bucket: SpendBucket) throws {
        context.delete(bucket)
        try context.save()
    }

    /// Claims `key` for `bucket`. A key another bucket holds moves rather
    /// than being held twice, and the previous holder's name comes back so
    /// the UI can say so.
    @discardableResult
    public func claim(_ key: String, for bucket: SpendBucket) throws -> String? {
        var movedFrom: String?
        for other in try buckets() where other.id != bucket.id {
            if let index = other.claimedRaw.firstIndex(of: key) {
                other.claimedRaw.remove(at: index)
                other.updatedAt = .now
                movedFrom = other.name
            }
        }
        if !bucket.claimedRaw.contains(key) {
            bucket.claimedRaw.append(key)
            bucket.updatedAt = .now
        }
        try context.save()
        return movedFrom
    }

    public func unclaim(_ key: String, from bucket: SpendBucket) throws {
        bucket.claimedRaw.removeAll { $0 == key }
        bucket.updatedAt = .now
        try context.save()
    }
```

In `LifeOSKit/Sources/Persistence/LifeOSContainer.swift`, add `SpendBucket.self,` to the `Schema` list after `MoneyAccount.self,`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter SpendBucketTests`
Expected: PASS. Also run the full package (`swift test --package-path LifeOSKit`) to confirm nothing else moved.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/SpendBucket.swift LifeOSKit/Sources/Persistence/MoneyStore.swift LifeOSKit/Sources/Persistence/LifeOSContainer.swift LifeOSKit/Tests/PersistenceTests/SpendBucketTests.swift
git commit -m "feat(money): spend buckets with a single-holder rule per claim key"
```

---

## Task 2: `BudgetPeriod`, the pure assessment

**Files:**
- Create: `LifeOSKit/Sources/Sectors/BudgetPeriod.swift`
- Test: `LifeOSKit/Tests/SectorsTests/BudgetPeriodTests.swift`

**Interfaces:**
- Consumes: `MoneyEntry` (with `claimKey` from Task 1), `MoneyCategoryRule.isTransferLike` (existing), `SpendBucket` (Task 1).
- Produces, all in `Sectors`:
  - `SpendLine` (`key: String?`, `label: String?`, `amount: Double`)
  - `BudgetBucket` (`id: UUID`, `name: String`, `monthlyLimit: Double`, `claimed: Set<String>`, `sortOrder: Int`; `@MainActor init(_ model: SpendBucket)`)
  - `BudgetReport` with `rows: [BudgetReport.Row]` (`id: UUID`, `name`, `limit`, `spent`, `adherence`, computed `isKept`), `unclaimed: [BudgetReport.Unclaimed]` (`key: String?`, `label: String?`, `amount`, `count`), computed `keptCount: Int`, `meanAdherence: Double?`, `unclaimedTotal: Double`
  - `BudgetPeriod.lines(from: [MoneyEntry]) -> [SpendLine]` (`@MainActor`)
  - `BudgetPeriod.assess(buckets: [BudgetBucket], lines: [SpendLine]) -> BudgetReport`
  - `BudgetPeriod.adherence(spent: Double, limit: Double) -> Double` (internal, tested via `@testable`)

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/SectorsTests/BudgetPeriodTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BudgetPeriodTests {
    private let eatingOut = BudgetBucket(
        name: "Eating out", monthlyLimit: 300,
        claimed: ["FOOD_AND_DRINK_RESTAURANTS", "FOOD_AND_DRINK_FAST_FOOD"]
    )

    /// A refund arrives positive in a spend category. It must reduce that
    /// bucket's spent figure, never inflate income or unclaimed spend.
    @Test func aRefundNetsWithinItsBucket() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "FOOD_AND_DRINK_RESTAURANTS", label: "Food & drink", amount: -120),
            SpendLine(key: "FOOD_AND_DRINK_RESTAURANTS", label: "Food & drink", amount: 40),
        ])
        #expect(report.rows.first?.spent == 80)
        #expect(report.unclaimed.isEmpty)
    }

    @Test func aClaimedKeyCountsInItsBucketAndNowhereElse() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "FOOD_AND_DRINK_FAST_FOOD", label: "Food & drink", amount: -55),
        ])
        #expect(report.rows == [BudgetReport.Row(
            id: eatingOut.id, name: "Eating out", limit: 300, spent: 55,
            adherence: 1
        )])
        #expect(report.unclaimed.isEmpty)
    }

    /// Income nets positive under its key, so it never shows as unclaimed
    /// spend; only net outflows do.
    @Test func incomeNeverAppearsAsUnclaimedSpend() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "INCOME_WAGES", label: "Income", amount: 5_200),
            SpendLine(key: "ENTERTAINMENT_MUSIC", label: "Entertainment", amount: -30),
        ])
        #expect(report.unclaimed == [BudgetReport.Unclaimed(
            key: "ENTERTAINMENT_MUSIC", label: "Entertainment", amount: 30, count: 1
        )])
    }

    @Test func uncategorisedSpendGroupsUnderTheNilKey() {
        let report = BudgetPeriod.assess(buckets: [], lines: [
            SpendLine(key: nil, label: nil, amount: -25),
            SpendLine(key: nil, label: nil, amount: -15),
        ])
        #expect(report.unclaimed == [BudgetReport.Unclaimed(
            key: nil, label: nil, amount: 40, count: 2
        )])
    }

    @Test func unclaimedComesBackLargestFirst() {
        let report = BudgetPeriod.assess(buckets: [], lines: [
            SpendLine(key: "MEDICAL_DENTAL", label: "Medical", amount: -60),
            SpendLine(key: "TRAVEL_FLIGHTS", label: "Travel", amount: -400),
        ])
        #expect(report.unclaimed.map(\.key) == ["TRAVEL_FLIGHTS", "MEDICAL_DENTAL"])
    }

    @Test func adherenceIsPerfectAtOrUnderTheLimit() {
        #expect(BudgetPeriod.adherence(spent: 0, limit: 300) == 1)
        #expect(BudgetPeriod.adherence(spent: 300, limit: 300) == 1)
    }

    /// A bucket 1% over must not read the same as one at triple its limit:
    /// linear decay, hitting zero when the overspend equals the limit again.
    @Test func adherenceDegradesLinearlyToZeroAtDoubleTheLimit() {
        #expect(BudgetPeriod.adherence(spent: 450, limit: 300) == 0.5)
        #expect(BudgetPeriod.adherence(spent: 600, limit: 300) == 0)
        #expect(BudgetPeriod.adherence(spent: 900, limit: 300) == 0)
    }

    @Test func keptCountAndMeanAdherenceSummarise() {
        let over = BudgetBucket(name: "Over", monthlyLimit: 100, claimed: ["A"])
        let under = BudgetBucket(name: "Under", monthlyLimit: 100, claimed: ["B"])
        let report = BudgetPeriod.assess(buckets: [over, under], lines: [
            SpendLine(key: "A", label: nil, amount: -200),
            SpendLine(key: "B", label: nil, amount: -50),
        ])
        #expect(report.keptCount == 1)
        #expect(report.meanAdherence == 0.5)
    }

    @Test func noBucketsMeansNoMeanAdherence() {
        #expect(BudgetPeriod.assess(buckets: [], lines: []).meanAdherence == nil)
    }

    /// The one entry filter, shared by the screen and the close: pending and
    /// transfer-like entries drop, and the raw code beats the display label.
    @Test @MainActor func linesDropPendingAndTransfersAndPreferTheCode() {
        let entries = [
            MoneyEntry(date: .now, amount: -50, merchant: "Shop",
                       category: "Shopping", categoryCode: "GENERAL_MERCHANDISE_SUPERSTORES"),
            MoneyEntry(date: .now, amount: -999, merchant: "Hold", pending: true),
            MoneyEntry(date: .now, amount: -400, merchant: "Card payment",
                       categoryCode: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"),
            MoneyEntry(date: .now, amount: -12, merchant: "Cafe", category: "Coffee"),
        ]
        let lines = BudgetPeriod.lines(from: entries)
        #expect(lines.map(\.key) == ["GENERAL_MERCHANDISE_SUPERSTORES", "Coffee"])
        #expect(lines.first?.label == "Shopping")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter BudgetPeriodTests`
Expected: compile failure, `BudgetPeriod` does not exist.

- [ ] **Step 3: Write the assessment**

Create `LifeOSKit/Sources/Sectors/BudgetPeriod.swift`:

```swift
import Foundation
import Persistence

/// One countable transaction, reduced to what budgeting needs. `label` is the
/// display string the transaction list already shows, carried for the
/// unclaimed view; it never keys arithmetic.
public struct SpendLine: Sendable, Equatable {
    public let key: String?
    public let label: String?
    public let amount: Double

    public init(key: String?, label: String?, amount: Double) {
        self.key = key
        self.label = label
        self.amount = amount
    }
}

/// A bucket as a plain value, so `assess` stays pure and its tests need no
/// container.
public struct BudgetBucket: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let monthlyLimit: Double
    public let claimed: Set<String>
    public let sortOrder: Int

    public init(id: UUID = UUID(), name: String, monthlyLimit: Double,
                claimed: Set<String>, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.monthlyLimit = monthlyLimit
        self.claimed = claimed
        self.sortOrder = sortOrder
    }

    @MainActor
    public init(_ model: SpendBucket) {
        self.init(id: model.id, name: model.name, monthlyLimit: model.monthlyLimit,
                  claimed: Set(model.claimedRaw), sortOrder: model.sortOrder)
    }
}

/// One month's budgets, measured.
public struct BudgetReport: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let id: UUID
        public let name: String
        public let limit: Double
        public let spent: Double
        /// 1.0 at or under the limit, degrading linearly to 0 when the
        /// overspend reaches the limit again.
        public let adherence: Double

        public var isKept: Bool { spent <= limit }

        public init(id: UUID, name: String, limit: Double, spent: Double, adherence: Double) {
            self.id = id
            self.name = name
            self.limit = limit
            self.spent = spent
            self.adherence = adherence
        }
    }

    /// Net outflow no bucket claims. First-class, never silently dropped:
    /// the whole point of buckets over raw strings was that nothing stops
    /// counting quietly.
    public struct Unclaimed: Sendable, Equatable {
        public let key: String?
        public let label: String?
        public let amount: Double
        public let count: Int

        public init(key: String?, label: String?, amount: Double, count: Int) {
            self.key = key
            self.label = label
            self.amount = amount
            self.count = count
        }
    }

    public let rows: [Row]
    public let unclaimed: [Unclaimed]

    public init(rows: [Row], unclaimed: [Unclaimed]) {
        self.rows = rows
        self.unclaimed = unclaimed
    }

    public var keptCount: Int { rows.filter(\.isKept).count }

    /// Nil with no buckets: no evidence, no number, never a zero.
    public var meanAdherence: Double? {
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + $1.adherence } / Double(rows.count)
    }

    public var unclaimedTotal: Double { unclaimed.reduce(0) { $0 + $1.amount } }
}

public enum BudgetPeriod {
    /// The one place the entry filter lives. Both call sites, the Money
    /// screen and the monthly close, come through here, so the two cannot
    /// drift: pending entries drop, transfer-like codes drop (a card payment
    /// must not surface as unclaimed spend), and the claim key prefers the
    /// raw code over the display label.
    @MainActor
    public static func lines(from entries: [MoneyEntry]) -> [SpendLine] {
        entries
            .filter { !$0.pending && !MoneyCategoryRule.isTransferLike($0.categoryCode) }
            .map { SpendLine(key: $0.claimKey, label: $0.category, amount: $0.amount) }
    }

    public static func assess(buckets: [BudgetBucket], lines: [SpendLine]) -> BudgetReport {
        var netByKey: [String?: Double] = [:]
        var countByKey: [String?: Int] = [:]
        var labelByKey: [String?: String] = [:]
        for line in lines {
            netByKey[line.key, default: 0] += line.amount
            countByKey[line.key, default: 0] += 1
            if let label = line.label { labelByKey[line.key] = label }
        }

        let rows = buckets
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { bucket in
                // Netting across the bucket's keys is what makes a refund
                // reduce spend instead of inflating income.
                let net = bucket.claimed.reduce(0) { $0 + (netByKey[$1] ?? 0) }
                let spent = max(0, -net)
                return BudgetReport.Row(
                    id: bucket.id, name: bucket.name, limit: bucket.monthlyLimit,
                    spent: spent, adherence: adherence(spent: spent, limit: bucket.monthlyLimit)
                )
            }

        let claimedKeys = Set(buckets.flatMap(\.claimed))
        let unclaimed = netByKey
            .filter { key, net in
                net < 0 && !(key.map(claimedKeys.contains) ?? false)
            }
            .map { key, net in
                BudgetReport.Unclaimed(
                    key: key, label: labelByKey[key],
                    amount: -net, count: countByKey[key] ?? 0
                )
            }
            .sorted { $0.amount > $1.amount }

        return BudgetReport(rows: rows, unclaimed: unclaimed)
    }

    /// At or under the limit is 1.0; over, linear decay reaching 0 when the
    /// overspend equals the limit again.
    static func adherence(spent: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        guard spent > limit else { return 1 }
        return max(0, 1 - (spent - limit) / limit)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter BudgetPeriodTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/BudgetPeriod.swift LifeOSKit/Tests/SectorsTests/BudgetPeriodTests.swift
git commit -m "feat(sectors): measure a month's budgets as a pure assessment"
```

---

## Task 3: Adherence leads the Money score

**Files:**
- Modify: `LifeOSKit/Sources/Sectors/MoneyScorer.swift`
- Modify: `LifeOSKit/Sources/Sectors/MonthInputs.swift` (add `budget`)
- Modify: `LifeOSKit/Sources/Sectors/SectorEvidenceFactory.swift` (pass it through)
- Modify: `LIfeOS/Features/Life/ViewModel/MonthlyCloseViewModel.swift` (`loadMonthInputs`)
- Test: `LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift` (append)

**Interfaces:**
- Consumes: `BudgetReport`, `BudgetBucket`, `BudgetPeriod` (Task 2); `MoneyStore.buckets()` (Task 1).
- Produces: `MoneyScorer(amounts:previousAmounts:budget:)` with `budget: BudgetReport? = nil`; `MonthInputs.budget: BudgetReport?` (default nil). Evidence rows: `budgets kept` (weight 3, value "K/N", normalised mean adherence), `kept of what came in` weight 2 when adherence exists else 3, `unclaimed` (weight 0) only when nonzero.

- [ ] **Step 1: Write the failing tests**

Append to `LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift`, inside the suite:

```swift
    private func report(spent: Double, limit: Double = 300, unclaimed: Double = 0) -> BudgetReport {
        var lines = [SpendLine(key: "FOOD", label: "Food & drink", amount: -spent)]
        if unclaimed > 0 {
            lines.append(SpendLine(key: "MYSTERY", label: nil, amount: -unclaimed))
        }
        return BudgetPeriod.assess(
            buckets: [BudgetBucket(name: "Eating out", monthlyLimit: limit, claimed: ["FOOD"])],
            lines: lines
        )
    }

    @Test func withBucketsAdherenceLeadsAndTheSavingRateStepsDown() {
        let rows = MoneyScorer(
            amounts: [4_000, -200], previousAmounts: [], budget: report(spent: 200)
        ).evidence().rows

        let adherence = rows.first { $0.label == "budgets kept" }
        #expect(adherence?.value == "1/1")
        #expect(adherence?.weight == 3)
        #expect(adherence?.normalised == 1)
        #expect(rows.first { $0.label == "kept of what came in" }?.weight == 2)
    }

    @Test func aBustedBudgetDragsTheAdherenceRowDown() {
        let rows = MoneyScorer(
            amounts: [4_000, -600], previousAmounts: [], budget: report(spent: 600)
        ).evidence().rows
        let adherence = rows.first { $0.label == "budgets kept" }
        #expect(adherence?.value == "0/1")
        #expect(adherence?.normalised == 0)
    }

    /// No buckets leaves the score exactly as it is today, row for row.
    @Test func withNoBucketsTheEvidenceIsUnchangedFromToday() {
        let evidence = MoneyScorer(amounts: [4_000, -1_000], previousAmounts: []).evidence()
        #expect(!evidence.rows.contains { $0.label == "budgets kept" })
        #expect(!evidence.rows.contains { $0.label == "unclaimed" })
        #expect(evidence.rows.first { $0.label == "kept of what came in" }?.weight == 3)
    }

    /// Unclaimed spend is a gap in the mapping, not a judgement on the
    /// person: shown, never scored.
    @Test func unclaimedSpendIsShownButNeverScored() {
        let rows = MoneyScorer(
            amounts: [4_000, -410], previousAmounts: [],
            budget: report(spent: 200, unclaimed: 210)
        ).evidence().rows
        let row = rows.first { $0.label == "unclaimed" }
        #expect(row?.value == "210")
        #expect(row?.weight == 0)
    }

    @Test func aZeroUnclaimedMonthGetsNoUnclaimedRow() {
        let rows = MoneyScorer(
            amounts: [4_000, -200], previousAmounts: [], budget: report(spent: 200)
        ).evidence().rows
        #expect(!rows.contains { $0.label == "unclaimed" })
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter MoneyScorerTests`
Expected: compile failure, `MoneyScorer` takes no `budget` parameter.

- [ ] **Step 3: Reweight the scorer and thread the report through**

Replace `LifeOSKit/Sources/Sectors/MoneyScorer.swift` with:

```swift
import Foundation
import Persistence

/// Money, from this month's transactions.
///
/// **Sign convention, inherited from `MoneyEntry`: positive is money in,
/// negative is money out.** A flip here turns every good month into a bad one,
/// which is why the split is done once, at the top, and named.
///
/// With buckets, adherence takes the top weight and the saving rate steps
/// down: a budget is a plan you set, and beating it measures what you decided
/// mattered, where a saving rate measures what happened to be left over. With
/// no buckets the evidence is exactly what it was before budgets existed.
public struct MoneyScorer: SectorScorer {
    public let sector = LifeSector.money

    private let amounts: [Double]
    private let previousAmounts: [Double]
    private let budget: BudgetReport?

    public init(amounts: [Double], previousAmounts: [Double], budget: BudgetReport? = nil) {
        self.amounts = amounts
        self.previousAmounts = previousAmounts
        self.budget = budget
    }

    public func evidence() -> Evidence {
        guard !amounts.isEmpty else { return Evidence() }

        let earned = amounts.filter { $0 > 0 }.reduce(0, +)
        let spent = -amounts.filter { $0 < 0 }.reduce(0, +)
        let adherence = budget?.meanAdherence

        var rows = [
            EvidenceRow(label: "earned", value: Self.money(earned), normalised: 0, weight: 0),
            EvidenceRow(label: "spent", value: Self.money(spent), normalised: 0, weight: 0),
        ]

        if let budget, let adherence {
            rows.append(EvidenceRow(
                label: "budgets kept",
                value: "\(budget.keptCount)/\(budget.rows.count)",
                normalised: adherence,
                weight: 3
            ))
        }

        // A month that earned nothing cannot have a saving rate. It scores
        // poorly rather than perfectly, and says why.
        let savingRate = earned > 0 ? (earned - spent) / earned : 0
        rows.append(EvidenceRow(
            label: "kept of what came in",
            value: earned > 0 ? "\(Int((savingRate * 100).rounded()))%" : "no income",
            normalised: savingRate / 0.5,  // Relies on EvidenceRow clamping above 1.0 (high savings) and below 0.0 (spending more than earning)
            weight: adherence == nil ? 3 : 2
        ))

        let previousSpend = -previousAmounts.filter { $0 < 0 }.reduce(0, +)
        if previousSpend > 0 {
            let change = (previousSpend - spent) / previousSpend
            rows.append(EvidenceRow(
                label: "spend vs last month",
                value: "\(change >= 0 ? "-" : "+")\(Int((abs(change) * 100).rounded()))%",
                normalised: 0.5 + change,  // Relies on EvidenceRow clamping above 1.0 and below 0.0
                weight: 1
            ))
        }

        // A gap in the category mapping, not a judgement on the person:
        // shown so it can be fixed, kept out of the arithmetic.
        if let budget, budget.unclaimedTotal > 0 {
            rows.append(EvidenceRow(
                label: "unclaimed", value: Self.money(budget.unclaimedTotal),
                normalised: 0, weight: 0
            ))
        }

        return Evidence(rows)
    }

    private static func money(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
```

In `LifeOSKit/Sources/Sectors/MonthInputs.swift`:

- After `public var previousAmounts: [Double]` add:

```swift
    /// This month's budgets, measured, or nil when no buckets exist.
    public var budget: BudgetReport?
```

- In the initializer, after `previousAmounts: [Double] = [],` add `budget: BudgetReport? = nil,` and after `self.previousAmounts = previousAmounts` add `self.budget = budget`.

In `LifeOSKit/Sources/Sectors/SectorEvidenceFactory.swift`, the `.money` case becomes:

```swift
        case .money:
            return MoneyScorer(
                amounts: inputs.amounts, previousAmounts: inputs.previousAmounts,
                budget: inputs.budget
            ).evidence()
```

In `LIfeOS/Features/Life/ViewModel/MonthlyCloseViewModel.swift`, `loadMonthInputs()`: replace

```swift
        let amounts = try moneyStore.entries(from: window.start, to: window.lastDay)
            .filter { !$0.pending }
            .map(\.amount)
```

with

```swift
        let monthEntries = try moneyStore.entries(from: window.start, to: window.lastDay)
        let amounts = monthEntries.filter { !$0.pending }.map(\.amount)

        let buckets = try moneyStore.buckets().map(BudgetBucket.init)
        let budget = buckets.isEmpty
            ? nil
            : BudgetPeriod.assess(buckets: buckets, lines: BudgetPeriod.lines(from: monthEntries))
```

and in the trailing `MonthInputs(...)` call change `amounts: amounts, previousAmounts: previousAmounts,` to `amounts: amounts, previousAmounts: previousAmounts, budget: budget,`.

- [ ] **Step 4: Run the tests and build the app**

Run: `swift test --package-path LifeOSKit && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: all package tests PASS (the pre-existing `MoneyScorerTests` untouched cases included), app builds.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/MoneyScorer.swift LifeOSKit/Sources/Sectors/MonthInputs.swift LifeOSKit/Sources/Sectors/SectorEvidenceFactory.swift LIfeOS/Features/Life/ViewModel/MonthlyCloseViewModel.swift LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift
git commit -m "feat(sectors): budget adherence leads the Money score when buckets exist"
```

---

## Task 4: The budgets band on the Money screen

**Files:**
- Modify: `LIfeOS/Features/Money/Model/MoneySnapshot.swift`
- Modify: `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`
- Modify: `LIfeOS/Features/Money/View/MoneyScreen.swift`

**Interfaces:**
- Consumes: `BudgetPeriod`, `BudgetBucket`, `BudgetReport` (Task 2); `MoneyStore.buckets()` (Task 1).
- Produces: `MoneySnapshot.budgets: [BudgetBandRow]` and `.unclaimed: [UnclaimedBandRow]`; `MoneyScreen.onEditBudgets: () -> Void` (Task 5 wires it). `MoneyViewModel` keeps `private(set) var buckets: [SpendBucket]` fresh for the editor.

- [ ] **Step 1: Extend the snapshot**

In `LIfeOS/Features/Money/Model/MoneySnapshot.swift`, add to `MoneySnapshot` after `var recent: [MoneyRow] = []`:

```swift
    var budgets: [BudgetBandRow] = []
    var unclaimed: [UnclaimedBandRow] = []
```

and append at the end of the file:

```swift
struct BudgetBandRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    let limit: Double
    let spent: Double

    var isOver: Bool { spent > limit }
    var progress: Double { limit > 0 ? min(spent / limit, 1) : 0 }
}

struct UnclaimedBandRow: Equatable, Identifiable {
    /// The claim key, or "uncategorised" for the nil key.
    let id: String
    let label: String
    let amount: Double
    let count: Int
}
```

- [ ] **Step 2: Build the rows in the view model**

In `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`:

- Add `import Sectors` under `import Persistence`.
- Add `private(set) var buckets: [SpendBucket] = []` under `private(set) var snapshot`.
- In `load(connection:)`, after `let summary = summarise(...)`, add:

```swift
            buckets = try store.buckets()
            var budgetRows: [BudgetBandRow] = []
            var unclaimedRows: [UnclaimedBandRow] = []
            if !buckets.isEmpty {
                let budget = BudgetPeriod.assess(
                    buckets: buckets.map(BudgetBucket.init),
                    lines: BudgetPeriod.lines(from: entries)
                )
                budgetRows = budget.rows.map {
                    BudgetBandRow(id: $0.id, name: $0.name, limit: $0.limit, spent: $0.spent)
                }
                unclaimedRows = budget.unclaimed.map {
                    UnclaimedBandRow(
                        id: $0.key ?? "uncategorised",
                        label: $0.label ?? $0.key ?? "Uncategorised",
                        amount: $0.amount,
                        count: $0.count
                    )
                }
            }
```

- In the `MoneySnapshot(...)` construction, after `recent: entries.prefix(8).map { ... },` add `budgets: budgetRows,` and `unclaimed: unclaimedRows,` (order must match the struct's property order in the memberwise-style init usage; `MoneySnapshot` uses var defaults, so pass them as labeled arguments in declaration order after `recent`).

- [ ] **Step 3: Render the band**

In `LIfeOS/Features/Money/View/MoneyScreen.swift`:

- Add `var onEditBudgets: () -> Void = {}` after `var onSync: () -> Void = {}`.
- In the connected branch, after the net-worth `SoftCard` block (and before `transactions`), add `budgetsBand`.
- Add the view builders after `transactions`:

```swift
    private var budgetsBand: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("BUDGETS")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button(snapshot.budgets.isEmpty ? "Set budgets" : "Edit", action: onEditBudgets)
                        .font(.system(size: 13, weight: .semibold))
                        .tint(LifeOSTokens.accent)
                }

                if snapshot.budgets.isEmpty {
                    Text("Set a monthly limit for the spending you care about.")
                        .font(.footnote)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                ForEach(snapshot.budgets) { row in
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.name).font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("\(Self.money(row.spent) ?? "—") / \(Self.money(row.limit) ?? "—")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(row.isOver ? .orange : LifeOSTokens.primaryText.resolve(scheme))
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme))
                                Capsule()
                                    .fill(row.isOver ? Color.orange : LifeOSTokens.accent)
                                    .frame(width: proxy.size.width * row.progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                if !snapshot.unclaimed.isEmpty { unclaimedRows }
            }
        }
    }

    /// Spend no bucket claims. Always rendered when present: the point of
    /// buckets is that nothing stops counting quietly.
    private var unclaimedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UNCLAIMED")
                .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                .padding(.top, 4)
            ForEach(snapshot.unclaimed) { row in
                HStack {
                    Text(row.count > 1 ? "\(row.label) ×\(row.count)" : row.label)
                        .font(.system(size: 14))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    Spacer()
                    Text(Self.money(row.amount) ?? "—")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            Button("Assign to a bucket", action: onEditBudgets)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
    }
```

- Extend the "With data" preview's snapshot with band rows so the band is visible in canvas:

```swift
        budgets: [
            BudgetBandRow(id: UUID(), name: "Eating out", limit: 300, spent: 210),
            BudgetBandRow(id: UUID(), name: "Groceries", limit: 450, spent: 480),
        ],
        unclaimed: [UnclaimedBandRow(id: "GENERAL_MERCHANDISE", label: "Shopping", amount: 210, count: 4)],
```

(placed after `recent: [...]`, matching property order.)

- [ ] **Step 4: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Money/Model/MoneySnapshot.swift LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift LIfeOS/Features/Money/View/MoneyScreen.swift
git commit -m "feat(money): budgets band with unclaimed spend on the Money screen"
```

---

## Task 5: The bucket editor sheet

**Files:**
- Create: `LIfeOS/Features/Money/View/BucketEditorSheet.swift`
- Modify: `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift` (editor data and actions)
- Modify: `LIfeOS/App/RootView.swift` (present the sheet)

**Interfaces:**
- Consumes: `MoneyStore` bucket CRUD (Task 1), `MoneyViewModel.buckets` (Task 4), `MoneyScreen.onEditBudgets` (Task 4).
- Produces: `ClaimableCategory` (`id: String` key, `label: String`, `holder: String?`), `MoneyViewModel.claimableCategories() -> [ClaimableCategory]`, `saveBucket(id:name:limit:claimed:)`, `deleteBucket(id:)`, and `BucketEditorSheet(model: MoneyViewModel)`.

- [ ] **Step 1: Editor data and actions on the view model**

Append to `MoneyViewModel` in `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`:

```swift
    // MARK: - Bucket editing

    /// Everything claimable: keys seen on the last three months of entries
    /// plus keys buckets already hold, each with the display label the
    /// transaction list uses and the name of the bucket holding it, if any.
    /// Three months, not one: the category you spent in last month but not
    /// yet this month is exactly the one you are budgeting for.
    func claimableCategories() -> [ClaimableCategory] {
        guard let context else { return [] }
        let store = MoneyStore(context: context, calendar: calendar)

        var labelByKey: [String: String] = [:]
        var order: [String] = []
        let start = calendar.date(byAdding: .month, value: -3, to: .now) ?? .now
        for entry in (try? store.entries(from: start, to: .now)) ?? [] {
            guard let key = entry.claimKey else { continue }
            if labelByKey[key] == nil { order.append(key) }
            labelByKey[key] = entry.category ?? key
        }
        for bucket in buckets {
            for key in bucket.claimedRaw where labelByKey[key] == nil {
                order.append(key)
                labelByKey[key] = key
            }
        }

        let holderByKey = buckets.reduce(into: [String: String]()) { result, bucket in
            for key in bucket.claimedRaw { result[key] = bucket.name }
        }
        return order.sorted { labelByKey[$0]! < labelByKey[$1]! }.map {
            ClaimableCategory(id: $0, label: labelByKey[$0]!, holder: holderByKey[$0])
        }
    }

    /// Creates or updates a bucket, then reconciles its claims. The store
    /// owns the single-holder rule; a key claimed here moves from whichever
    /// bucket held it.
    func saveBucket(id: UUID?, name: String, limit: Double, claimed: Set<String>) {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)
        do {
            let bucket: SpendBucket
            if let id, let existing = buckets.first(where: { $0.id == id }) {
                try store.updateBucket(existing, name: name, monthlyLimit: limit)
                bucket = existing
            } else {
                bucket = try store.addBucket(name: name, monthlyLimit: limit)
            }
            for key in Set(bucket.claimedRaw).subtracting(claimed) {
                try store.unclaim(key, from: bucket)
            }
            for key in claimed.subtracting(bucket.claimedRaw) {
                try store.claim(key, for: bucket)
            }
            load()
        } catch {
            assertionFailure("Bucket save failed: \(error)")
        }
    }

    func deleteBucket(id: UUID) {
        guard let context, let bucket = buckets.first(where: { $0.id == id }) else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).deleteBucket(bucket)
            load()
        } catch {
            assertionFailure("Bucket delete failed: \(error)")
        }
    }
```

and append at the end of the file:

```swift
struct ClaimableCategory: Equatable, Identifiable {
    /// The claim key.
    let id: String
    let label: String
    /// Name of the bucket holding this key, nil when it is free.
    let holder: String?
}
```

- [ ] **Step 2: The sheet**

Create `LIfeOS/Features/Money/View/BucketEditorSheet.swift`:

```swift
import SwiftUI
import Persistence

/// Budgets: the bucket list, and one bucket's name, limit and claims.
/// Follows `AddMoneySheet`'s form idiom. The store owns the single-holder
/// rule; this sheet only says when saving will move a key from another
/// bucket.
struct BucketEditorSheet: View {
    @Bindable var model: MoneyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditingBucket?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.buckets, id: \.id) { bucket in
                    Button {
                        editing = EditingBucket(bucket)
                    } label: {
                        HStack {
                            Text(bucket.name).foregroundStyle(.primary)
                            Spacer()
                            Text(bucket.monthlyLimit.formatted(
                                .currency(code: "USD").precision(.fractionLength(0))
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        model.deleteBucket(id: model.buckets[offset].id)
                    }
                }

                Button("New bucket") { editing = EditingBucket() }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { bucket in
                BucketForm(model: model, bucket: bucket)
            }
        }
    }
}

/// A value copy of what the form edits, so cancel abandons it untouched.
private struct EditingBucket: Identifiable {
    let id: UUID?
    var name: String
    var limit: String
    var claimed: Set<String>

    init() {
        id = nil
        name = ""
        limit = ""
        claimed = []
    }

    init(_ bucket: SpendBucket) {
        id = bucket.id
        name = bucket.name
        limit = String(Int(bucket.monthlyLimit.rounded()))
        claimed = Set(bucket.claimedRaw)
    }
}

private struct BucketForm: View {
    let model: MoneyViewModel
    @State var bucket: EditingBucket
    @Environment(\.dismiss) private var dismiss

    private var parsedLimit: Double? {
        guard let value = Double(bucket.limit), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $bucket.name)
                    TextField("Monthly limit", text: $bucket.limit)
                        .keyboardType(.decimalPad)
                }

                Section("Counts") {
                    if model.claimableCategories().isEmpty {
                        Text("Categories appear here once you have transactions.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.claimableCategories()) { category in
                        Button {
                            if bucket.claimed.contains(category.id) {
                                bucket.claimed.remove(category.id)
                            } else {
                                bucket.claimed.insert(category.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.label).foregroundStyle(.primary)
                                    if let holder = category.holder,
                                       !bucket.claimed.contains(category.id) {
                                        Text("Held by \(holder), saving moves it here")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if bucket.claimed.contains(category.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(bucket.id == nil ? "New bucket" : "Edit bucket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsedLimit {
                            model.saveBucket(
                                id: bucket.id, name: bucket.name,
                                limit: parsedLimit, claimed: bucket.claimed
                            )
                        }
                        dismiss()
                    }
                    .disabled(
                        parsedLimit == nil
                        || bucket.name.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
    }
}
```

Note: `MoneyViewModel` is `@Observable`; if `@Bindable` complains (no bindings are actually needed), drop it to `let model: MoneyViewModel`.

- [ ] **Step 3: Present it from RootView**

In `LIfeOS/App/RootView.swift`:

- Add `@State private var showBudgets = false` beside `@State private var showAddMoney = false`.
- In the `.money` case, add `onEditBudgets: { showBudgets = true },` after `onAdd: { showAddMoney = true },`.
- After the `showAddMoney` sheet modifier, add:

```swift
        .sheet(isPresented: $showBudgets, onDismiss: { money.load(connection: plaid) }) {
            BucketEditorSheet(model: money)
        }
```

(The `onDismiss` reload keeps the band honest after edits; check the `.money` case for how `money.load(connection:)` is called elsewhere and match it.)

- [ ] **Step 4: Build and run the full suite**

Run: `swift test --package-path LifeOSKit && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: all tests PASS, app builds.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Money/View/BucketEditorSheet.swift LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift LIfeOS/App/RootView.swift
git commit -m "feat(money): edit buckets and assign categories from a sheet"
```

---

## Verification sweep (after all tasks)

- `swift test --package-path LifeOSKit` is green.
- `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build` succeeds.
- In the simulator: with no buckets the Money screen shows the quiet "Set budgets" affordance and the Money close scores exactly as before; after creating a bucket and claiming a category, the band shows spend against limit, unclaimed spend lists with an assign path, and the close's Money evidence leads with "budgets kept".
