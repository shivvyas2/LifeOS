# Whoop data display

**Date:** 2026-08-12
**Status:** Approved

Supersedes sections 3, 4 and 5 of
`2026-08-11-whoop-ui-and-responsive-layout-design.md`. That spec's layout
foundation and iPad work (sections 1, 2, 5, 6) are unchanged and still
unimplemented; this document replaces only what it said about *which* Whoop
data is shown, because that was written when Whoop gave us six fields.

## Problem

The ingestion work landed and the UI did not move. What is stored versus what
is rendered, measured on 2026-08-12:

| Store | Fields | Read by the app |
| --- | --- | --- |
| `DailyMetrics` | 20 columns | 10 never read |
| `WorkoutRecord` | 13 fields | **none** |
| `SleepRecord` | 18 fields | **none** |
| `WhoopRawRecord` | full payloads | none, by design |

The Recovery screen renders four numbers: recovery percentage, HRV, day strain,
sleep duration. Every workout is synced, archived, rolled into `WorkoutRecord`
and invisible. Every night's sleep stages are stored and invisible.

Two record types exist that the superseded spec never anticipated, because they
did not exist when it was written.

## Goals

- Render the data already stored, without another sync-side change.
- Give workouts and sleep stages a home, since they are lists and compositions
  rather than daily scalars.

## Non-goals

- Responsive and iPad layout. Still specified in the superseded document, still
  outstanding, deliberately not bundled here.
- New API surface. Nothing here needs another endpoint.
- Rendering the raw archive. It exists for re-derivation, not for reading.

## Design

### 1. Baselines, because half these numbers are meaningless alone

SpO2 of 97.2% means nothing to a reader. SpO2 0.1 above your own fortnight
average means something. Whoop presents its vitals this way and the app has to
as well, or the numbers are decoration.

New `LifeOSKit/Sources/DesignSystem/TrendSeries.swift`, carried over unchanged
from the superseded spec:

```swift
public struct TrendPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double?     // nil is a gap, never a zero
}

public struct TrendSeries: Sendable, Equatable {
    public let points: [TrendPoint]
    public var average: Double?          // over non-nil values only
    public var latest: Double?
    public var deltaFromAverage: Double?
}
```

Pure over plain values, so it tests on macOS with no simulator. A day Whoop did
not report is a gap in the chart and is excluded from the average, never a zero.

### 2. Recovery: the day card

`RecoverySection` is rebuilt around a banded recovery number, then three
labelled groups. Every value is optional and renders an em dash when absent.

- **Recovery** in its band colour, with the band's name. Whoop's thresholds:
  below 34 low, 34 to 66 moderate, 67 and above high.
- **Sleep quality**: duration, performance %, efficiency %, consistency %,
  sleep debt.
- **Vitals**: SpO2, skin temperature, respiratory rate, each shown with its
  delta from the 14-day baseline. A vital with no baseline yet shows the reading
  alone rather than a fabricated delta.
- **Day**: average HR, max HR, calories, day strain.

Also renders "Synced 2h ago" from `syncedAt`, so a dead connection is visible
rather than silent.

### 3. Recovery detail: trends and sleep composition

Reached by tapping the day card. Two kinds of chart:

- **Line or bar series over 14 days** for recovery, strain, sleep duration,
  HRV, resting HR, with today highlighted and a dashed rule at the average.
- **A stacked bar per night** for sleep composition: light, REM, SWS and awake
  stacked to the night's total. This is the one chart that shows *structure*
  rather than quantity, which is the whole reason the stages were ingested. A
  short night and a fragmented night look identical on a duration chart and
  obviously different here.

Sleep composition reads `SleepRecord`, not `DailyMetrics`, since the stages live
on the record. Naps are excluded from the composition chart, which is a
night-by-night view, but they are stored and remain available.

### 4. Activity: the workouts list

`ActivitySection` keeps its steps, active time, energy and resting HR tiles and
gains a list of the selected day's workouts underneath.

Each row: sport name, duration, strain in its band colour, and a second line of
distance and average HR where present. A day with no workouts shows nothing
rather than an empty frame, since most days have none and a permanent empty
state is noise.

`percentRecorded` is deliberately not rendered as a number. It is used to mark a
workout Whoop only partly captured, so a low strain reads as incomplete rather
than as an easy session.

### 5. What stays stored and unrendered

`sportID` duplicates `sportName`. `altitudeGainMeters` and
`altitudeChangeMeters` are meaningful for exactly one kind of workout and would
be noise on every other row. `sleepCycleCount` and `noDataMinutes` are
diagnostic. All remain stored, and the archive means adding them later costs a
re-derive and no network traffic.

## Testing

Pure and terminal-runnable, matching the package convention:

- `TrendSeriesTests`: average ignores gaps; an all-gap series has a nil average
  rather than zero; `deltaFromAverage` sign and nil handling.
- `RecoveryBandTests`: the 33/34 and 66/67 boundaries, and the 0 and 100 ends.
- `SleepCompositionTests`: stages sum to the night's total; a night missing one
  stage still renders the others; a night with no stage data is excluded rather
  than drawn as a zero-height bar.
- `WorkoutRowTests`: formatting of duration, distance and a partly recorded
  session.

View bodies are verified by previews and a build, per the existing convention
that testing view bodies is low-value ceremony.

## Risks

- **Chart density on a phone.** Six series plus a stacked composition is a lot
  for a 402pt screen. If it reads as noise, the composition chart is the one to
  keep and the redundant duration series is the one to drop.
- **Vitals without a baseline.** A new connection has no 14-day history, so
  deltas are absent for the first fortnight. The design shows the bare reading
  rather than a delta against a half-formed average.
