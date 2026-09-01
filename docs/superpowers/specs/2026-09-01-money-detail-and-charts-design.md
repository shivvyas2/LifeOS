# Money: precision, logos, drill-down and charts

**Date:** 2026-09-01
**Status:** approved in conversation, implementing
**Builds on:** `2026-08-26-plaid-personal-finance-design.md`, `2026-09-01-money-inference-layer-design.md`

## 1. The problem

The Money tab renders figures a person cannot get behind. Four things make it
read as imprecise and confusing:

1. Nothing is tappable. A category band says "Food & drink $412" and there is
   no way to see the twelve charges that make it up. The Money tab is the only
   tab whose `NavigationStack` pushes nothing.
2. The ledger shows eight rows, with no date and no account, so "what did I
   actually spend" has no answer on the screen.
3. Every figure is rounded to one decimal. `$25.55` renders as `$25.5`, which
   is not the number on the bank statement.
4. Merchants are text only. A row that says "AMZN Mktp US" is slower to
   recognise than the Amazon mark, and there are no charts at all: the shape
   of the month is carried by hairline pinstripes.

Separately, the category rollup counts pending charges and credit card
payments, while the "Spent" figure above it excludes both. The parts do not
sum to the whole.

## 2. What this slice delivers

| Area | Change |
|---|---|
| Precision | Cents everywhere. Category rollup uses the same exclusions as the summary. Ledger is the whole month, grouped by day, each row carrying date and account. |
| Logos | Plaid's `logo_url` is stored per transaction and rendered as a merchant tile on every row, with the existing category glyph as the fallback. |
| Drill-down | A category band, a recurring row, a ledger row, or a donut slice pushes a detail page: total this month, a six-month trend, every matching transaction this month. |
| Charts | Three, in Swift Charts: a donut of category shares on "Where it went", a Mon to Sun daily bar chart on "In and out", and the six-month trend on the detail page. |

The six-tab rail stays. Bands stay full-bleed pastel on white with one ink.

## 3. Decisions

| Decision | Choice | Why |
|---|---|---|
| Merchant logos | Plaid `logo_url`, stored as `MoneyEntry.logoURL: String?` | Already in the responses being paid for. No third-party logo API, so nothing new against the $2 per user per month ceiling, and no merchant names leave the device. This reverses Section 6 of the inference-layer spec: the reference screens Shiv chose are logos on pastel bands, and a white circle holding the mark sits inside the band vocabulary rather than fighting it. |
| Logos on old rows | One-time cursor reset | `/transactions/sync` only re-delivers changed transactions, so rows synced before this change would never gain a logo. On first launch after the change every item's cursor is cleared once, so the next sync replays history through the same upsert path. Safe: `ingest` is keyed on `transaction_id`. Not billed: Plaid's Transactions product is billed per connected item, not per sync call. |
| Logos on rows Plaid never resolved | Borrowed from a sibling | The view model builds a merchant-to-logo map from every row in its window, keyed on `merchantID` then on the lowercased merchant name, so a row with no URL still shows the mark if any other row for that merchant carries one. |
| Chart library | Swift Charts | Already imported by two Recovery screens. `SectorMark` gives the donut and `chartAngleSelection` gives slice taps without a hit-test of our own. |
| Donut colour | One ink at stepped opacity, largest slice darkest, 2pt paper gaps, top five plus "Other" | The money palette is six pastels; run through the dataviz validator as a categorical palette it fails every check (chroma floor, CVD separation, normal-vision floor). A single-hue sequential encoding is what the validator passes and what the one-ink rule already says. Identity is never colour alone: each category band below carries a swatch at the same opacity plus its name, and the two lists are in the same order. |
| Bar charts | Single series, emphasis form | The current day or month in solid ink, the rest at reading opacity, a direct label on the emphasised bar only. No y-axis: the figure above the chart is the number, the bars are the shape. |
| Detail page ownership | Its own view model, own fetch | Six months of history is not something the tab should load on every save in the app. Follows `MetricDetailViewModel`. |
| Where series math lives | `Insights/SpendSeries.swift` in LifeOSKit | The app target has no test target. Bucketing by week and by month, and folding a share list into "Other", are the things most likely to be off by one, and the kit is where they can be tested. |
| Detail filter | `enum MoneyDetailFilter { case category(String), merchant(String) }` | A category and a merchant page are the same page with a different predicate. One screen, one view model. |

## 4. Data

### 4.1 Persistence (LifeOSKit)

- `MoneyEntry.logoURL: String?`. Optional, additive, lightweight migration,
  exactly as `merchantID` was added. Nil for manual entries and for rows Plaid
  sent without one.
- `MoneyIngestRow.logoURL: String?`, written by `ingest` on insert and update,
  so a backfilled logo moves onto an existing row.
- `MoneyEntry.isSpending: Bool`: negative amount, not pending, not
  transfer-like. `summarise` and the category rollup both read it, so the
  category list sums to the "Spent" figure by construction.

### 4.2 Integrations (LifeOSKit)

- `PlaidTransaction.logo_url: String?` decoded; fixture gives `txn_coffee` a
  URL and leaves the others null.
- `PlaidMapping` copies it onto the ingest row.

### 4.3 Insights (LifeOSKit)

`SpendSeries`, pure functions over `SpendSeries.Line(amount: Double, date: Date)`:

- `week(of date: Date, lines:, calendar:) -> [DayTotal]`: seven entries from
  the calendar's first weekday, each `date`, `amount` (positive spend), and
  `isFuture`. Only negative amounts count.
- `months(endingIn date: Date, count: Int, lines:, calendar:) -> [MonthTotal]`:
  `count` entries oldest first, each `monthStart` and `amount`. A month with
  nothing spent is present with zero, never missing.
- `fold(_ shares: [Share], keep: Int) -> [Share]`: keeps the `keep` largest,
  sums the rest into one named "Other". A list of `keep + 1` or fewer is
  returned as is: an "Other" of one category is a category with the wrong
  name.

### 4.4 View layer (app)

- `MoneyRow` gains `logoURL: URL?` and `accountName: String?`.
- `CategoryRow` gains `count: Int`.
- `RecurringRow` gains `logoURL: URL?`.
- `MoneySnapshot.recent` becomes the whole month, most recent first. The coach
  bundle already takes `prefix(30)`.
- `MoneySnapshot.week: [DaySpend]` and `MoneySnapshot.slices: [CategorySlice]`
  (name, amount, share, `opacity` step), derived in the view model.
- `MoneyDetailSnapshot`: `title`, `subtitle`, `logoURL`, `monthTotal`,
  `monthCount`, `months: [MonthSpend]` (six, oldest first, `isCurrent` on the
  last), `average` across the five completed months, `transactions:
  [MoneyRow]` for the current month.

## 5. Screens

### 5.1 In and out

Unchanged bands, plus one: **This week** (stone) holding the week's spend at
figure size and the seven-bar chart. Today's bar is solid ink with its amount
above it; earlier days are ink at 0.3; days still to come are an empty track.

### 5.2 Where it went

Top band (mist): eyebrow, the "Spent" figure, "N transactions", and the donut
on the right with a 2pt paper gap between slices. Tapping a slice opens that
category. "Other" is not tappable.

Each category band gains a swatch circle at its slice opacity, "N
transactions" beside the name, a trailing chevron, and is a button that opens
the category. Categories folded into "Other" have no swatch.

### 5.3 Every month

Each recurring row gains the merchant tile and is a button opening the
merchant.

### 5.4 Recent

The whole month, grouped by day with a day header ("Today", "Yesterday", then
"Mon 24 Aug"). Each row: merchant tile, merchant, `category · account`,
signed amount to the cent, and is a button opening the merchant. Pending rows
keep their dimmed amount.

### 5.5 Detail page

Pushed on the Money tab's `NavigationStack` with `navigationDestination(item:)`.
White paper background, same bands:

1. **Headline band** in the section's tone: merchant tile or category glyph,
   title, "This month" eyebrow, the month total at 46pt, "N transactions".
2. **Six months band** (stone): the bar chart, current month solid with a
   direct label, a rule at the completed-months average, and a caption
   "Averages $X a month" or "First month with anything here".
3. **Transactions**: the month's rows grouped by day, same row as the ledger,
   not tappable (a merchant page opening a merchant page is a loop).

Empty month: the headline reads $0.00 and the transactions band says "Nothing
this month", with the six-month chart still showing history.

### 5.6 The merchant tile

`MerchantTile(logoURL: URL?, glyph: String, size: 40)`: a paper-white circle.
With a URL, `AsyncImage` clipped to the circle, the glyph shown while loading
and on failure. Without one, the glyph in ink at 0.75. `AsyncImage` goes
through the shared `URLSession`, whose `URLCache` keeps the 100 by 100 PNGs
from being fetched on every scroll.

## 6. Correctness rules

1. **Cents carry.** `MoneyFigure` rounds to two decimals before splitting whole
   from fraction, so `19.995` renders `$20.00` and never `$19.100`.
2. **Parts sum to the whole.** The category list and the donut are built from
   `isSpending` rows only, the same predicate as the "Spent" figure.
3. **A day with nothing is a bar of zero, a month with nothing is a bar of
   zero.** Missing buckets in a series would shift every later bar one slot
   left.
4. **The cursor reset happens once.** A `UserDefaults` flag records it. Reset
   on every launch would replay full history every day.
5. **"Other" is never a filter.** It is a fold for the donut only; the bands
   below still list every category.
6. **A logo is a hint, not an identity.** Borrowing is by `merchantID` first
   and by name second, and a borrowed logo never changes grouping.

## 7. Testing

- LifeOSKit `swift test`: `logoURL` decode, mapping and ingest upsert;
  `isSpending` against pending, transfer and income rows; `SpendSeries.week`
  across a month boundary and a calendar whose week starts on Monday;
  `SpendSeries.months` with an empty middle month; `fold` at, below and above
  the keep count.
- App: `xcodebuild` of the `LIfeOS` scheme for iPhone 17, then screenshots of
  each section and the detail page on the simulator in light and dark mode.

## 8. Out of scope

- Safe-to-spend, credit utilisation and the Accounts rail item from the
  inference-layer spec. Unchanged and still unbuilt.
- Editing or recategorising a transaction.
- A search box over the ledger.
- Grouping recurring detection by `merchantID` (its own slice).
