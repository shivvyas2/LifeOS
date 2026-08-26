# The life sectors spine

Nine sectors, scored once a month, with the app arguing and the user deciding.

## Why

Shiv has been scoring himself by hand every month across nine sectors of life:
Family, Romance, Soul, Friends, Growth, Money, Mission, Body, Mind. The practice
works. What it lacks is evidence and memory: the score is a feeling recorded on
a page, with nothing underneath it and no way to see a year at a glance.

The app already holds a great deal of the evidence. What it does not have is any
concept of a sector at all. The word appears nowhere in the codebase.

## Scope

This is the first of three sub-projects. It builds the spine that the other two
plug into:

1. **This document.** The sector model, the scoring rules, the monthly close,
   the board, and navigation.
2. **The relational sectors in depth.** Family, Romance, Friends, Soul: what to
   log between closes, and whether to add mood tracking.
3. **Deepening what exists.** Money budgeting and targets, Mission PARA,
   goal horizons.

Each gets its own spec, plan, and implementation cycle.

## Decisions

Five questions settled the shape. They are recorded here with their reasoning,
because the reasoning is what a future reader will need.

### The app proposes, the user decides

Every month the app proposes a score per sector with the evidence behind it. The
user confirms or overrides. **The user's number is what gets stored.**

Full automation was rejected: Romance and Soul have no honest data source, so
those numbers would be invented, and one invented number costs trust in all
nine. A pure record-keeper was rejected as barely more than a spreadsheet.

### Monthly close, as a ritual

Sector scores change once a month. Between closes the board holds steady.

Today remains the daily surface. The two never compete: daily activity lives in
Today, monthly reflection lives in the board. A continuously drifting score was
rejected because it duplicates Today's job, invites gaming the number, and would
leave the four relational sectors frozen regardless, since nothing feeds them
daily.

### A fifth tab, board as hub

> **Amended by `2026-08-25-sector-screens-design.md`.** That project defines a
> sector screen as score history and past answers, which the Health, Money and
> Plan tabs do not show. All nine cards now open the same shape of screen, and
> Body, Money and Mission carry a link through to their full tab. The paragraph
> below records the original reasoning.

A Life tab holds the board. Tapping a sector opens its screen. For Body, Money
and Mission that screen **is** the existing Health, Money and Plan surface, not
a second copy of it. No sector has two homes.

This is purely additive. Nothing that works today moves, and the side rail work
on iPad is untouched.

### Rules score, the model explains

A deterministic per-sector rule computes the number. The existing on-device
`Engine` turns the evidence rows into a sentence.

The score is therefore testable, reproducible, and identical on every device,
and it costs nothing to produce. A model-judged score was rejected because the
same month could score differently on two runs and there would be no way to see
why a number moved. A score you cannot explain is a score you stop trusting.

### The close-time check-in fills the cold start

A sector with thin data asks two or three short questions during the close. The
answers become its evidence, stored and comparable next month.

This generalises the Friends check-in Shiv already described. It makes every
sector scorable in month one, and over time the answers themselves become the
trend line.

## Architecture

### A new `Sectors` module in LifeOSKit

Alongside `DesignSystem`, `Insights`, `Integrations` and `Persistence`. The
scoring rules live here because they are pure functions over stored data, which
makes them testable without a database or a view.

```
LifeSector      enum, nine cases. title, tint, icon, and whether the
                sector routes to an existing screen or a new one.

SectorScorer    protocol. Given a month, returns Evidence.
                One conforming type per sector, each small.

Evidence        rows of (label, raw value, normalised 0...1, weight)
                plus the computed score.
```

`Evidence` is the audit trail. The close screen renders those rows directly, so
the explanation cannot drift from the arithmetic that produced the number.

### Persistence

Two `@Model` types beside `MoneyEntry` and `PlanEntry`, and a `SectorStore`
following the existing `MetricsStore` / `MoneyStore` / `PlanStore` pattern.

```
SectorScore     sector, month, proposedScore, userScore, closedAt,
                archived evidence
CheckInAnswer   sector, month, questionID, answer
```

`month` is always `Calendar.startOfDay` of the first day of the month being
scored, matching the normalisation `MoneyEntry.date` already uses. A score
recorded on 3 September for August stores 1 August.

Two properties of this shape matter more than the fields themselves.

**`userScore` and `proposedScore` are stored separately and permanently.** The
gap between what the app computed and what the user actually felt is the most
interesting signal in the system. Collapsing them into one column would destroy
it. Over a year, a sector consistently scored below its rule is saying something
the rule cannot see.

**Evidence is archived onto the score, never recomputed.** If the step goal
changes in March, February's Body score must still show February's reasoning.
Recomputed history is history that lies.

### Where the evidence comes from

Existing sectors read what is already stored. No new logging is introduced by
this sub-project.

| Sector | Evidence available now | Strength |
|---|---|---|
| Body | goal days hit, sleep vs goal, exercise minutes, Whoop recovery, streak | strong |
| Money | income, spend, spend by category, month over month | strong |
| Mission | goals and habits moved vs open, by status | good |
| Growth | `UserGoals` targets met, goal completion rate | good |
| Mind | journal entry count and cadence, Coach usage | thin |
| Soul | journal entries | thin |
| Family, Romance, Friends | nothing | check-in only |

Five sectors get real rules on day one. Four are carried by the check-in. There
is no mood tracking in the app today; whether to add it is a question for
sub-project two.

### Prose

A new task beside `DailyBrief` in `Insights/Tasks`, run on the existing
on-device engine. It receives only the evidence rows and is instructed to
describe what changed, never to judge or to suggest a score.

`ModelAvailability` already handles Apple Intelligence being unavailable. In
that case the close shows evidence rows without a sentence, which is a degraded
presentation rather than a broken one.

## The scoring rule

Identical for all nine sectors:

1. Each evidence row normalises to 0...1.
2. Rows are weighted.
3. The weighted mean scales to 0...10 and rounds.

One arithmetic path for every sector means one thing to test and one thing to
explain. A sector with two rows behaves exactly like a sector with six.

**Weights live in code, not in settings.** User-editable weights on day one turn
every score into a dial to twist until the number is agreeable, which defeats
the purpose of an outside opinion. A wrong weight gets changed in code and
mentioned in the release.

**A sector with no evidence proposes nothing.** It does not propose zero. Zero
out of ten for Romance in month one is both wrong and demoralising.

## The board

Nine cards in a grid: `PastelFillCard` with a per-sector tint, `HeroNumeral` for
the score, and a six-month `RoundedBarChart` sparkline beneath. Two columns on
iPhone, three on iPad beside the side rail. All from the existing component kit,
so the board matches the app by construction rather than by imitation.

**There is no overall life score.** Averaging nine sectors produces a number
that sits near 6.5 forever and moves by fractions, reading as "nothing is
happening" even in a month where Friends collapsed and Body soared. Worse, it
invites protecting the average instead of attending to the weak sector. The
board header instead carries the two facts that prompt action: **the lowest
sector** and **the biggest mover since last month**.

## The close

A close always scores the month that just ended. From the first of September
onward the Life tab grows a "Close August" banner using the existing
`AlertBanner`. Not a modal, not a notification. It waits.

A month stays closable indefinitely. If August is never closed, the September
banner does not replace it: the oldest unclosed month is offered first, so a
gap in the history is always visible and always fillable rather than silently
lost.

The close is nine steps, one sector per screen:

```
  SOUL                          4 of 9

  proposed        6            last month  7

  journal entries        5  █████░░░░░  0.42
  entries per week     1.2  ████░░░░░░  0.40

  "Fewer journal entries than July."

  your score   0 1 2 3 4 5 [6] 7 8 9 10

  [ skip ]                        [ next ]
```

For a thin-data sector the check-in questions come first and the proposal is
computed from those answers, so every step has the same shape.

**Leaving mid-close is normal, not an error state.** Each sector commits as the
user passes it. Returning a week later resumes at the first unscored sector. A
skipped sector stays genuinely unscored rather than defaulting to its proposal,
because a score nobody looked at is noise in the history. An unscored sector
shows a dash on the board.

## Testing

Following the existing suite and its `#expect` style.

- One test per scorer: a fixture month in, expected evidence rows and score out.
  Pure functions over value types, so no container and no async.
- Cold start: every scorer with zero data returns no proposal rather than zero.
- Archived evidence: change a goal, recompute, confirm last month's stored
  evidence is untouched.
- Partial close: score four sectors, abandon, resume, confirm it lands on sector
  five with the other four unchanged.
- `userScore` survives independently of `proposedScore` across a recompute.
- The shared rule: normalisation bounds, weighting, rounding at boundaries.

## Out of scope

- Mood tracking, and any new between-close logging for the relational sectors.
- Money budgeting, targets, loans.
- Mission PARA, and the daily / monthly / yearly / long-term goal horizons.
- A single combined life score.
- User-editable weights.
- Notifications and reminders to close the month.
