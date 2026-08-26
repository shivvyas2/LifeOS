# Money Budgeting Design Spec

**Date:** 2026-08-26
**Status:** Approved in conversation; this document records the decisions.

**Scope of this document:** Monthly spending budgets on top of the transactions Plaid and manual entry already produce: user-defined buckets that claim raw categories, a monthly limit per bucket, an unclaimed-spend view, and budget adherence feeding the Money sector's score. Does not cover savings goals, a wishlist, or loan surfacing; those are the next slices (see Section 8).

## 1. What this is

`MoneyScreen` shows income, expenses, savings rate and net worth, and the Money sector scores on the savings rate. None of that says whether the month went the way you *planned*. A budget is a plan you set: buckets like "Eating out" with a monthly limit, measured against what actually got spent. This slice adds the bucket model, the assessment, the score change, and the screen surface.

## 2. Decisions on record

These were put as questions and answered; they are settled.

**Budgets key on user-defined buckets, not raw category strings and not merchant rules.** A bucket claims one or more raw categories. This survives Plaid renaming a category or splitting one in two, works for manual entries, and lets one budget cover what Plaid calls three different things. The rejected options both fail silently: a renamed category simply stops counting and the budget quietly reads as under. A budget that silently stops counting is worse than no budget.

**This project is budgets alone.** Savings goals and a wishlist are close cousins (both are a target amount and progress toward it) and ship together as the next project. Loans are mostly display, `MoneyAccount` already knows a loan balance and subtracts it from net worth, and come after that.

## 3. The model

One new `@Model` in `Persistence`, registered in `LifeOSContainer.schema`:

```
SpendBucket
  id            UUID
  name          "Eating out"
  monthlyLimit  300           Double, must be > 0
  claimedRaw    [String]      raw claim keys, see Section 4
  sortOrder     Int
  createdAt / updatedAt
```

**A claim key may be held by at most one bucket.** `MoneyStore` enforces this on write rather than resolving collisions at read time; otherwise the same transaction counts in two buckets and every total is quietly wrong. Claiming a key another bucket holds *moves* it, and the store returns the name of the bucket it moved from so the UI can say so.

Bucket CRUD lives on `MoneyStore` beside the entry and account methods: `buckets()`, `addBucket(name:monthlyLimit:)`, `updateBucket(_:name:monthlyLimit:)`, `deleteBucket(_:)`, and `claim(_:for:)` / `unclaim(_:from:)` which carry the single-holder invariant.

## 4. The claim key

An entry's claim key is **`categoryCode ?? category`**: Plaid's raw `personal_finance_category.detailed` code when the entry has one, else the free-form `category` string a manual entry may carry, else nil.

The code is preferred for the same reason `MoneyCategoryRule` keys on it: `category` is display text, and keying arithmetic off display text means renaming a label silently changes what a budget counts. The detailed code is also the granularity the bucket vision needs; "Eating out" claims `FOOD_AND_DRINK_RESTAURANTS`, `FOOD_AND_DRINK_FAST_FOOD` and `FOOD_AND_DRINK_COFFEE` while "Groceries" claims `FOOD_AND_DRINK_GROCERIES`.

For display, a claim key travels with the last `category` label seen on an entry carrying it, so the UI shows "Fast food", never a shouting code. A key with no label shows the raw key: honest, and a prompt to fix the mapping rather than an invented transform.

## 5. The assessment, pure

Everything decidable goes in the `Sectors` package as pure functions, the same bet as the last two projects, for the same reason: the Xcode project has no test target, so anything in a view model is permanently unverifiable.

```
BudgetPeriod.lines(from: [MoneyEntry])            -> [SpendLine]
BudgetPeriod.assess(buckets: [BudgetBucket],
                    lines:   [SpendLine])         -> BudgetReport

SpendLine       key: String?   label: String?   amount: Double
BudgetBucket    plain value mirror of SpendBucket (id, name, limit, claimed keys, sortOrder)
BudgetReport
  rows          one per bucket: name, limit, spent, adherence   (bucket sort order)
  unclaimed     net outflow matching no bucket, grouped by key, with label and count
```

`lines(from:)` is the one place the entry filter lives: it drops pending entries and transfer-like codes (`MoneyCategoryRule.isTransferLike`, the same rule the rollup uses; a card payment must not surface as unclaimed spend), and extracts the claim key. Both call sites, the Money screen and the monthly close, go through it, so the two cannot drift.

**Correctness rules, in priority order:**

**Unclaimed spend is a first-class result, never silently dropped.** A key no bucket claims, including the nil key, appears in `unclaimed` with its label and transaction count so it can be assigned. The whole point of choosing buckets over raw strings was that nothing stops counting quietly.

**Only outflows count, and refunds net within their bucket.** `MoneyEntry` is positive-in, and a refund arriving as a positive amount in a spend category must reduce that bucket's spent figure, not inflate income. Amounts are summed per key first; a bucket's spent is the negated sum over its claimed keys, floored at zero. The same netting keeps income keys out of `unclaimed`: only keys whose net is an outflow appear there.

**Months key on the same boundary as everything else.** The close feeds `assess` from `MonthWindow`; the screen feeds it from `MoneyStore.monthEntries`. Both are the calendar month; two definitions of "this month" in one app is a bug waiting to happen.

**Adherence per bucket:** at or under the limit is 1.0; over the limit it degrades linearly, reaching 0 when the overspend equals the limit again (`max(0, 1 - (spent - limit) / limit)`). A bucket 1% over must not read the same as one at triple its limit.

## 6. Scoring

Budget adherence becomes the Money sector's primary evidence, but only when buckets exist:

```
budgets kept          3/4      weight 3    normalised = mean per-bucket adherence
kept of what came in  38%      weight 2    (drops from 3)
spend vs last month   -8%      weight 1    unchanged
earned / spent                 weight 0    unchanged, context
unclaimed             210      weight 0    context, only when nonzero
```

The saving rate carries weight 3 today. With buckets it drops to 2 and adherence takes the top slot, because a budget is a plan you set: beating it measures what you decided mattered, where a saving rate measures what happened to be left over.

**With no buckets, the adherence and unclaimed rows simply do not exist** and the score is exactly today's, saving rate at weight 3. Same nil-not-zero rule as everywhere else: no evidence, no row, never a zero.

**Unclaimed spend never affects the score.** Penalising a gap in the app's category mapping would score the mapping, not the person. It is shown so it can be fixed, and stays out of the arithmetic.

**Plumbing:** `MonthInputs` gains `budget: BudgetReport?`, assembled in `MonthlyCloseViewModel.loadMonthInputs()` from `moneyStore.buckets()` and the windowed entries, nil when there are no buckets. `MoneyScorer` gains the same optional parameter. `SectorEvidenceFactory` passes it through.

**Archived adherence comes free.** Close freezes evidence rows onto `SectorScore`, so raising a limit in March cannot rewrite February's adherence. The spine's archive guarantee covers this with no new work.

## 7. The screen

**A budgets band on the existing Money surface, built from the same kit.** A `SoftCard` after the metric tiles: one row per bucket with name, spent against limit, a thin progress bar, and the over ones marked. Unclaimed sits below inside the same card with its labels, amounts and counts, and an assign action that opens the editor. When there are no buckets the band is a single quiet "Set budgets" affordance, not an empty chart.

**Bucket editing lives in a sheet**, following `AddMoneySheet`'s pattern in `RootView`: name, monthly limit, and which categories it claims. The claimable list is built from the keys seen on recent entries plus keys other buckets hold; a key held elsewhere shows its holder, and claiming it moves it with the store's returned name confirming from where.

`MoneySnapshot` gains the rows the band renders (bucket rows and unclaimed rows as plain `Equatable` values); `MoneyViewModel.load` builds them through the same `BudgetPeriod` the close uses.

## 8. Out of scope, and what comes next

1. Savings goals and a wishlist: one shared shape (target amount, progress), the next project.
2. Loan surfacing beyond the net-worth subtraction that already exists.
3. Rollover budgets, weekly periods, per-merchant rules, shared budgets.
4. Multi-currency arithmetic. Everything sums raw amounts, matching `summarise`; the first non-USD account revisits both together.
5. The coach reading budget state. The evidence rows land on `SectorScore` where the digest already looks; anything richer waits for a real use.

## 9. Testing

The parts that can hold a bug, all pure or store-level:

- A refund nets within its bucket rather than inflating income or unclaimed.
- A key claimed by a second bucket moves, and the report never counts it twice.
- Unclaimed grouping: nil keys grouped as one, income keys absent, counts right.
- Adherence at exactly the limit is 1.0; at double the limit it is 0.
- No buckets leaves `MoneyScorer` output identical to today's, row for row.
- `lines(from:)` drops pending and transfer-like entries and prefers the code over the label.
- Store: limit must be positive; deleting a bucket frees its keys; claim returns the previous holder's name.
