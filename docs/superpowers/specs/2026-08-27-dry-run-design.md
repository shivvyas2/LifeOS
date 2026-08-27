# Dry Run Design Spec

**Date:** 2026-08-27
**Status:** Approved in conversation; this document records the decisions.

**Scope of this document:** A second mode for the Life board that scores the month you are currently living as a reachable range rather than a single number: a floor if you coast, a ceiling if you finish at your own targets, and a ranking of which lever still moves the number most. Also covers answering a sector's check-in questions before close, which is what gives the three relational sectors anything to show in flight. Does not cover sliders, coach narration, calendar-derived scoring for the relational sectors, or notifications; those are Section 11.

## 1. What this is

`LifeBoardViewModel` renders the most recently *completed* month, and `CloseSchedule` only ever offers a month in the past. The app has nothing to say about the month in progress. That is the hole this fills.

Every sector card gains a second reading: not "you scored 6" but "you are between 6 and 8, and there are four days left to decide which." The floor is what you close at if the rest of the month looks like the part you have already lived. The ceiling is what you close at if every remaining day hits the targets you set. The gap between them is the only part of the month still yours to move, and it narrows on its own as the month burns down.

The feature is arithmetic, not prediction. There is no model call, no network, and no new scoring rule.

## 2. Decisions on record

These were put as questions and answered; they are settled.

**No new scoring math.** Every number shown comes from `SectorEvidenceFactory.evidence(for:inputs:answers:)`, the same call the real close makes. Dry Run's entire job is to build alternate `MonthInputs` and re-run that function. This is the load-bearing decision: the moment a projection computes a score by any other path, the band and the close can disagree, and a band that contradicts the close is worse than no band. `SectorEvidenceFactory` is already pure, non-throwing and non-awaiting by deliberate design, which is what makes this possible without a new seam.

**The band lives on the Life board, behind a segmented control.** Closed (today's behaviour, last completed month) and In flight (this month, bands). Same nine cards, same grid, same palette. A separate screen would duplicate the board's visual grammar and bury the feature; the sector detail alone would hide it until someone taps in.

**The ceiling is your own targets.** Remaining days are filled at `GoalTargets`: your sleep goal, your exercise goal, your steps, your water. Not a theoretical maximum, which produces ceilings nobody reaches and reads as noise, and not your personal best, which is undefined in month one. A ceiling built from your own targets is reachable by definition, and it makes target-setting consequential for the first time.

**Coast means continuing at your current pace, not stopping.** See Section 3; this is the subtle one.

**The three relational sectors become answerable in flight.** Family, Romance and Friends have no tracked data at all, so without this a third of the board is dead in its flagship view. Tapping the card asks the same `CheckInQuestion` set the close asks, and the answer is written to the current month. See Section 8.

**Tapping an in-flight card shows a leverage readout, not sliders.** Floor and ceiling evidence side by side, plus a ranking of which single lever moves the score most, computed by re-running the factory once per lever. Sliders are fiddly on a phone and invite fantasy inputs; a sensitivity ranking answers the question the person actually has, which is what to do next.

## 3. The projection model

Given the current month's real `MonthInputs`, a `MonthProgress` splitting the month at today, and `GoalTargets`, three variants are built:

| Variant | Remaining days are filled | Produces |
|---|---|---|
| Coast | at your month-to-date pace | the floor |
| Perfect | at `GoalTargets` | the ceiling |
| One lever perfected | that lever at target, everything else coasting | the leverage ranking |

**Coast is defined as continuing at your current daily rate, not as an empty tail.** For Body the two are nearly identical: `BodyScorer` counts only days that have data, so logging nothing leaves the ratio and the averages untouched. For Money they are opposites. Spending nothing for the rest of the month is the *best* case, not the worst, so an empty tail would compute the floor above the ceiling and invert the card. One definition applies to every sector, and it is the one that reads correctly for spend: the rest of the month looks like the part already lived.

**Decided** is defined per sector as `1 - (ceiling - floor) / 10`, clamped to `0...1`. It is literally the share of the score that is no longer movable. The board header shows the mean across the nine sectors. No other definition of "decided" appears anywhere in the feature.

## 4. New types

All pure, all in the `Sectors` package beside the scorers, all unit tested without a container.

```
MonthProgress
  init(window: MonthWindow, now: Date, calendar: Calendar)
  window         MonthWindow
  elapsedDays    Int      today counts as lived
  remainingDays  Int      0 for any month that has ended
  isInFlight     Bool
  remainingDates(calendar:) -> [Date]

ProjectedInputs
  static func coasting(_ inputs: MonthInputs, progress:, calendar:) -> MonthInputs
  static func perfect(_ inputs: MonthInputs, progress:, calendar:) -> MonthInputs
  static func perfecting(_ lever: Lever, in: MonthInputs, progress:, calendar:) -> MonthInputs

Targets are read from `inputs.targets`; none of these take them separately.
Every one returns a value. Money's missing ceiling is a rule about one
sector's score, not about a month's inputs, so it is decided in `SectorBand`
where it can be stated once (Section 5).

SectorBand
  sector          LifeSector
  floor           Int?     nil when the sector has no evidence at all
  ceiling         Int?     nil when no ceiling is defensible (Section 5)
  floorEvidence   Evidence
  ceilingEvidence Evidence
  decided         Double?

Lever
  enum { sleep, exercise, steps, water, journal, habits, spend }
  static func all(for: LifeSector) -> [Lever]
  func tracked(in: MonthInputs) -> Bool

Leverage
  static func ranked(for sector:, inputs:, progress:, answers:, calendar:) -> [LeverDelta]
  LeverDelta { lever: Lever, delta: Double }

`delta` is in points on the 0...10 scale and needs sub-point resolution, so
`Evidence` gains `proposedValue: Double?`, the unrounded weighted mean, and
`proposedScore` becomes its rounded form. The two cannot then disagree.
```

`floor` and `ceiling` are optional and are never zero when absent. This follows the rule `Evidence.proposedScore` already sets: a sector with no evidence has not been judged badly, it has not been judged.

## 5. Sector-specific rules

**Money has no ceiling without buckets.** With no `BudgetReport` there is no defensible best remaining spend. Zero is fantasy and any other figure is invented. `SectorBand` reports no ceiling for that case, the card shows a floor alone, and the copy points at bucket setup. This turns the honest gap into a funnel toward budgets rather than a fabricated number.

With buckets, the perfect variant spends the remaining bucket allowance across the remaining days, so `BudgetReport.meanAdherence` reaches 1.0 without pretending spending stops.

**Ceilings never assume other people move.** `MissionScorer` projects every remaining habit-day as ticked, which is yours to control, and leaves goal statuses exactly as they are. `progressFraction` already returns nil for blocked, so waiting on someone else stays out of the arithmetic in the projection for the same reason it stays out at close.

**Growth** recomputes targets-met from the projected readings through the existing `SectorEvidenceFactory.growthTargets` path and leaves goal statuses alone, same as Mission.

**Mind and Soul** project a journal entry on every remaining day for the ceiling and hold journal days flat at the month-to-date rate for the floor. Their check-in rows use whatever has been answered, per Section 8.

**An untracked metric produces no lever.** If water was never logged this month, water is not offered as something that moves the score, mirroring `BodyScorer` dropping an absent metric rather than scoring it a failure.

**`GoalTargets.default` is disclosed.** Someone who never set targets still gets a ceiling, derived from numbers they did not choose. The sheet says so in one line and links to target setting, otherwise the ceiling is quietly someone else's.

## 6. The refactor: MonthInputsLoader

`MonthlyCloseViewModel.loadMonthInputs()` is private, roughly 55 lines, and sits inside a 337-line view model. The in-flight board needs the same thing for the current month.

It moves to `Sectors/MonthInputsLoader.swift` as `load(context:month:now:calendar:) throws -> MonthInputs`, with the previous-month window logic it already carries. `MonthlyCloseViewModel` calls it instead of owning it.

The new `now` parameter fixes a bug the in-flight case exposes. `PlanStore.recentTicks` returns one flag per day in its window and reads a day with no tick as a miss, so running the window to the last day of a month still being lived scores every day still to come as a habit already broken. On the 27th of a 31 day month that alone caps the rate at 27/31 however perfect the person has been. Habits are now judged only across the days already lived. A month that has ended is unaffected, which the characterization test pins.

This is behaviour-preserving and is covered by a characterization test written *before* the move (Section 9). It also puts store-reading where it can be tested: `LifeBoardViewModel`'s own doc comment records that view models stay thin because the app has no test target, and this is that rule applied to the loader.

## 7. Board surface

`LifeBoardViewModel` gains `mode: BoardMode` (`.closed`, `.inFlight`) and `bands: [SectorBand]`, built by calling `MonthInputsLoader`, then `ProjectedInputs`, then `SectorBand`. No arithmetic enters the view model; it stays a wiring layer.

`SectorStack` renders a card two ways: a number when closed, a floor-to-ceiling track when in flight. A sector with a nil floor renders as "not yet read" rather than as a zero.

The header differs by mode. `BoardSummary(scores:previous:)` compares two closed months and has no meaning in flight, so in-flight mode shows "N days left" and the mean decided percentage instead of stretching a type that means something else.

`InFlightSectorSheet` is the new detail surface: the band, the floor and ceiling evidence tables, and the ranked levers.

## 8. Answering early

Tapping a sector whose evidence is thin offers its `CheckInQuestion` set inline, and the answer is written with the existing `SectorStore.saveAnswer(sector:month:questionID:answer:)` against the **current** month.

Nothing on the write path changes. `CheckInAnswer` is already keyed by `(sector, month, questionID)`, `saveAnswer` already upserts ("Answering again replaces"), and `MonthlyCloseViewModel.advance()` already reloads stored answers for the sector-month into `answers` before recomputing. An answer given on the 12th is therefore visible, scored, and revisable at close with no migration, no new model, and no change to the close.

One view extraction is needed: `MonthlyCloseScreen.questionView(_:model:)` is bound to `MonthlyCloseViewModel` and cannot be reused as-is. It becomes `CheckInQuestionView(question:answer:onAnswer:)`, used by both the close and the in-flight card. `AnswerPersistence.isImmediate` governs debouncing in both places, unchanged.

## 9. Testing

All new tests are pure and live in `SectorsTests`.

- `MonthProgress`: the split at today; the last day of the month leaves zero remaining; a month already ended leaves zero, so the band collapses onto the closed score; a month not yet started leaves every day remaining.
- `ProjectedInputs`: coasting preserves month-to-date averages; perfect fills remaining readings at targets; money coasting extends the daily spend rate; money perfect is bounded by `BudgetReport`; money perfect returns nil with no buckets.
- `SectorBand`: ceiling is greater than or equal to floor across sample inputs; a sector with no evidence yields nil for both rather than zero; decided is 1.0 when the band has collapsed.
- `Leverage`: ranking orders by delta; a lever already at target contributes zero; an untracked metric produces no lever.
- `MonthInputsLoader`: a characterization test locking the current output for a fixed month, written before the extraction and unchanged by it.

## 10. Risks

**A band on day two is nearly 0 to 10.** Wide, and on first read it looks broken. The position taken here is that this is the honest signal and the copy says it plainly, but it needs looking at on a device before the visual is settled.

**Sparse trackers get nil bands.** No Whoop and no HealthKit means Body and Growth have nothing to project. They get the same "not yet read" treatment as the relational cards.

**Leverage cost.** One extra `SectorEvidenceFactory` call per lever per sector, on tap only, over data already in memory. Negligible, but it should not be moved to board load.

## 11. Out of scope

Deliberately excluded so the first release is one idea:

- Sliders over the levers.
- Coach narration or tool calls off the back of a band.
- Calendar-derived scoring for Family, Romance and Friends. This is the most novel follow-on and the one that would remove the check-in dependency entirely, but it means new scorers and a change to what those sectors measure.
- Notifications and nudges.
- Sharing and widgets.
