# Cards Wallet Design Spec

**Date:** 2026-10-08
**Status:** Approved in conversation, implemented on `feat/cards-wallet`
**Part of:** a four-slice Money plan. This is slice 1.

1. Cards wallet (this spec)
2. Live updates: Plaid webhook, silent push, device sync
3. Budget coach: bucket warnings (delivery style still to decide)
4. Best-card advisor: reward rates per card, "use Sapphire here"

Slices 3 and 4 both need to know which card paid, so this one goes first.

---

## 1. What Shiv asked for

- See at a glance which card paid for each transaction, with a picture of the
  card: Discover, Chase Sapphire, Apple Card, Zolve, Banana Republic.
- Set the card in the app when Plaid does not say, or says wrong.
- Get spending from a card Plaid cannot connect into the app at all.

## 2. Decisions on record

| Decision | Choice | Why |
|---|---|---|
| Card pictures | Original faces drawn in SwiftUI, inspired by each card's look | Plaid has no card art, and shipping the issuers' artwork risks App Store rejection. A drawn face is recognisable and costs nothing. |
| Cards in the data | Existing `MoneyAccount` rows plus optional fields | A Plaid card and a hand-added card are the same thing to budgets and the advisor. A parallel `Card` model would duplicate names and balances. |
| A user's correction | `MoneyEntry.cardOverrideKey`, separate from `accountID` | `MoneyStore.ingest` rewrites `accountID` on every resend, so a correction stored there would be wiped. |
| "Always this card for this merchant" | `MerchantCardRule` rows, resolved at read time | Resolving at read time applies a new rule to history without a write pass, and needs no change to ingest. |
| Precedence | row override, then merchant rule, then Plaid's account | The most specific statement the person made wins. |
| Cards Plaid cannot see | Quick add with a card picker, plus statement import | Chosen as option C. |
| Statement PDFs | Read on the phone: PDFKit text, Apple's on-device model to rows, review before saving | Free and private. Server Claude was rejected for cost and the privacy plan. |
| CSV statements | Parsed directly, no model | Columns are columns. |
| Duplicates on import | Same cents and within 3 days of an existing row: flagged and unticked | Quick-added purchases will reappear on the statement. |
| Reward rates | Not in this slice | They belong to the advisor, and stale rates are worse than none. |

## 3. Data

All new stored fields are optional or defaulted, so installed stores migrate
in place (see the SwiftData lesson from the live-workout work).

- `MoneyAccount.cardProductID: String?`: a `CardCatalog` id.
- `MoneyAccount.faceColorHex: String?`: colour for a card not in the catalog.
- `MoneyAccount.isManual: Bool = false`: added by hand, never touched by sync.
- `MoneyAccount.cardKey` (computed): `externalID`, or `manual:<uuid>`.
- `MoneyEntry.cardOverrideKey: String?`
- `MerchantCardRule { merchantKey, cardKey, createdAt }`, merchant key
  lowercased and trimmed.
- Imported rows: `source = .manual`, `externalID = "import:<card>:<date>:<cents>:<merchant>"`,
  so importing one statement twice updates the same rows instead of adding them again.

`CardCatalog` is a plain Swift list: id, name, issuer, network, face style
(two colours, a pattern, ink colour), and name keywords for guessing the
product from Plaid's account name. A Plaid card with no chosen product gets
the guess; the person can change it.

## 4. Screens

- **Cards strip** under the Money masthead: each card's face with its month
  spend, then a "+" tile. Tap a card for a detail page of its charges.
- **Card chip** on every transaction row, beside the amount: a tiny face with
  the last four. Unknown card: a dashed chip with "?". Tapping the chip opens
  the picker; the row still opens the merchant page.
- **Card picker:** every card, "No card", and "Always use this card for
  <merchant>".
- **Card editor:** choose a known card from a grid of faces, or "Other" with a
  colour; name and last four for hand-added cards.
- **Quick add:** the existing add sheet gains a card picker, defaulting to the
  last card used.
- **Statement import:** choose a card, pick a PDF or CSV from Files, review
  the rows (duplicates unticked), import.

## 5. Not in this slice

- A share-sheet extension for statements (needs a new app target); Files picker only.
- Live updates, budget warnings, reward advice: slices 2 to 4.

## 6. Testing

Kit tests for: card key resolution precedence, rule matching, catalog
guessing, CSV parsing (signs, dates, quoted commas), duplicate flagging,
import idempotence, store card operations, schema defaults.
