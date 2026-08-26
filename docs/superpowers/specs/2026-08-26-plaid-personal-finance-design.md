# Plaid Personal Finance Design Spec

**Date:** 2026-08-26
**Status:** Approved for planning
**Scope of this document:** Connecting a real bank account through Plaid and turning its transactions and balances into the numbers the Money tab already renders. Covers the Link flow, the Edge Functions that hold the credential, the sync path into `Persistence`, and the correctness rules that keep the totals honest. Does not cover budgets, goals, spending forecasts, or the coach reading financial data.

---

## 1. What this is

`MoneyScreen` renders income, expenses, savings rate, net worth, and a transaction list. Today those numbers come from manual entry or, in DEBUG, from `SampleMoneyData`. The screen's empty state says "Plaid sync arrives in a later slice." This is that slice.

The persistence layer was built for this and needs very little reshaping. `MoneyEntry` already carries `externalID` for Plaid's `transaction_id`, a `pending` flag, a `source` of `.plaid`, and a written-down sign convention. `MoneyStore.ingest` is already an upsert keyed on `transaction_id`. `MoneyAccount` already maps onto `/accounts/get` and already knows that credit and loan balances subtract from net worth. The work is the connection, the credential, the sync, and the correctness rules.

**Target for this slice: one real bank account, Shiv's, syncing real transactions.** Not a multi-user launch. See Section 10.

---

## 2. Decisions on record

| Decision | Choice | Why |
|---|---|---|
| First target | Real data, single user | Find out how the Money screen reads with real money in it before paying per connected Item |
| Where transactions rest | Device only | Postgres holds the credential and nothing else; SwiftData stays the source of truth |
| Where the credential rests | Postgres, service-role only | Every Plaid call requires `client_id` and `secret`, so no Plaid call can originate on device |
| Link presentation | Plaid's native LinkKit SDK | Hands `public_token` straight to the app, so connecting needs no webhook |
| Products | Transactions and Accounts | Exactly enough for income, expenses, savings rate, and net worth. No Auth, Identity, or Investments |
| Categories | Plaid `personal_finance_category` | Already normalized across institutions; a hand-rolled mapping would be worse and is unpaid work |
| Sync trigger | Existing staleness policy | `WhoopSyncPolicy`'s rule (stale after an hour, plus a day boundary) applies unchanged |
| Cursor owner | The device, per Item | See Section 6.1. This is the one deliberate departure from the Whoop precedent |

---

## 3. Architecture and data flow

Every Plaid call is server-side. The device talks only to Edge Functions, authenticated with its Supabase session.

### 3.1 Connect

1. App calls `plaid-link-token`. The function calls `/link/token/create` with `client_user_id` set to the Supabase user id and returns only the `link_token`.
2. App presents LinkKit with that token. The user picks their bank and logs in.
3. LinkKit's success callback returns a `public_token`.
4. App posts it to `plaid-exchange`, which calls `/item/public_token/exchange` and writes `access_token` plus `item_id` into `plaid_items`. The response to the app contains the institution name and item id, never the token.

### 3.2 Sync

1. App calls `plaid-sync` with the cursor it holds for each connected Item.
2. The function loads that user's `access_token`, calls `/transactions/sync` and `/accounts/balance/get`, and returns `added`, `modified`, `removed`, `accounts`, `next_cursor`, and `has_more`.
3. App negates every transaction amount, maps categories, applies removals, upserts accounts, and only then persists the new cursor.
4. If `has_more`, the app calls again immediately with the new cursor.

### 3.3 Disconnect

App calls `plaid-disconnect`. The function calls `/item/remove` and deletes the row. The app clears that Item's cursor.

**Local history is kept by default.** Disconnecting stops the billing and revokes the credential; it is not a request to erase the past. The confirmation offers deleting that Item's entries as a separate, explicitly checked choice.

Disconnect is not optional polish. A connected Item bills monthly, and without it the only way to stop is a visit to the Plaid dashboard.

---

## 4. Server

### 4.1 Migration: `plaid_items`

```sql
create table public.plaid_items (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  item_id text not null,

  -- A live, non-expiring credential to a bank account.
  access_token text not null,

  institution_id text,
  institution_name text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (user_id, item_id)
);

alter table public.plaid_items enable row level security;
-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner. Only the service role, which bypasses RLS,
-- can read this table, and it does so only from inside an Edge Function.
```

The composite primary key is what allows a second bank later without a schema change.

**Named risk:** this stores a bank credential as a plaintext column. Anyone holding the service-role key or direct database access can read it. For a single user that is an accepted trade; Supabase Vault is the upgrade path. This must be revisited before a second person connects an account, and the migration carries that note in a comment so it is not rediscovered by accident.

`sync_state` gains no `plaid` row. Section 6.1 explains why.

### 4.2 Functions

Four functions sharing `_shared/plaid.ts` for environment reading, caller resolution, and a `callPlaid` helper.

| Function | Plaid endpoint | Returns |
|---|---|---|
| `plaid-link-token` | `/link/token/create` | `link_token` |
| `plaid-exchange` | `/item/public_token/exchange` | `item_id`, `institution_name` |
| `plaid-sync` | `/transactions/sync`, `/accounts/balance/get` | delta, accounts, cursor, `has_more` |
| `plaid-disconnect` | `/item/remove` | ok |

**Caller resolution is a security boundary, not a formality.** Each function resolves the user by calling `getUser()` against the incoming Authorization header and scopes the `plaid_items` lookup to that id. A service-role client that trusted a `user_id` from the request body would let any authenticated user read any other user's bank data. `whoop-token` does not need this because it holds no per-user state; these functions do.

Secrets are `PLAID_CLIENT_ID`, `PLAID_SECRET`, and `PLAID_ENV`, set with `supabase secrets set` and never written to this repository. `_shared/plaid.ts` opens with the same explanation `whoop-token/index.ts` carries, for the same reason: an `.ipa` is a zip file, so a secret compiled into the app ships public.

`PLAID_ENV` is what sequences the work. The entire path is built and tested against Sandbox, with its fake institutions and forced error states. Flipping one variable points it at the real bank.

**Error handling** follows `whoop-token`: log the upstream body, return only a status, because Plaid's error responses echo request parameters. One exception. `ITEM_LOGIN_REQUIRED` is returned as its own error code rather than a generic 502. It is the most common real-world Plaid failure, since banks invalidate stored logins every few months, and it needs a reconnect prompt rather than a retry spinner.

**Page cap.** `plaid-sync` fetches at most 3 pages per invocation and returns `has_more` so the device drives the rest. An initial pull of several years of history would otherwise risk the function's wall clock.

---

## 5. Client

### 5.1 The SDK stays out of the kit

LinkKit is a closed-source, UIKit-facing binary. It is added to the app target only, wrapped by a small `PlaidLinkPresenter` in `Features/Settings`. `LifeOSKit/Sources/Integrations` takes no third-party import, which keeps it unit-testable and keeps the binary out of the reusable layer.

### 5.2 New in `Integrations`

- **`PlaidClient.swift`** The four function calls, authenticated with the Supabase session token, endpoints from `AppConfig`. Mirrors `WhoopTokenExchange`'s error unwrapping so a 502 still reveals the real upstream cause.
- **`PlaidCursorStore.swift`** A map of `item_id` to cursor, in `UserDefaults`.
- **`PlaidSync.swift`** Orchestration: call, negate, map, ingest, remove, upsert accounts, then persist the cursor.
- **`PlaidCategory.swift`** Pure mapping from `FOOD_AND_DRINK` to "Food & drink".

`WhoopSyncPolicy` is generalized to `SyncStalenessPolicy` and used by both integrations. It is a single static function whose rule applies unchanged; the alternative is copying it under a second name.

### 5.3 `MoneyStore` additions

All three are additive:

- `remove(externalIDs: [String])` for Plaid's `removed` array
- `upsertAccounts(_:)` keyed on `account_id`, for balances and therefore net worth
- `ingest` extended to carry `accountID`, `accountName`, and `currencyCode`, so a transaction knows which account it came from

`MoneyEntry` also gains one stored property, `categoryCode: String?`, holding Plaid's raw `personal_finance_category.detailed` value. `category` stays what it is, a display string.

This separation is load-bearing rather than tidy. Section 6.4's exclusion rule has to identify transfers, and keying that off the display string would mean `summarise` comparing against "Transfer in", so renaming a label for the UI would silently change the savings rate. The rule keys off `categoryCode`. As a new optional property on an existing `@Model`, it is a lightweight SwiftData migration and needs no manual migration step.

### 5.4 Feature layer

`MoneyViewModel` gains `sync()`, driven by `SyncStalenessPolicy` on foreground, plus `isSyncing`, `lastSyncedAt`, and an error case. `MoneySnapshot` gains `lastSyncedAt` and a sync state.

One correctness fix falls out here. `isConnected` is currently `!entries.isEmpty || !accounts.isEmpty`, so a bank connected seconds ago that has not yet returned transactions renders the "not connected" empty state. It becomes "a Plaid Item exists, or there is local data."

`MoneyScreen`'s empty state loses "Plaid sync arrives in a later slice" and gains a Connect button, a reconnect banner for `ITEM_LOGIN_REQUIRED`, and the still-fetching state from Section 7.4. The two "Arrives in the next release" rows, in `ConnectionsSettingsScreen` and onboarding's `ConnectionsScreen`, become live Connect and Disconnect rows backed by a `PlaidConnectionViewModel` sitting alongside `WhoopConnectionViewModel`.

**Final step of the slice**, once real transactions render: delete `SampleMoneyData.swift`, the Settings toggle, and `MoneyViewModel.sampleDataKey`. `SampleMoneyData.swift:9` already asks for this.

---

## 6. Correctness rules

These are the rules that decide whether the headline number is true. Each one, unhandled, produces a plausible wrong answer rather than a visible failure.

### 6.1 The cursor lives on the device, per Item

`/transactions/sync` cursors are scoped to an Item, so the store is a map, not a string. A single shared cursor works until a second bank is connected, then corrupts both.

The device owns it because a server-advanced cursor loses data. If the server advanced the cursor and the app then crashed mid-ingest, Plaid would never resend that page and those transactions would be gone permanently. With the device persisting the cursor only after a successful `ingest`, a crash replays the page, and `ingest` is an idempotent upsert on `transaction_id`, so a replay is harmless.

It also self-heals a reinstall. A wiped app container means no cursor, which means an empty cursor, which means Plaid replays full history into a fresh database. This is precisely why the cursor belongs in `UserDefaults` and not the Keychain: **the Keychain survives a reinstall and the SwiftData database does not.** A surviving cursor beside a wiped database means Plaid replays nothing and the history is silently gone. The cursor must die with the data it describes.

### 6.2 Sign

Plaid's `amount` is positive for money leaving the account. `MoneyEntry`'s convention is the opposite: positive is money in. The ingestion layer negates. `MoneyEntry.swift:14` already documents this. A silent sign flip turns income into expenses and every rollup lies, which is why Section 8's fixture test exists.

### 6.3 Pending settles under a new id

When a pending charge posts, Plaid issues it with a different `transaction_id`, returning the old one in `removed` and the new one in `added`. Ignore `removed` and every card charge eventually exists twice. `summarise` already excludes pending rows from totals, so the damage lands in the transaction list rather than the headline, but it is still wrong.

### 6.4 Transfers and card payments inflate both sides

Moving $500 from savings to checking reads as $500 of income and $500 of expense. The net is right, but income and expenses are both overstated and the savings rate is dragged toward zero for money that was never spent. A credit card payment double counts against the purchases already recorded on the card.

`summarise` therefore excludes from income and expenses:

- a `categoryCode` whose primary segment is `TRANSFER_IN` or `TRANSFER_OUT`
- a `categoryCode` of `LOAN_PAYMENTS_CREDIT_CARD_PAYMENT`

Manual entries have no `categoryCode` and are never excluded.

Excluded rows still appear in the transaction list. They happened; they are just not spending.

---

## 7. Failure modes

### 7.1 Expired bank login

`ITEM_LOGIN_REQUIRED` surfaces as a distinct error and the Money screen shows a reconnect banner. This slice offers disconnect and reconnect. Proper Link update mode is a follow-up (Section 9).

### 7.2 Function or network failure

Sync fails without mutating local data or the cursor. The previous snapshot stays on screen with its `lastSyncedAt`, which is honest, rather than being replaced by zeroes.

### 7.3 Partial ingest

Covered by 6.1. The cursor advances only after a successful ingest, and replays are idempotent.

### 7.4 The first sync legitimately returns nothing

Plaid fetches transaction history asynchronously after Link completes and normally announces readiness by webhook, which this design does not build. The sync immediately after connecting can therefore correctly return zero transactions.

The screen must say it is still fetching history and offer a retry. It must not render an empty month as though that were the user's financial position. This is the direct cost of skipping webhooks and it is accepted, but it has to be visible in the UI rather than silently wrong.

### 7.5 Duplicate connect

Connecting the same institution twice creates two Items with overlapping transactions. Plaid returns distinct `transaction_id` values per Item, so `ingest` cannot deduplicate them. `plaid-exchange` therefore rejects an institution already present for that user, and the UI says so.

---

## 8. Testing

TDD throughout. Pure logic lives in `LifeOSKit` and is tested there.

**Unit**

- `PlaidCategory` mapping, including an unknown category falling through to nil rather than a crash
- Sign negation
- Transfer and card-payment exclusion in `summarise`, asserted on the savings rate specifically
- `MoneyStore.remove(externalIDs:)` and `upsertAccounts`
- `PlaidCursorStore` per-Item isolation
- `SyncStalenessPolicy` after the rename, reusing the existing Whoop cases

**Fixture**

The test that earns its keep: a real Sandbox `/transactions/sync` response saved into `Tests`, decoded, ingested, and asserted against an expected `MoneySummary`. This is what catches a sign flip, a mishandled `removed`, and a transfer leaking into income. It runs offline and does not need Plaid.

**End to end, manual**

Sandbox provides `user_good` and `pass_good` for the happy path, and `/sandbox/item/reset_login` forces `ITEM_LOGIN_REQUIRED` on demand so the reconnect banner is exercised rather than assumed.

---

## 9. Out of scope, and what comes next

Not in this slice, in rough order of likely value:

1. **Link update mode** for re-authenticating an expired Item in place, rather than disconnect and reconnect
2. **Webhooks** for `SYNC_UPDATES_AVAILABLE` and `HISTORICAL_UPDATE`, which would remove the still-fetching state in 7.4 and keep data fresh with the app closed
3. **Multi-user hardening**: Vault for the credential, and the cost question in Section 10
4. **Coach access to spending**, which the device-only decision deliberately forecloses for now
5. Budgets, goals, recurring-transaction detection, spending forecasts

---

## 10. Cost, before this ships to anyone else

The standing constraint is roughly $2 per user per month across backend and AI, with the app free. Plaid's Transactions product bills per connected Item per month, and a user with three banks is three Items. That is a per-user cost that scales with connections and sits alongside the coach's allowance rather than inside it.

This slice does not pay that, because it targets one user on Plaid's free tier. **The pricing question is deferred, not answered**, and it must be answered with current Plaid pricing before a second person connects an account. If the numbers do not fit, the honest options are a paid tier for finance, a cap on connected institutions, or dropping bank sync in favour of manual entry. Building the feature does not commit to shipping it to everyone.
