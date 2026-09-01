# Money Inference Layer Design Spec

**Date:** 2026-09-01
**Status:** Approved for planning
**Scope of this document:** Widening what the device decodes from Plaid, and the design direction that justifies each new field. Specifies slice 1, the decode and schema widening, in full. Slices 2 to 4 are described only as far as is needed to explain why a field is being stored before anything reads it. Does not specify the inference arithmetic, which gets its own spec.

---

## 1. What this is

`MoneyScreen` renders six sections behind a vertical rail: flow, categories, repeating, goal, pressure, ledger. Every one of them is a readout. Net, Earned, Spent, Kept and Net worth are five stacked bands of near-identical visual mass showing arithmetic the person could do themselves. The only inference on the screen is `verdict`, three words in a caption under the net figure.

The gap is not features. It is that nothing on the screen tells you something you did not already know, and there is no account-level view at all, so the app cannot answer "how close am I to my limit" or "what is actually spendable".

Closing that gap needs data the app is already receiving and throwing away.

**This slice stores that data and changes no UI.** It exists on its own because of Section 2.

---

## 2. Why this is urgent, and why it is first

`plaid-sync` passes Plaid's JSON through untouched. Everything in Section 4 is already arriving at the device on every sync and being dropped by `PlaidWireFormat`'s decoder.

`/transactions/sync` is a cursor-based delta. Once a bank is connected and the cursor advances, Plaid does not resend transactions the device has already seen. A decoder widened after the first real connection would therefore carry the new fields on new transactions only, and every transaction in the initial history pull, which is up to 24 months and the entire basis for the baselines in Section 5.4, would hold nulls forever.

This is recoverable rather than fatal. Clearing the Item's cursor makes Plaid replay full history, and `MoneyStore.ingest` is an idempotent upsert on `transaction_id`, so a replay updates rows in place rather than duplicating them. But the recovery costs a full re-pull and has to be triggered deliberately, and no bank has been connected in production yet.

So this slice lands before the first real connection. That is the whole reason it is separated from the work that reads its output.

---

## 3. Decisions on record

| Decision | Choice | Why |
|---|---|---|
| Server change | None | `plaid-sync` already passes Plaid's JSON through untouched. This is a decoder change only. |
| New Plaid products | None | Every field here is already in the responses being paid for. No new billing against the $2 per user per month ceiling. |
| `/transactions/recurring` | Rejected | A separately billed Plaid product. `RecurringSpend` already detects recurrence from history for free, and Section 5.3 improves it with a field that costs nothing. |
| Merchant logos | Rejected, for now | See Section 6. An aesthetic decision, not a scope one. |
| Schema shape | New optional properties on existing `@Model` types | Matches how `categoryCode` was added: a lightweight SwiftData migration with no manual migration step. |
| Migration | Additive only | Nothing is renamed, retyped or removed. An old row reads back with nils. |

---

## 4. What gets decoded

The names on the left are Plaid's, verified against Plaid's API reference rather than recalled. The names on the right are this app's.

### 4.1 Transactions

| Plaid field | Stored as | Read by |
|---|---|---|
| `merchant_entity_id` | `MoneyEntry.merchantID: String?` | Section 5.3 |

One field. `RecurringSpend` currently groups by merchant display string, which splits `NETFLIX.COM` from `Netflix` into two charges and merges two different Starbucks into one. `merchant_entity_id` is Plaid's stable identifier for a merchant across locations and descriptor spellings, and it is the correct key for that grouping.

It is optional at the source: Plaid does not resolve every descriptor to a merchant entity. Section 5.3 therefore specifies a fallback rather than assuming presence.

### 4.2 Accounts

| Plaid field | Stored as | Read by |
|---|---|---|
| `mask` | `MoneyAccount.mask: String?` | Section 5.2 |
| `subtype` | `MoneyAccount.subtype: String?` | Sections 5.1, 5.2 |
| `balances.available` | `MoneyAccount.availableBalance: Double?` | Section 5.1 |
| `balances.limit` | `MoneyAccount.creditLimit: Double?` | Section 5.2 |

`MoneyAccount` currently holds `type`, which is Plaid's coarse classification: depository, credit, investment or loan. That is enough for `netWorthContribution` and not enough for anything else. `subtype` is what separates a checking account from a savings account, and a credit card from a mortgage, and both of those distinctions decide whether a number is meaningful.

**Every one of these is optional at the source, and each nil means something different.** Section 7 covers what the reading code must do about that. Storing them as non-optional with a zero default would be the bug this spec exists to avoid: a credit limit of 0 renders as 100% utilization, which is a plausible wrong answer rather than a visible failure.

### 4.3 What is deliberately not decoded

`logo_url`, `personal_finance_category_icon_url`, `website`, `location`, `payment_channel`, `authorized_date`, `counterparties`, `merchant_category_code`, `personal_finance_category.confidence_level`, `pending_transaction_id`.

All are arriving. None are read by any of Section 5. Adding a stored property that nothing reads is a migration paid for with no return, and each of these can be added later by the same additive mechanism at the same cost.

`pending_transaction_id` deserves a note because it looks load-bearing and is not. It links a pending charge to the posted transaction that replaces it. The Plaid spec's Section 6.3 already handles that settlement correctly through the `removed` array, and the two mechanisms describe the same event. Adding this would give a second way to do something already done.

---

## 5. The design this serves

Specified here only to the depth that justifies Section 4. Each of these gets its own spec.

### 5.1 Safe to spend

Available cash summed from depository `balances.available`, minus recurring charges predicted to land before the next income date.

Needs `availableBalance` because `current` is the wrong number: it includes funds not yet settled and money already committed to pending charges. It needs `subtype` to sum only spendable accounts, since a savings account and a checking account are both `depository` and only one of them is money you are about to spend.

**This is the one that can hurt by being wrong.** Every other inference here is descriptive: if utilization is off, the person notices. This one is prescriptive, and a figure that says $800 when the truth is $200 causes an overdraft. It is built last, defined conservatively, and always shows its working: "$1,240 available, minus $380 in bills due before Sep 15." A bare number with no explanation is the version that fails quietly. It also depends on 5.3 landing first, because it cannot know what is still due without reliable recurring detection.

### 5.2 Credit utilization

`currentBalance / creditLimit` per card, and an overall figure across cards.

Needs `creditLimit`, without which it cannot be computed at all, and `subtype` to include credit cards while excluding every other `type: credit` account. It needs `mask` because a person with two cards needs to know which one the number is about.

The cheapest of the four and the most immediately legible: it is a fraction between 0 and 1, which is exactly what the existing `Pinstripes` component takes, unmodified.

### 5.3 Real subscription detection

`RecurringSpend` groups on `merchantID` when present, falling back to its current normalized merchant string when nil.

Once merchants are stable identities rather than descriptor spellings, a price increase is the same identity at a different amount and a duplicate service is two identities in one category. Both fall out of the grouping rather than needing rules of their own.

### 5.4 Spending drift

This month's run rate per category against a trailing baseline of the same category, projected to month end.

Needs no new field. It is listed because it is the reason Section 2 matters: the baseline is computed from the initial history pull, so it works on the first day the app has a bank rather than after three months of use, but only if that history carries the fields the rest of the layer reads.

### 5.5 Where the inferences surface

`MoneySnapshot` already carries `PressurePoint`, which holds a `title`, a `detail` written as a plain sentence in the app's voice, and an `amount`. That is already the shape of "tell me the thing I need to know", and it is currently reachable only by opening a tab called "What hurts".

The direction, specified properly in the UI slice: promote the highest-priority pressure point to a lead band pinned above the rail's content and visible on every section, and widen what can become a pressure point to include 5.1 through 5.4. One slot, always answered, so the screen states its conclusion before being asked.

A new Accounts rail item renders 5.2, one band per account, mask in the eyebrow, balance as the figure, utilization as pinstripes. It replaces nothing and answers a question the app currently cannot answer at all.

---

## 6. Why there are no merchant logos

Plaid sends `logo_url`, a 100 by 100 PNG per merchant, and it is the single largest visual lever available. It is still declined here, and the reason is design rather than scope.

`MoneyPalette` is built as full-bleed pastel bands on pure white with one ink across all of them, and its own comments record that this was chosen against the alternative and tuned on real hardware. The apps this data would imitate are built on brand logos and cards floating on dark grey. A grid of logos dropped into flat pastel bands reads as one app pasted into another, and it would cost the most distinctive thing this screen has.

The useful part of those apps is that they tell you things. That is what Section 5 takes. The look is not the part worth taking.

This is a decision, not a permanent bar. If the band vocabulary later grows a form that can hold an image without fighting it, the field is one additive property away.

---

## 7. Correctness rules

Each of these, unhandled, produces a plausible wrong answer rather than a visible failure. That is the same standard the Plaid spec's Section 6 was written to.

### 7.1 A missing credit limit is not a limit of zero

Plaid returns `balances.limit` as null at institutions that do not report it. Stored as an optional and rendered as "no limit reported", never as a computed percentage. A card at $610 against a limit of 0 is 100% utilized by arithmetic and unknowable in fact, and the difference is the whole value of the number.

### 7.2 A missing available balance is not zero either

`balances.available` is null on accounts where the institution does not distinguish it. Safe-to-spend must exclude such an account from its sum and say that it did, rather than treating it as an account holding nothing. Silently summing nulls as zeroes understates available cash, which is the direction that causes the wrong behaviour: a person who believes they have less than they do.

### 7.3 `type` and `subtype` answer different questions

`netWorthContribution` keys off `type` and must keep doing so: every `credit` and `loan` account is money owed regardless of subtype. Utilization keys off `subtype`, because a mortgage is `type: loan` with a balance and no meaningful utilization, and a line of credit is not a credit card. Neither rule may be rewritten in terms of the other.

### 7.4 `merchantID` is absent, not empty

A nil `merchantID` means Plaid did not resolve the descriptor. Grouping every nil together would merge every unresolved merchant into a single fictitious subscription, which is exactly the false positive `RecurringSpend`'s doc comment says is worse than a miss. The fallback is per row, to that row's existing normalized merchant string, never to a shared nil bucket.

### 7.5 Old rows read back nil

Every property added here is optional on an existing `@Model`, so rows written before this slice decode with nils and no migration step. Any code reading them must treat nil as "not known" rather than "not applicable". Sections 7.1 through 7.4 are the specific cases.

---

## 8. Testing

TDD throughout, in `LifeOSKit` where the logic lives.

**Unit**

- `PlaidWireFormat` decodes each new field, and decodes a payload omitting all of them without throwing, which is the shape every existing test fixture has
- `MoneyIngestRow` and `MoneyAccountRow` carry the new values through to the model
- `MoneyStore.upsertAccounts` updates the new fields on an account it has already seen, since balances and limits change between syncs while the account does not
- A `MoneyEntry` and a `MoneyAccount` written before this change read back with nils rather than failing to load

**Fixture**

`PlaidFixtures.syncPage` is currently trimmed to the fields the decoder reads, which is what stopped it answering "what else does Plaid send". Extend it with the new fields on some rows and not others, because mixed presence is the real-world shape and the nil handling in Section 7 is the part worth testing. The existing assertions on sign, removals and transfer exclusion must continue to pass unchanged: this slice is additive and any movement in those numbers is a regression.

---

## 9. Out of scope

1. Every inference in Section 5. This slice stores; it computes nothing.
2. Every UI change, including the lead band and the Accounts section.
3. The fields listed in Section 4.3.
4. Webhooks, which would remove the still-fetching state but are unrelated to this.
5. Any change to `plaid-sync` or any other Edge Function.

## 10. What this slice is finished by

The new fields are stored, tested, and visible in no UI. Success is that a bank connected after this ships carries `merchantID` on its transactions and `mask`, `subtype`, `availableBalance` and `creditLimit` on its accounts, for the full history Plaid returns, so that every slice after this one can be built against data that is already complete.
