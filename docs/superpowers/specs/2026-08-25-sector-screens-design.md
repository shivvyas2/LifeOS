# Sector screens

Nine cards you can tap, each opening what that sector has actually looked like over time.

## Why

The life sectors spine gave every sector a score and a monthly close. It did not
give six of the nine sectors anywhere to live. Family, Romance, Friends, Soul,
Growth and Mind exist only as a number on a card, and no card is tappable at
all. The board answers "how am I doing" and nothing answers "how has this been
going".

The close already stores everything needed to answer the second question. Each
`SectorScore` carries its month, the proposal, the person's own score, and the
evidence rows frozen at close time. Each `CheckInAnswer` carries a question, an
answer, and a month. That is a year of history nobody can currently read.

## Scope

Presentation only. This project adds no new models, no new logging, and no new
data collection. It reads what the close already writes.

It is the second of three sub-projects. The third, deepening Money budgeting,
Mission PARA and the goal horizons, is unchanged and still outstanding.

## Decisions

### The screen is for looking back, not for logging

A sector screen shows the trend, the reasoning behind each close, every past
check-in answer side by side, and the person's own notes.

Between-close logging was rejected for now. It would mean a new habit per
sector and new models per sector, and it would make an unlogged sector look
emptier than it is. Reading what the close already collects works from month
one and ships as one coherent piece.

### All nine sectors get the same screen, and this amends an earlier decision

**This supersedes the "board as hub" decision in
`2026-08-25-life-sectors-spine-design.md`.**

That spec said tapping Body, Money or Mission opens the existing Health, Money
or Plan surface, so that no sector has two homes. That decision was made when
"a sector's screen" meant the sector's data, which those tabs already show.

This project defines a sector screen as **score history and past answers**,
which those tabs do not show anywhere. Routing three of the nine cards away
from that content would mean three sectors have no view of their own history,
and three of nine cards behaving differently from the rest.

So: every card opens the same shape of screen. Body, Money and Mission
additionally carry a row that switches to their full tab. The no-two-homes
concern is answered by that link rather than by withholding the screen.

### Observations are computed, never model-written

The screen surfaces short observations, for example that the same answer has
been given several months running, or that the person has scored themselves
persistently below what the rule proposed.

These are deterministic rules, consistent with the spine's decision that the
rule owns the number and the model only describes. No model call is made from
this screen at all, which also keeps it free and instant.

Two rules ship, both requiring three consecutive months so that a single
unusual month never triggers one:

- **A repeated answer.** The same answer given to the same question three
  months running.
- **A standing gap.** The person's own score below the proposal for three
  months running, which says the rule is measuring something they do not feel.
  This is the signal the spine kept `proposedScore` and `userScore` in separate
  columns to preserve, and this screen is the first place it is read.

## Architecture

### `SectorHistory` in the `Sectors` package

A pure value type assembled from arrays of stored values, in the same shape as
every scorer: no container, no async, no throwing. This matters because
`LIfeOS.xcodeproj` has **no test target**, so any logic placed in a view model
cannot be unit tested at all. Everything decidable lives in the package.

```
SectorHistory
  sector        LifeSector
  months        [MonthEntry]   oldest first
  questions     [QuestionTrack]
  notes         [Note]         newest first
  observations  [String]

MonthEntry     month, userScore, proposedScore, evidenceRows
QuestionTrack  questionID, prompt, answers by month
Note           month, questionID, text
```

`SectorHistory.build(sector:scores:answers:calendar:)` takes the stored values
and returns the assembled history. The view model fetches and calls it.

### The four bands

1. **Trend.** The last twelve months of the person's own score.

The trend shows twelve months and the answer tracks show six. That is
deliberate, not an oversight. A score is one glyph per month, so a year reads
at a glance and is where a slow drift becomes visible. An answer is a phrase,
so six is already the most that stays readable across a phone's width. The two
bands answer different questions and are sized for their own content.
2. **This month's reasoning.** The archived evidence rows for the most recent
   closed month, rendered exactly as they were at close time. This is the
   spine's archive promise doing visible work: open August in December and
   August's reasoning is what appears, even if a goal changed since.
3. **Answers over time.** One row per question, the last six months across it,
   oldest to newest, horizontally scrollable. A column of "barely, barely,
   some" says something no single score does.
4. **Notes.** Free-text answers, newest first, each labelled with its month.

Bands with no data are omitted rather than rendered empty. A sector closed once
shows a trend of one bar and no answer tracks if it has no questions.

### Navigation

The Life tab gains a `NavigationStack`. Each card becomes a link pushing
`SectorDetailScreen`.

`AppTab` is private to `RootView` and stays that way. The board receives a
closure for requesting a tab change, so it does not learn how the tab bar
works. Body, Money and Mission render a row that calls it; the other six do
not.

### Components

No new design system components. `RoundedBarChart` for the trend, whose `Bar`
already takes a `Date` id, a label and an optional value, which is exactly a
month and a score. `PastelFillCard` for the header in the sector's hue.
`SoftCard` per band. `Space.x2` and `Space.x3` for rhythm. The screen should
look like it was always there.

## Testing

`SectorHistory` gets real coverage, since it holds every decision:

- Months are ordered oldest first, and only closed months appear.
- A sector with no closed months produces an empty history rather than nil bands.
- A sector closed once produces one month and no observations.
- Evidence rows come from the archive, not from a recomputation.
- Answers align to their months, and a month with no answer to a question
  leaves a gap rather than shifting later answers left.
- The repeated-answer rule fires on three identical consecutive answers and not
  on two.
- The score-gap rule fires when the person's score sits below the proposal for
  three months running, and not on a single month.

The screens themselves are untestable here, which is the reason the assembly
logic is not in them.

## Out of scope

- Any new logging or new models.
- Model-written prose on this screen.
- Editing a past score or a past answer.
- Money budgeting, Mission PARA, goal horizons. Sub-project three.
- Mood tracking, still unresolved from sub-project one.
