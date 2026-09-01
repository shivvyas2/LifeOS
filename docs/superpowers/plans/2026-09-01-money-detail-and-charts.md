# Money: precision, logos, drill-down and charts. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Money tab precise to the cent, put merchant logos on every row, let every category, merchant and transaction open a detail page, and draw the month with three Swift Charts.

**Architecture:** Two additive fields in LifeOSKit (`logoURL` on the entry and the ingest row, decoded from Plaid) and one pure series module (`SpendSeries`) carry the new data; the app's `MoneyViewModel` derives the week series, donut slices and logo map from the month it already loads; a new `MoneyDetailScreen` with its own view model is pushed on the Money tab's `NavigationStack` with a `MoneyDetailFilter` item, following the `MetricDetailScreen` pattern.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Charts (`SectorMark`, `BarMark`, `chartAngleSelection`), Swift Testing in LifeOSKit.

**Spec:** `docs/superpowers/specs/2026-09-01-money-detail-and-charts-design.md`

## Global Constraints

- iOS 26 target. LifeOSKit `Package.swift` platforms `.iOS("26.0"), .macOS("26.0")`.
- Sign convention: positive is money in. Plaid is negated in `PlaidMapping`.
- Additive SwiftData migration only: new optional properties, nothing renamed.
- Money screen vocabulary: full-bleed pastel bands, one ink (`MoneyPalette.ink`), `moneyEyebrow`, `MoneyFigure`. No `SoftCard` on the Money tab.
- Charts: single ink at stepped opacity. Never a categorical pastel palette (it fails the dataviz validator).
- Commits: conventional `type(scope): imperative summary`, no em dashes, no attribution trailer, on branch `feat/money-detail-and-charts`.
- Tests: `cd LifeOSKit && swift test --filter <Suite>`. App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build`.
- Worktree: `/Users/shivvyas/LIfeOS/.claude/worktrees/money-detail-charts`. All paths below are relative to it.

---

### Task 1: Store Plaid's logo URL on each transaction

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/PlaidWireFormat.swift:32-70` (`PlaidTransaction`)
- Modify: `LifeOSKit/Sources/Integrations/PlaidMapping.swift:50-62`
- Modify: `LifeOSKit/Sources/Persistence/MoneyEntry.swift:36-80`
- Modify: `LifeOSKit/Sources/Persistence/MoneyStore.swift:12-40, 170-185`
- Test: `LifeOSKit/Tests/IntegrationsTests/PlaidFixtures.swift`, `PlaidWireFormatTests.swift`, `PlaidMappingTests.swift`, `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`

**Interfaces:**
- Produces: `MoneyEntry.logoURL: String?`, `MoneyIngestRow.logoURL: String?` (new init parameter after `merchantID`), `PlaidTransaction.logo_url: String?`.

- [ ] **Step 1: Give the fixture's coffee transaction a logo**

In `PlaidFixtures.swift`, inside the `txn_coffee` object after `"merchant_entity_id": "mch_bluebottle",` add:

```json
              "logo_url": "https://plaid-merchant-logos.plaid.com/blue_bottle_1234.png",
```

Leave every other transaction without the key, so absence is exercised.

- [ ] **Step 2: Write the failing tests**

`PlaidWireFormatTests.swift`, after `anUnresolvedDescriptorHasNoMerchantEntity`:

```swift
    @Test func aLogoIsDecodedWhenPlaidSentOne() throws {
        let coffee = try #require(delta().added.first { $0.transaction_id == "txn_coffee" })
        #expect(coffee.logo_url == "https://plaid-merchant-logos.plaid.com/blue_bottle_1234.png")
    }

    @Test func aTransactionWithoutALogoStillDecodes() throws {
        let payroll = try #require(delta().added.first { $0.transaction_id == "txn_payroll" })
        #expect(payroll.logo_url == nil)
    }
```

`PlaidMappingTests.swift`, after `anUnresolvedMerchantCarriesNoEntityID`:

```swift
    @Test func aLogoRidesTheIngestRow() throws {
        let rows = try PlaidMapping.ingestRows(from: delta().added)
        let coffee = try #require(rows.first { $0.externalID == "txn_coffee" })
        #expect(coffee.logoURL == "https://plaid-merchant-logos.plaid.com/blue_bottle_1234.png")
        let payroll = try #require(rows.first { $0.externalID == "txn_payroll" })
        #expect(payroll.logoURL == nil)
    }
```

`MoneyTests.swift`, after `aManualEntryHasNoMerchantEntity`:

```swift
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
```

Every existing `MoneyIngestRow(...)` call in `MoneyTests.swift` needs `logoURL: nil,` inserted after its `merchantID:` argument (there are eight).

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd LifeOSKit && swift test --filter "PlaidWireFormatTests|PlaidMappingTests|MoneyTests"`
Expected: compile errors, `logo_url` and `logoURL` do not exist.

- [ ] **Step 4: Decode, map and store the field**

`PlaidWireFormat.swift`, in `PlaidTransaction` after `merchant_entity_id`:

```swift
    /// Plaid's merchant mark, a 100 by 100 PNG, when it resolved one. Nil is
    /// ordinary: an unresolved descriptor has no logo, and a resolved one may
    /// still lack an image.
    public let logo_url: String?
```

Add `logo_url: String? = nil,` to the memberwise `init` after `merchant_entity_id`, and `self.logo_url = logo_url`.

`PlaidMapping.swift`, in the `MoneyIngestRow(` construction, after `merchantID: transaction.merchant_entity_id,`:

```swift
                logoURL: transaction.logo_url,
```

`MoneyEntry.swift`, after the `merchantID` property:

```swift
    /// Where the merchant's mark can be fetched. A string rather than a URL
    /// because SwiftData stores it as text either way and a malformed value
    /// should read back as "no logo", not fail the row. Optional and additive
    /// for the same migration reason as `merchantID`.
    public var logoURL: String?
```

Add `logoURL: String? = nil,` to `init` after `merchantID`, and `self.logoURL = logoURL`.

`MoneyStore.swift`, `MoneyIngestRow`: add `public let logoURL: String?` after `merchantID`, the init parameter `logoURL: String?` after `merchantID: String?`, and `self.logoURL = logoURL`. In `ingest`, after `entry.merchantID = row.merchantID`:

```swift
            entry.logoURL = row.logoURL
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd LifeOSKit && swift test --filter "PlaidWireFormatTests|PlaidMappingTests|MoneyTests"`
Expected: all pass, including the two new decode tests, the mapping test and the two store tests.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit
git commit -m "feat(money): store the merchant logo Plaid sends with each transaction

logo_url is already in every sync response. Stored additively on MoneyEntry
so the ledger can show a mark beside a merchant name, and written on every
upsert so a replayed history backfills rows synced before this existed."
```

---

### Task 2: One spending predicate shared by the summary and the category rollup

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MoneyEntry.swift:82-90` (`isIncome` neighbourhood) and `summarise` at the bottom of the file
- Test: `LifeOSKit/Tests/PersistenceTests/MoneyTests.swift`

**Interfaces:**
- Produces: `MoneyEntry.isSpending: Bool`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter MoneyTests`
Expected: compile error, `isSpending` does not exist.

- [ ] **Step 3: Implement**

In `MoneyEntry`, after `public var isIncome: Bool { amount > 0 }`:

```swift
    /// Money that left and counts as spent: a settled outflow that is not a
    /// transfer or a card payment. The category rollup and the donut are
    /// built from this, and `summarise` uses the same rule, so the category
    /// list sums to the "Spent" figure above it.
    public var isSpending: Bool {
        amount < 0 && !pending && !MoneyCategoryRule.isTransferLike(categoryCode)
    }
```

Rewrite the loop in `summarise`:

```swift
    for entry in entries where !entry.pending
        && !MoneyCategoryRule.isTransferLike(entry.categoryCode) {
        if entry.amount > 0 { income += entry.amount } else if entry.isSpending { expenses += -entry.amount }
    }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd LifeOSKit && swift test --filter MoneyTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MoneyEntry.swift LifeOSKit/Tests/PersistenceTests/MoneyTests.swift
git commit -m "feat(money): name the spending predicate the summary already applies

The category rollup counted pending charges and card payments that the
Spent figure excludes, so the list never summed to the total above it.
One predicate on the entry, read by both."
```

---

### Task 3: `SpendSeries`, the week, month and fold maths

**Files:**
- Create: `LifeOSKit/Sources/Insights/SpendSeries.swift`
- Test: `LifeOSKit/Tests/InsightsTests/SpendSeriesTests.swift`

**Interfaces:**
- Produces:
  - `SpendSeries.Line(amount: Double, date: Date)`
  - `SpendSeries.DayTotal { date: Date; amount: Double; isFuture: Bool }`
  - `SpendSeries.MonthTotal { monthStart: Date; amount: Double }`
  - `SpendSeries.Share { name: String; amount: Double }`
  - `SpendSeries.week(of:lines:calendar:) -> [DayTotal]`
  - `SpendSeries.months(endingIn:count:lines:calendar:) -> [MonthTotal]`
  - `SpendSeries.fold(_:keep:) -> [Share]`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to see them fail**

Run: `cd LifeOSKit && swift test --filter SpendSeriesTests`
Expected: compile error, `SpendSeries` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The shapes the Money charts are drawn from: a week of daily spend, a run
/// of monthly spend, and a share list folded to fit a donut.
///
/// Pure functions in the kit rather than in the view model, because every one
/// of these is an off-by-one waiting to happen (week boundaries, an empty
/// month in the middle of a run, the "Other" slice) and the app target has no
/// tests. Callers filter to the rows they mean first; these only know an
/// amount and a date.
public enum SpendSeries {

    public struct Line: Equatable, Sendable {
        public let amount: Double
        public let date: Date

        public init(amount: Double, date: Date) {
            self.amount = amount
            self.date = date
        }
    }

    public struct DayTotal: Equatable, Sendable, Identifiable {
        public let date: Date
        /// Positive: money that left that day.
        public let amount: Double
        /// After the day the series was asked for. Drawn as an empty track,
        /// never as a zero, because nothing has happened there yet.
        public let isFuture: Bool

        public var id: Date { date }
    }

    public struct MonthTotal: Equatable, Sendable, Identifiable {
        public let monthStart: Date
        public let amount: Double

        public var id: Date { monthStart }
    }

    public struct Share: Equatable, Sendable {
        public let name: String
        public let amount: Double

        public init(name: String, amount: Double) {
            self.name = name
            self.amount = amount
        }
    }

    /// Seven days from the calendar's first weekday, each holding the outflows
    /// dated that day. Income and anything outside the week are ignored.
    public static func week(of date: Date, lines: [Line], calendar: Calendar) -> [DayTotal] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let today = calendar.startOfDay(for: date)

        var byDay: [Date: Double] = [:]
        for line in lines where line.amount < 0 {
            let day = calendar.startOfDay(for: line.date)
            guard day >= interval.start, day < interval.end else { continue }
            byDay[day, default: 0] += -line.amount
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }
            return DayTotal(date: day, amount: byDay[day] ?? 0, isFuture: day > today)
        }
    }

    /// `count` months ending with the month containing `date`, oldest first.
    /// A month with nothing spent is present at zero: a missing bucket would
    /// shift every later bar one slot left.
    public static func months(
        endingIn date: Date, count: Int, lines: [Line], calendar: Calendar
    ) -> [MonthTotal] {
        guard count > 0, let current = calendar.dateInterval(of: .month, for: date) else { return [] }

        let starts: [Date] = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: current.start)
        }
        guard let windowStart = starts.first else { return [] }

        var byMonth: [Date: Double] = [:]
        for line in lines where line.amount < 0 {
            guard line.date >= windowStart, line.date < current.end,
                  let month = calendar.dateInterval(of: .month, for: line.date)?.start
            else { continue }
            byMonth[month, default: 0] += -line.amount
        }

        return starts.map { MonthTotal(monthStart: $0, amount: byMonth[$0] ?? 0) }
    }

    /// The `keep` largest shares, then everything else summed as "Other".
    /// A list that would fold a single share is returned whole: an "Other"
    /// holding one category is that category with the wrong name.
    public static func fold(_ shares: [Share], keep: Int) -> [Share] {
        let sorted = shares.sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
        guard sorted.count > keep + 1 else { return sorted }
        let head = Array(sorted.prefix(keep))
        let rest = sorted.dropFirst(keep).reduce(0) { $0 + $1.amount }
        return head + [Share(name: "Other", amount: rest)]
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd LifeOSKit && swift test --filter SpendSeriesTests`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/SpendSeries.swift LifeOSKit/Tests/InsightsTests/SpendSeriesTests.swift
git commit -m "feat(money): bucket spend by week and by month, and fold shares for a donut

Pure series maths for the three Money charts, in the kit where the week
boundary, the empty middle month and the Other slice can be tested."
```

---

### Task 4: View rows, cents, and the derived series in the view model

**Files:**
- Modify: `LIfeOS/Features/Money/Model/MoneySnapshot.swift`
- Modify: `LIfeOS/Features/Money/Model/SampleMoneyData.swift`
- Modify: `LIfeOS/Features/Money/View/MoneyPalette.swift:79-107` (`MoneyFigure`)
- Modify: `LIfeOS/Features/Money/View/MoneyScreen.swift:186-193` (`money(_:)`)
- Modify: `LIfeOS/Features/Money/ViewModel/MoneyViewModel.swift`

**Interfaces:**
- Consumes: `MoneyEntry.logoURL`, `MoneyEntry.isSpending`, `SpendSeries`.
- Produces:
  - `MoneyRow(id:merchant:category:amount:date:pending:logoURL:accountName:)`
  - `CategoryRow(id:name:amount:share:count:)`
  - `RecurringRow(id:merchant:category:amount:months:logoURL:)`
  - `DaySpend { id: Date; date; amount; isFuture; isToday }`
  - `CategorySlice { id: String; name; amount; share; opacity: Double; isOther }`
  - `MoneySnapshot.week: [DaySpend]`, `MoneySnapshot.slices: [CategorySlice]`, `MoneySnapshot.spendCount: Int`
  - `MoneyViewModel.logoMap(from:) -> [String: URL]`, `MoneyViewModel.rows(from:logos:) -> [MoneyRow]`, `MoneyViewModel.week(from:now:calendar:)`, `MoneyViewModel.slices(from:)`
  - `MoneySnapshot.spendCount`

- [ ] **Step 1: Extend the rows**

`MoneySnapshot.swift`:

```swift
struct MoneyRow: Equatable, Identifiable {
    let id: UUID
    let merchant: String
    let category: String?
    let amount: Double
    let date: Date
    let pending: Bool
    /// The merchant's mark, from Plaid or borrowed from a sibling row for the
    /// same merchant. Nil shows the category glyph.
    var logoURL: URL? = nil
    var accountName: String? = nil
}
```

`CategoryRow` gains `let count: Int` after `share`. `RecurringRow` gains `var logoURL: URL? = nil` at the end.

Add after `PressurePoint`:

```swift
/// One day of the current week, for the seven-bar chart.
struct DaySpend: Equatable, Identifiable {
    let date: Date
    let amount: Double
    let isFuture: Bool
    let isToday: Bool

    var id: Date { date }
}

/// One slice of the donut. At most five categories and an "Other".
struct CategorySlice: Equatable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    let share: Double
    /// Ink opacity for the slice and for the swatch on the band that names it.
    /// Largest slice darkest: the donut is a magnitude, not a set of
    /// identities, and the money palette has one ink.
    let opacity: Double
    let isOther: Bool

    /// The opacity steps, largest slice first. Six, because `fold` keeps five
    /// and adds one.
    static let steps: [Double] = [0.92, 0.72, 0.54, 0.40, 0.28, 0.16]
}
```

On `MoneySnapshot`, after `recurring`:

```swift
    /// This week, Monday to Sunday (or the calendar's own first day).
    var week: [DaySpend] = []
    /// Category shares folded for the donut.
    var slices: [CategorySlice] = []
    /// How many charges make up `expenses`.
    var spendCount: Int = 0
```

- [ ] **Step 2: Cents in `MoneyFigure` and the helper**

Replace the body of `MoneyFigure`:

```swift
    var body: some View {
        // Round to cents FIRST, then split. Splitting before rounding lets
        // .995 carry into a fraction of 100 and render as "$19.100". Money
        // that displays as the wrong number is the worst bug this screen
        // could have, so the arithmetic is done in the order that carries.
        let magnitude = (abs(amount) * 100).rounded() / 100
        let whole = Int(magnitude)
        let cents = Int(((magnitude - Double(whole)) * 100).rounded())
        let sign = showsSign ? (amount < 0 ? "-" : "+") : ""

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(sign)$\(whole.formatted(.number.grouping(.automatic)))")
            Text(".\(cents < 10 ? "0" : "")\(cents)")
                .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.35))
        }
        .font(LifeOSType.numeral(size))
        .monospacedDigit()
        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
```

Update the doc comment above it from `$1,894.0` to `$1,894.00`. In `MoneyScreen.money(_:)` and `signed(_:)`, change `.precision(.fractionLength(0))` to `.precision(.fractionLength(2))`.

- [ ] **Step 3: Derive everything in the view model**

In `MoneyViewModel.load`, replace the `recent:` and `categories:` arguments and add the new ones:

```swift
            let logos = Self.logoMap(from: entries)
            let rows = Self.rows(from: entries, logos: logos)
            let categories = Self.categories(from: entries, expenses: summary.expenses)
```

then in the `MoneySnapshot(` initialiser:

```swift
                recent: rows,
                budgets: budgetRows,
                unclaimed: unclaimedRows,
                categories: categories,
                recurring: Self.recurring(from: entries, calendar: calendar, logos: logos),
                week: Self.week(from: entries, now: .now, calendar: calendar),
                slices: Self.slices(from: categories),
                spendCount: entries.filter(\.isSpending).count,
```

Replace `categories(from:expenses:)` and `recurring(from:calendar:)` and add the helpers:

```swift
    /// Spending grouped by category, largest first.
    ///
    /// Built from `isSpending` only, the same predicate as `summarise`, so
    /// the list sums to the "Spent" figure above it. Uncategorised spend is
    /// kept rather than dropped for the same reason: the gap is exactly the
    /// spend nobody has labelled.
    static func categories(from entries: [MoneyEntry], expenses: Double) -> [CategoryRow] {
        guard expenses > 0 else { return [] }
        let grouped = Dictionary(grouping: entries.filter(\.isSpending)) { $0.category ?? "Uncategorised" }

        return grouped.map { name, rows in
            let amount = rows.reduce(0) { $0 + abs($1.amount) }
            return CategoryRow(id: name, name: name, amount: amount,
                               share: amount / expenses, count: rows.count)
        }
        .sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
    }

    /// Merchants billing every month, detected from history by `RecurringSpend`.
    static func recurring(from entries: [MoneyEntry], calendar: Calendar,
                          logos: [String: URL] = [:]) -> [RecurringRow] {
        let lines = entries.map {
            RecurringSpend.Line(merchant: $0.merchant, category: $0.category,
                                amount: $0.amount, date: $0.date)
        }
        return RecurringSpend.charges(in: lines, calendar: calendar).map {
            RecurringRow(id: $0.merchant, merchant: $0.merchant, category: $0.category,
                         amount: $0.typicalAmount, months: $0.months,
                         logoURL: logos[Self.logoKey(merchant: $0.merchant)])
        }
    }

    /// Every logo in the window, keyed twice: by merchant entity where Plaid
    /// gave one, and by lowercased merchant name always. A row Plaid sent
    /// without a logo borrows from any sibling that has one; a manual "Netflix"
    /// picks up the mark from the Plaid rows. A borrowed logo never changes
    /// grouping: it is a picture beside a name, not an identity.
    static func logoMap(from entries: [MoneyEntry]) -> [String: URL] {
        var map: [String: URL] = [:]
        for entry in entries {
            guard let raw = entry.logoURL, let url = URL(string: raw) else { continue }
            if let id = entry.merchantID { map["id:\(id)"] = map["id:\(id)"] ?? url }
            let key = Self.logoKey(merchant: entry.merchant)
            map[key] = map[key] ?? url
        }
        return map
    }

    static func logoKey(merchant: String) -> String {
        "name:" + merchant.lowercased().trimmingCharacters(in: .whitespaces)
    }

    static func logo(for entry: MoneyEntry, in logos: [String: URL]) -> URL? {
        if let raw = entry.logoURL, let url = URL(string: raw) { return url }
        if let id = entry.merchantID, let url = logos["id:\(id)"] { return url }
        return logos[Self.logoKey(merchant: entry.merchant)]
    }

    static func rows(from entries: [MoneyEntry], logos: [String: URL]) -> [MoneyRow] {
        entries.map {
            MoneyRow(id: $0.id, merchant: $0.merchant, category: $0.category,
                     amount: $0.amount, date: $0.date, pending: $0.pending,
                     logoURL: Self.logo(for: $0, in: logos), accountName: $0.accountName)
        }
    }

    static func week(from entries: [MoneyEntry], now: Date, calendar: Calendar) -> [DaySpend] {
        let today = calendar.startOfDay(for: now)
        let lines = entries.filter(\.isSpending).map { SpendSeries.Line(amount: $0.amount, date: $0.date) }
        return SpendSeries.week(of: now, lines: lines, calendar: calendar).map {
            DaySpend(date: $0.date, amount: $0.amount, isFuture: $0.isFuture,
                     isToday: calendar.isDate($0.date, inSameDayAs: today))
        }
    }

    /// The donut: five largest categories and an "Other", each with its ink
    /// step. Shares are of the full month, so the slices still sum to one.
    static func slices(from categories: [CategoryRow]) -> [CategorySlice] {
        let total = categories.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        let folded = SpendSeries.fold(
            categories.map { SpendSeries.Share(name: $0.name, amount: $0.amount) }, keep: 5
        )
        return folded.enumerated().map { index, share in
            CategorySlice(id: share.name, name: share.name, amount: share.amount,
                          share: share.amount / total,
                          opacity: CategorySlice.steps[min(index, CategorySlice.steps.count - 1)],
                          isOther: share.name == "Other" && !categories.contains { $0.name == "Other" })
        }
    }
```

Note the `week` from the month's entries: the week can begin in the previous month, and those days will read zero. Accept that here; `monthEntries` is what the tab loads, and a week straddling the first of the month is six days a year.

- [ ] **Step 4: Bring the sample data along**

In `SampleMoneyData.swift`, the `MoneySnapshot(` call gains, after `recurring: sampleRecurring,`:

```swift
            week: sampleWeek,
            slices: MoneyViewModel.slices(from: sampleCategories),
            spendCount: 23,
```

Change `sampleCategories` parts to carry counts and `CategoryRow(id: $0.0, name: $0.0, amount: $0.1, share: $0.1 / total, count: $0.2)`:

```swift
        let parts: [(String, Double, Int)] = [
            ("Rent", 1_850.00, 1),
            ("Groceries", 412.87, 6),
            ("Transport", 163.15, 5),
            ("Eating out", 238.40, 4),
            ("Subscriptions", 47.97, 3),
            ("Health", 128.00, 1),
            ("Uncategorised", 1_591.19, 3),
        ]
```

Add:

```swift
    /// A week with a clear peak and today somewhere in the middle, so the
    /// chart's three states (past, today, still to come) are all visible.
    private static var sampleWeek: [DaySpend] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let amounts: [Double] = [42.10, 118.40, 12.99, 86.31, 27.85, 64.00, 0]
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }
            let isFuture = day > today
            return DaySpend(date: day, amount: isFuture ? 0 : amounts[offset],
                            isFuture: isFuture, isToday: day == today)
        }
    }
```

Give the sample rows `accountName`: add `accountName: "Checking"` to the `MoneyRow(` construction in `sampleRows`, and add four more rows so the ledger has more than one day's worth:

```swift
            ("Netflix",            "Entertainment",    -19.99, 9, false),
            ("Amazon",             "Shopping",         -64.20, 10, false),
            ("Shell",              "Transport",        -48.00, 12, false),
            ("Sweetgreen",         "Dining",           -15.75, 12, false),
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | grep -E "error:|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Money
git commit -m "feat(money): carry cents, logos, accounts and the chart series on the snapshot

MoneyFigure rounds to the cent before splitting. Rows carry the logo and
account, categories carry a count, and the view model derives the week
series and the donut slices from the same month it already loads."
```

---

### Task 5: The merchant tile and the tappable ledger and recurring rows

**Files:**
- Create: `LIfeOS/Features/Money/View/MerchantTile.swift`
- Modify: `LIfeOS/Features/Money/View/MoneySections.swift:137-197, 332-403`
- Modify: `LIfeOS/Features/Money/View/MoneyScreen.swift` (add `onOpen`)

**Interfaces:**
- Produces: `MerchantTile(logoURL:glyph:size:)`, `MoneyDetailFilter` (enum, `Hashable`, `Identifiable`), `MoneyTransactionRow(row:onOpen:)`, `MoneyDayGroup.group(_:calendar:) -> [(label: String, rows: [MoneyRow])]`, `MoneyScreen.onOpen: (MoneyDetailFilter) -> Void`, `MoneyRecurringSection.onOpen`, `MoneyLedgerSection.onOpen`.

- [ ] **Step 1: The filter type and the tile**

`MerchantTile.swift`:

```swift
import SwiftUI
import DesignSystem

/// What a detail page is about. A category page and a merchant page are the
/// same page with a different predicate, so one type carries both.
enum MoneyDetailFilter: Hashable, Identifiable {
    case category(String)
    case merchant(String)

    var id: String {
        switch self {
        case .category(let name): "category:\(name)"
        case .merchant(let name): "merchant:\(name)"
        }
    }

    var title: String {
        switch self {
        case .category(let name), .merchant(let name): name
        }
    }
}

/// The mark beside a merchant: Plaid's logo in a paper-white circle, or the
/// category glyph when there is none.
///
/// A white circle on every band rather than the logo bare, because Plaid's
/// PNGs come on whatever background the merchant chose and a row of mixed
/// squares breaks the band. The circle also gives the glyph fallback the
/// same footprint, so a list with and without logos lines up.
struct MerchantTile: View {
    let logoURL: URL?
    let glyph: String
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(MoneyPalette.paper.resolve(scheme))
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(MoneyPalette.ink.resolve(scheme).opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: glyph)
            .font(LifeOSType.label.weight(.semibold))
            .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.75))
    }
}

/// One transaction, as the ledger and the detail page both draw it.
struct MoneyTransactionRow: View {
    let row: MoneyRow
    var onOpen: ((MoneyDetailFilter) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let onOpen {
            Button { onOpen(.merchant(row.merchant)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every charge from \(row.merchant)")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Space.x2 - 4) {
            MerchantTile(logoURL: row.logoURL, glyph: MoneyLedgerSection.glyph(for: row.category))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.merchant)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    .lineLimit(1)
                Text(detail).moneyEyebrow(scheme).lineLimit(1)
            }
            Spacer(minLength: Space.x1)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyFigure(amount: row.amount, size: 18, showsSign: true)
                    .opacity(row.pending ? 0.45 : 1)
                if row.pending {
                    Text("Pending").moneyEyebrow(scheme)
                }
            }
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x1 + 2)
        .frame(maxWidth: .infinity)
        .background(MoneyPalette.stone.resolve(scheme))
        .contentShape(Rectangle())
    }

    private var detail: String {
        [row.category ?? "Uncategorised", row.accountName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Rows grouped by day, most recent day first, with the label the header
/// shows: "Today", "Yesterday", then the weekday and date.
enum MoneyDayGroup {
    static func group(_ rows: [MoneyRow], calendar: Calendar = .current,
                      now: Date = .now) -> [(label: String, rows: [MoneyRow])] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let label: String
            if day == today {
                label = "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      day == yesterday {
                label = "Yesterday"
            } else {
                label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return (label, grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}
```

- [ ] **Step 2: Rewrite the ledger section**

Replace `MoneyLedgerSection.body` in `MoneySections.swift` (keep `glyph(for:)`):

```swift
struct MoneyLedgerSection: View {
    let snapshot: MoneySnapshot
    var onAdd: () -> Void = {}
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.stone) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(snapshot.monthLabel)").moneyEyebrow(scheme)
                        Text("\(snapshot.recent.count) transactions")
                            .font(LifeOSType.sectionTitle.weight(.bold))
                            .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    }
                    Spacer()
                    Button("Add", action: onAdd)
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                }
            }

            if snapshot.recent.isEmpty {
                MoneyEmptyBand(tone: MoneyPalette.mist, line: "Nothing logged this month yet.")
            } else {
                ForEach(MoneyDayGroup.group(snapshot.recent), id: \.label) { day in
                    Text(day.label)
                        .moneyEyebrow(scheme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.x2)
                        .padding(.top, Space.x2)
                        .padding(.bottom, Space.half)
                        .background(MoneyPalette.stone.resolve(scheme))
                    ForEach(day.rows) { row in
                        MoneyTransactionRow(row: row, onOpen: onOpen)
                    }
                }
                Color.clear.frame(height: Space.x1).background(MoneyPalette.stone.resolve(scheme))
            }
        }
    }
```

- [ ] **Step 3: Recurring rows get the tile and a tap**

`MoneyRecurringSection` gains `var onOpen: (MoneyDetailFilter) -> Void = { _ in }`. Replace the `ForEach(snapshot.recurring)` body:

```swift
                ForEach(snapshot.recurring) { row in
                    Button { onOpen(.merchant(row.merchant)) } label: {
                        MoneyBand(tone: MoneyPalette.stone) {
                            HStack(spacing: Space.x2 - 4) {
                                MerchantTile(logoURL: row.logoURL,
                                             glyph: MoneyLedgerSection.glyph(for: row.category))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.merchant)
                                        .font(LifeOSType.body.weight(.semibold))
                                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                        .lineLimit(1)
                                    Text(row.category ?? "Uncategorised")
                                        .moneyEyebrow(scheme)
                                }
                                Spacer(minLength: Space.x1)
                                VStack(alignment: .trailing, spacing: 2) {
                                    MoneyFigure(amount: row.amount, size: 20)
                                    Text("\(row.months) months")
                                        .font(LifeOSType.eyebrow.weight(.regular))
                                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                                }
                                Image(systemName: "chevron.right")
                                    .font(LifeOSType.caption.weight(.semibold))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens every charge from \(row.merchant)")
                }
```

- [ ] **Step 4: Thread `onOpen` through the screen**

`MoneyScreen` gains `var onOpen: (MoneyDetailFilter) -> Void = { _ in }` after `onEditBudgets`, and passes it: `MoneyRecurringSection(snapshot: snapshot, onOpen: onOpen)` and `MoneyLedgerSection(snapshot: snapshot, onAdd: onAdd, onOpen: onOpen)`. Update the doc comment in `RootView` at the `.money` case (Task 7 wires the destination).

- [ ] **Step 5: Build**

Run the xcodebuild command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Money
git commit -m "feat(money): show the whole month by day, with a merchant mark on every row

The ledger was eight rows with no date. It is now the month grouped by
day, each row carrying the Plaid logo (or the category glyph), the
account, and a tap that opens the merchant. Recurring rows get the same."
```

---

### Task 6: The three charts

**Files:**
- Create: `LIfeOS/Features/Money/View/MoneyCharts.swift`
- Modify: `LIfeOS/Features/Money/View/MoneySections.swift:37-133` (`MoneyFlowSection`, `MoneyCategoriesSection`)

**Interfaces:**
- Produces: `MoneyWeekChart(days:)`, `MoneyDonut(slices:onSelect:)`, `MoneyMonthsChart(months:average:)` where `MonthSpend { id: Date; monthStart; amount; isCurrent }` is defined here and reused by Task 7.
- `MoneyCategoriesSection.onOpen`.

- [ ] **Step 1: Write the charts**

```swift
import SwiftUI
import Charts
import DesignSystem

/// The three Money charts. One ink at stepped opacity, no y-axis, no grid:
/// the figure above each chart is the number, the marks are the shape. A
/// pastel categorical palette was run through the dataviz validator and
/// failed every check, which is the long way of saying what the one-ink rule
/// already said.

// MARK: - This week

struct MoneyWeekChart: View {
    let days: [DaySpend]
    var height: CGFloat = 110
    @Environment(\.colorScheme) private var scheme

    private var peak: Double { max(days.map(\.amount).max() ?? 0, 1) }

    var body: some View {
        Chart(days) { day in
            // An empty track for every day, so a day still to come is
            // visibly a slot and not a gap.
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Track", peak))
                .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.07))
                .cornerRadius(4)

            if !day.isFuture {
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Spent", day.amount))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(day.isToday ? 1 : 0.32))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if day.isToday, day.amount > 0 {
                            Text(day.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(LifeOSType.eyebrow.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        }
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(peak * 1.25))
        .chartXAxis {
            AxisMarks(values: days.map(\.date)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(LifeOSType.eyebrow)
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("Spending this week by day")
    }
}

// MARK: - Where it went

struct MoneyDonut: View {
    let slices: [CategorySlice]
    var onSelect: (CategorySlice) -> Void = { _ in }
    var size: CGFloat = 128
    @Environment(\.colorScheme) private var scheme
    @State private var selectedAmount: Double?

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Share", slice.amount),
                innerRadius: .ratio(0.62),
                // The 2pt paper gap between fills, so two adjacent steps of
                // the same ink read as two slices and not a gradient.
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(slice.opacity))
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAmount)
        .onChange(of: selectedAmount) { _, amount in
            guard let amount, let slice = slice(at: amount) else { return }
            selectedAmount = nil
            if !slice.isOther { onSelect(slice) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Spending by category")
        .accessibilityValue(slices.map { "\($0.name) \(Int($0.share * 100)) percent" }.joined(separator: ", "))
    }

    /// `chartAngleSelection` reports a position along the cumulative angle
    /// value, in the data's own units. Walk the slices until it is passed.
    private func slice(at amount: Double) -> CategorySlice? {
        var running = 0.0
        for slice in slices {
            running += slice.amount
            if amount <= running { return slice }
        }
        return slices.last
    }
}

// MARK: - Six months

struct MonthSpend: Equatable, Identifiable {
    let monthStart: Date
    let amount: Double
    let isCurrent: Bool

    var id: Date { monthStart }
}

struct MoneyMonthsChart: View {
    let months: [MonthSpend]
    /// Across the completed months. Nil until there is one.
    let average: Double?
    var height: CGFloat = 140
    @Environment(\.colorScheme) private var scheme

    private var peak: Double { max(months.map(\.amount).max() ?? 0, average ?? 0, 1) }

    var body: some View {
        Chart {
            ForEach(months) { month in
                BarMark(x: .value("Month", month.monthStart, unit: .month),
                        y: .value("Spent", month.amount))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(month.isCurrent ? 1 : 0.32))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if month.isCurrent {
                            Text(month.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(LifeOSType.eyebrow.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        }
                    }
            }
            if let average, average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.4))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(peak * 1.25))
        .chartXAxis {
            AxisMarks(values: months.map(\.monthStart)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .font(LifeOSType.eyebrow)
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("Spending over the last six months")
    }
}
```

- [ ] **Step 2: The week band on "In and out"**

In `MoneyFlowSection.body`, after the `Spent` band and before the `Kept` band:

```swift
            if !snapshot.week.isEmpty {
                MoneyBand(tone: MoneyPalette.stone) {
                    Text("This week").moneyEyebrow(scheme)
                    MoneyFigure(amount: snapshot.week.reduce(0) { $0 + $1.amount }, size: 28)
                    MoneyWeekChart(days: snapshot.week)
                        .padding(.top, Space.half)
                }
            }
```

- [ ] **Step 3: The donut and the tappable category bands**

Replace `MoneyCategoriesSection`:

```swift
struct MoneyCategoriesSection: View {
    let snapshot: MoneySnapshot
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.mist) {
                HStack(alignment: .center, spacing: Space.x2) {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("Spent · \(snapshot.monthLabel)").moneyEyebrow(scheme)
                        MoneyFigure(amount: snapshot.expenses, size: 34)
                        Text("\(snapshot.spendCount) transaction\(snapshot.spendCount == 1 ? "" : "s")")
                            .font(LifeOSType.label.weight(.semibold))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                    Spacer(minLength: 0)
                    if !snapshot.slices.isEmpty {
                        MoneyDonut(slices: snapshot.slices) { onOpen(.category($0.name)) }
                    }
                }
            }

            if snapshot.categories.isEmpty {
                MoneyEmptyBand(
                    tone: MoneyPalette.stone,
                    line: "Nothing categorised yet. Categories appear once transactions carry one."
                )
            } else {
                ForEach(snapshot.categories) { row in
                    Button { onOpen(.category(row.name)) } label: {
                        MoneyBand(tone: MoneyPalette.stone) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                                if let opacity = swatchOpacity(for: row) {
                                    Circle()
                                        .fill(MoneyPalette.ink.resolve(scheme).opacity(opacity))
                                        .frame(width: 10, height: 10)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                }
                                Text(row.name)
                                    .font(LifeOSType.body.weight(.semibold))
                                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                Text("\(row.count)")
                                    .font(LifeOSType.eyebrow.weight(.regular))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                                Spacer(minLength: Space.x1)
                                MoneyFigure(amount: row.amount, size: 20)
                                Image(systemName: "chevron.right")
                                    .font(LifeOSType.caption.weight(.semibold))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                            }
                            Pinstripes(fraction: row.share)
                                .frame(height: 18)
                            Text("\(Int((row.share * 100).rounded()))% of spending")
                                .font(LifeOSType.eyebrow.weight(.regular))
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens every charge in \(row.name)")
                }
            }
        }
    }

    /// The band's swatch matches its slice. A category folded into "Other"
    /// has no slice of its own and gets no swatch.
    private func swatchOpacity(for row: CategoryRow) -> Double? {
        snapshot.slices.first { $0.name == row.name && !$0.isOther }?.opacity
    }
}
```

Pass `onOpen` from `MoneyScreen`: `MoneyCategoriesSection(snapshot: snapshot, onOpen: onOpen)`.

- [ ] **Step 4: Build**

Run the xcodebuild command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Money
git commit -m "feat(money): draw the week, the category donut and the six-month trend

Three Swift Charts in one ink at stepped opacity. The donut folds to five
categories and Other, each band below carries the matching swatch, and a
slice or a band opens the category."
```

---

### Task 7: The detail page and its wiring

**Files:**
- Create: `LIfeOS/Features/Money/Model/MoneyDetailSnapshot.swift`
- Create: `LIfeOS/Features/Money/ViewModel/MoneyDetailViewModel.swift`
- Create: `LIfeOS/Features/Money/View/MoneyDetailScreen.swift`
- Modify: `LIfeOS/App/RootView.swift:51, 419-432, 622, 709`

**Interfaces:**
- Consumes: `MoneyDetailFilter`, `MoneyRow`, `MonthSpend`, `MoneyTransactionRow`, `MoneyMonthsChart`, `MerchantTile`, `MoneyDayGroup`, `MoneyViewModel.logoMap/rows`, `SpendSeries.months`.
- Produces: `MoneyDetailViewModel.attach(_:)`, `.load(_ filter: MoneyDetailFilter, now:)`, `.snapshot: MoneyDetailSnapshot`.

- [ ] **Step 1: The snapshot**

```swift
import Foundation

/// One category or one merchant, on a page of its own.
struct MoneyDetailSnapshot: Equatable {
    var filter: MoneyDetailFilter?
    var logoURL: URL?
    var category: String?
    var monthTotal: Double = 0
    var monthCount: Int = 0
    /// Six months, oldest first, the last one current.
    var months: [MonthSpend] = []
    /// Mean of the completed months that had anything. Nil until one has.
    var average: Double?
    /// This month's matching rows, most recent first.
    var transactions: [MoneyRow] = []
    var monthLabel: String = ""
}
```

- [ ] **Step 2: The view model**

```swift
import Foundation
import SwiftData
import Persistence
import Insights

/// Six months of one category or one merchant.
///
/// Its own view model rather than more fields on `MoneyViewModel`, which
/// loads one month on every save in the app. Six months of rows for a page
/// nobody is looking at is the kind of work that makes a tab feel slow.
@MainActor @Observable
final class MoneyDetailViewModel {
    private(set) var snapshot = MoneyDetailSnapshot()

    private var context: ModelContext?
    private let calendar: Calendar

    static let monthCount = 6

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load(_ filter: MoneyDetailFilter, now: Date = .now) {
        guard let context,
              let month = calendar.dateInterval(of: .month, for: now),
              let start = calendar.date(byAdding: .month, value: -(Self.monthCount - 1), to: month.start)
        else { return }
        let store = MoneyStore(context: context, calendar: calendar)

        do {
            let all = try store.entries(from: start, to: now)
            let logos = MoneyViewModel.logoMap(from: all)
            let matching = all.filter { Self.matches($0, filter) }
            let spend = matching.filter(\.isSpending)
            let thisMonth = matching.filter { $0.date >= month.start }

            let months = SpendSeries.months(
                endingIn: now, count: Self.monthCount,
                lines: spend.map { SpendSeries.Line(amount: $0.amount, date: $0.date) },
                calendar: calendar
            )
            let completed = months.dropLast().map(\.amount).filter { $0 > 0 }

            snapshot = MoneyDetailSnapshot(
                filter: filter,
                logoURL: matching.lazy.compactMap { MoneyViewModel.logo(for: $0, in: logos) }.first,
                category: thisMonth.first?.category ?? matching.first?.category,
                monthTotal: spend.filter { $0.date >= month.start }.reduce(0) { $0 + abs($1.amount) },
                monthCount: spend.filter { $0.date >= month.start }.count,
                months: months.enumerated().map { index, total in
                    MonthSpend(monthStart: total.monthStart, amount: total.amount,
                               isCurrent: index == months.count - 1)
                },
                average: completed.isEmpty ? nil : completed.reduce(0, +) / Double(completed.count),
                transactions: MoneyViewModel.rows(from: thisMonth, logos: logos),
                monthLabel: now.formatted(.dateTime.month(.wide).year())
            )
        } catch {
            assertionFailure("Money detail load failed: \(error)")
        }
    }

    /// A category page matches on the display label the list was grouped by,
    /// so "Uncategorised" opens the rows with no category. A merchant page
    /// matches the name, case-insensitively, since the ledger showed it.
    static func matches(_ entry: MoneyEntry, _ filter: MoneyDetailFilter) -> Bool {
        switch filter {
        case .category(let name):
            (entry.category ?? "Uncategorised") == name && entry.amount < 0
        case .merchant(let name):
            entry.merchant.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
```

- [ ] **Step 3: The screen**

```swift
import SwiftUI
import DesignSystem

/// One category or one merchant: what it cost this month, the six months
/// behind that, and every charge that makes it up.
///
/// Pushed from a category band, a donut slice, a recurring row or a ledger
/// row. Same bands as the tab it came from, so the push reads as the same
/// object opening rather than as arriving somewhere new.
struct MoneyDetailScreen: View {
    let filter: MoneyDetailFilter
    @Bindable var model: MoneyDetailViewModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    private var snapshot: MoneyDetailSnapshot { model.snapshot }

    private var tone: AdaptiveColor {
        switch filter {
        case .category: MoneyPalette.mist
        case .merchant: MoneyPalette.mint
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headline
                trend
                transactions
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .background(MoneyPalette.paper.resolve(scheme).ignoresSafeArea())
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.load(filter) }
    }

    private var headline: some View {
        MoneyBand(tone: tone) {
            HStack(spacing: Space.x2 - 4) {
                MerchantTile(logoURL: snapshot.logoURL,
                             glyph: MoneyLedgerSection.glyph(for: snapshot.category),
                             size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.title)
                        .font(LifeOSType.sectionTitle.weight(.bold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        .lineLimit(2)
                    if case .merchant = filter, let category = snapshot.category {
                        Text(category).moneyEyebrow(scheme)
                    }
                }
            }
            Text("This month").moneyEyebrow(scheme).padding(.top, Space.x1)
            MoneyFigure(amount: snapshot.monthTotal, size: 46)
            Text(snapshot.monthCount == 0
                 ? "Nothing in \(snapshot.monthLabel)"
                 : "\(snapshot.monthCount) charge\(snapshot.monthCount == 1 ? "" : "s") in \(snapshot.monthLabel)")
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(MoneyPalette.quietInk(scheme))
        }
    }

    private var trend: some View {
        MoneyBand(tone: MoneyPalette.stone) {
            Text("Six months").moneyEyebrow(scheme)
            MoneyMonthsChart(months: snapshot.months, average: snapshot.average)
                .padding(.top, Space.half)
            if let average = snapshot.average {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Averages")
                    MoneyFigure(amount: average, size: 15)
                    Text("a month before this one")
                }
                .font(LifeOSType.caption)
                .foregroundStyle(MoneyPalette.quietInk(scheme))
            } else {
                Text("First month with anything here")
                    .font(LifeOSType.caption)
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }
        }
    }

    @ViewBuilder
    private var transactions: some View {
        if snapshot.transactions.isEmpty {
            MoneyEmptyBand(tone: MoneyPalette.stone, line: "Nothing this month.")
        } else {
            ForEach(MoneyDayGroup.group(snapshot.transactions), id: \.label) { day in
                Text(day.label)
                    .moneyEyebrow(scheme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.x2)
                    .padding(.top, Space.x2)
                    .padding(.bottom, Space.half)
                    .background(MoneyPalette.stone.resolve(scheme))
                ForEach(day.rows) { row in
                    // No tap: a merchant page opening a merchant page is a loop.
                    // A category page could open a merchant, but two depths of
                    // the same list is one more than anyone asked for.
                    MoneyTransactionRow(row: row)
                }
            }
            Color.clear.frame(height: Space.x1).background(MoneyPalette.stone.resolve(scheme))
        }
    }
}
```

- [ ] **Step 4: Wire it in `RootView`**

After `@State private var money = MoneyViewModel()` (line 51):

```swift
    @State private var moneyDetail = MoneyDetailViewModel()
    @State private var openMoney: MoneyDetailFilter?
```

Replace the `.money` case:

```swift
            case .money:
                // Wrapped here rather than in `MoneyScreen`: the stack carries
                // the bar the actions live in and the detail page a category
                // or merchant opens onto.
                NavigationStack {
                    MoneyScreen(
                        snapshot: money.snapshot,
                        onAdd: { showAddMoney = true },
                        onConnect: { plaid.connect() },
                        onSync: { Task { await plaid.sync(); money.load(connection: plaid) } },
                        onEditBudgets: { showBudgets = true },
                        onOpen: { openMoney = $0 }
                    )
                    .quickActionsToolbar()
                    .navigationDestination(item: $openMoney) { filter in
                        MoneyDetailScreen(filter: filter, model: moneyDetail)
                    }
                }
```

After `money.attach(context)` (line 622): `moneyDetail.attach(context)`.

In `reloadAll`, after `money.load(connection: plaid)` (line 714):

```swift
        if let openMoney { moneyDetail.load(openMoney) }
```

and the same line again inside the `Task` after the second `money.load(connection: plaid)`.

- [ ] **Step 5: Build**

Run the xcodebuild command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Money LIfeOS/App/RootView.swift
git commit -m "feat(money): open a category or a merchant on a page of its own

The month total, six months of history and every matching charge, pushed
on the Money tab's stack from a band, a slice, a recurring row or a ledger
row. Its own view model, since six months is not something the tab
should load on every save."
```

---

### Task 8: Replay history once so old rows gain their logo

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/PlaidItemStore.swift` (add `resetCursors()` to the protocol and store)
- Modify: `LIfeOS/Features/Settings/ViewModel/PlaidConnectionViewModel.swift` (around `init` and `syncIfDue`)
- Test: `LifeOSKit/Tests/IntegrationsTests/PlaidItemStoreTests.swift`

**Interfaces:**
- Produces: `PlaidItemStoring.resetCursors()`, `PlaidConnectionViewModel.replayHistoryOnce(defaults:)`, `PlaidConnectionViewModel.logoReplayKey`.

- [ ] **Step 1: Write the failing test**

In `PlaidItemStoreTests.swift`, matching the file's existing helper for an isolated `UserDefaults` suite:

```swift
    @Test func resettingCursorsKeepsEveryItemAndForgetsWhereItWas() {
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "A", cursor: "c1"))
        store.upsert(PlaidStoredItem(itemID: "item_b", institutionName: "B", cursor: "c2"))

        store.resetCursors()

        let items = store.items()
        #expect(items.map(\.itemID) == ["item_a", "item_b"])
        #expect(items.allSatisfy { $0.cursor == nil })
    }
```

(If the file names its factory differently, use that name.)

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter PlaidItemStoreTests`
Expected: compile error, `resetCursors` not found.

- [ ] **Step 3: Implement**

Protocol: add `/// Forgets every cursor and keeps every item, so the next sync replays full history. func resetCursors()`.

Store:

```swift
    public func resetCursors() {
        lock.lock()
        defer { lock.unlock() }
        write(loadItems().map {
            PlaidStoredItem(itemID: $0.itemID, institutionName: $0.institutionName, cursor: nil)
        })
    }
```

Search the tests for any other `PlaidItemStoring` conformer (`grep -rn "PlaidItemStoring" LifeOSKit/Tests`) and add an empty `func resetCursors() {}` to each.

`PlaidConnectionViewModel`: add

```swift
    /// Rows synced before the logo field existed never get one, because
    /// `/transactions/sync` only re-sends what changed. Clearing every cursor
    /// once makes the next sync replay history through the same upsert, and
    /// the flag stops it happening again: a replay on every launch would pull
    /// years of rows daily.
    static let logoReplayKey = "plaid.logoReplayDone.v1"

    func replayHistoryOnce(defaults: UserDefaults = .currentAccount) {
        guard !defaults.bool(forKey: Self.logoReplayKey) else { return }
        items.resetCursors()
        defaults.set(true, forKey: Self.logoReplayKey)
    }
```

and call `replayHistoryOnce()` at the top of `syncIfDue()` before the staleness check, so the very next due sync starts from nothing. Read `syncIfDue` first: if it short-circuits when no item exists, the call still belongs before it (the flag is set with nothing to reset, which is correct for a fresh install).

- [ ] **Step 4: Run the tests and build**

Run: `cd LifeOSKit && swift test --filter Plaid` then the xcodebuild command.
Expected: pass, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit LIfeOS/Features/Settings
git commit -m "feat(money): replay bank history once so existing rows gain their logo

Sync only re-sends changed transactions. Clearing every item's cursor once,
behind a flag, lets the next sync run the whole history back through the
upsert, which is where the logo gets written."
```

---

### Task 9: Spec amendment, screenshots, full test run

**Files:**
- Modify: `docs/superpowers/specs/2026-09-01-money-inference-layer-design.md:125-134` (Section 6)

- [ ] **Step 1: Amend the earlier spec**

Append to Section 6:

```markdown
**Superseded 2026-09-01.** Merchant logos are in, by decision: see
`2026-09-01-money-detail-and-charts-design.md`, Section 3. The band vocabulary
grew the form this paragraph asked for (a paper-white circle inside the band),
and `logoURL` was added by the additive mechanism described above.
```

- [ ] **Step 2: Full kit test run**

Run: `cd LifeOSKit && swift test 2>&1 | tail -5`
Expected: all suites pass.

- [ ] **Step 3: Build, install and screenshot**

Boot the iPhone 17 (OS 26.0) simulator, install the Debug build, open the Money tab, and capture: Flow with the week chart, Spend with the donut, Recent grouped by day, and a category detail page. Light and dark. Follow `driving-lifeos-ios-simulator` from memory for tapping. Save screenshots to the scratchpad and put them in front of the user.

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs(money): record that merchant logos superseded the no-logo decision"
```
