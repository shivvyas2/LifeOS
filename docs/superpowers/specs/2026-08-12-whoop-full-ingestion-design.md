# Whoop full ingestion: archive, then derive

**Date:** 2026-08-12
**Status:** Approved

## Problem

The Whoop integration fetches three endpoints and keeps six numbers. Whoop
returns considerably more, and two of the app's own models were built for that
surplus and have never been written to.

Concretely, what is taken today:

| Endpoint | Kept | Discarded |
| --- | --- | --- |
| `/v2/recovery` | recovery %, resting HR, HRV | SpO2, skin temperature |
| `/v2/activity/sleep` | performance %, asleep minutes | sleep stages, respiratory rate, efficiency, sleep need, sleep debt, disturbances |
| `/v2/cycle` | day strain | average HR, max HR, kilojoules |
| `/v2/activity/workout` | nothing: never called | every workout |

`WorkoutRecord` and `SleepRecord` exist in `SourceRecords.swift` with the header
"source records roll *up* into `DailyMetrics`". Nothing writes to either.

Three defects surface alongside the gap:

1. **Pagination is decoded and discarded.** `WhoopDTOs.Page.next_token` is
   parsed and never read, and `get` sends `limit=25`. Fourteen days of daily
   records fit under 25, so this is invisible today. Workouts do not fit: an
   active fortnight exceeds 25 easily, and the result is a silently partial
   sync with no error.
2. **Asleep time is derived by subtraction.** `in_bed - awake` is a proxy for
   `light + SWS + REM`. It drifts whenever Whoop counts time as neither.
3. **One endpoint's field names are unverified, and a stale comment claims all
   of them are.** `WhoopClient.swift:5` says nothing in the file "has been
   exercised against a live token". That is no longer true and has not been true
   since `c1e90dd`: that commit captured real v2 payloads into
   `WhoopWireFormatTests.swift`, whose header records them as "captured from a
   live Whoop v2 response on 2026-08-10. Field names and the timestamp format
   are real". The comment was left behind by the very commit that disproved it.

   So recovery, sleep and cycle are verified, and their fixtures already contain
   every field this design adds. Only `/v2/activity/workout` is genuinely
   unknown, because it has never been called. The stale comment is corrected as
   part of this work.

## Goals

- Fetch everything the four endpoints return, and retain it.
- Fill `WorkoutRecord` and `SleepRecord`.
- Verify the wire format against real payloads before finalising the models.

## Non-goals

- Uploading anything to Supabase. The `whoop_raw` table stays waiting for the
  data-sync layer, which does not exist and is not built here.
- New UI. This makes data available; rendering it is the separate approved
  responsive/UI spec.
- `/v2/user/measurement/body`. Height and max HR are profile facts, not daily
  signal, and nothing would read them.

## Design

### 1. Archive, then derive

```
WhoopClient  ->  WhoopRawRecord  ->  WhoopDerivation  ->  DailyMetrics
  (wire)          (archive)           (pure)              WorkoutRecord
                                                          SleepRecord
```

New `LifeOSKit/Sources/Persistence/WhoopRawRecord.swift`:

```swift
@Model
public final class WhoopRawRecord {
    #Unique<WhoopRawRecord>([\.kind, \.externalID])
    public var kind: String        // recovery | sleep | cycle | workout
    public var externalID: String
    public var payload: Data       // the record's JSON, exactly as received
    public var receivedAt: Date
}
```

The columns deliberately mirror the existing Supabase `whoop_raw` table, so
moving the archive server-side later is a copy rather than a redesign. `kind` is
a `String` and not an enum for the reason the migration already gives: a new
collection should land as data, not as a failed insert.

This enables `rederive()`: replay the archive into the metric tables with no
network call. That is the capability the schema comment asks for, that "a
derivation bug found six months from now must be fixable without asking for the
data again".

Sync becomes: fetch, archive, derive from the archive. Deriving from the archive
rather than from the in-flight response means the archive path is exercised on
every sync and cannot rot.

`WhoopDerivation` replaces `WhoopIngestion` and takes its place in
`LifeOSKit/Sources/Integrations/`, next to the other Whoop types and importing
`Persistence` as `WhoopIngestion` does today. It keeps that type's two
load-bearing properties: every write goes through `MetricsStore.upsertBatch`,
and a nil field never overwrites a stored value. `WhoopIngestion` is deleted
rather than kept alongside, so there is one derivation path and not two.

### 2. Pagination

`WhoopClient.get` becomes a loop that follows `next_token` until it is nil,
accumulating records. A page cap of 20 bounds a pathological response. Reaching
the cap is logged, because a silent truncation reads as a complete sync.

### 3. Sleep

`asleepMinutes` is computed as `light + SWS + REM` when the stage summary is
present, falling back to `in_bed - awake` when it is not. The fallback is kept
rather than removed so a missing stage summary degrades instead of nulling the
field.

`SleepRecord` gains optional `performancePercentage`, `lightMinutes`,
`swsMinutes`, `remMinutes`, `awakeMinutes`, `respiratoryRate`,
`sleepNeedMinutes`, `sleepDebtMinutes`, `disturbanceCount`.

Naps continue to be excluded from the day roll-up, as they are today, but are
now archived and stored as `SleepRecord`s so a nap is visible rather than
dropped on the floor.

### 4. Workouts

`/v2/activity/workout` joins the sync. `WorkoutRecord` already has `externalID`,
`start`, `durationMinutes`, `activityName` and `energyKcal`; it gains optional
`strain`, `averageHR`, `maxHR` and `distanceMeters`.

### 5. `DailyMetrics` columns

Four new optional columns: `spo2Percentage`, `skinTempCelsius`,
`respiratoryRate`, `whoopCalories`.

Restraint is deliberate. Because the raw payload is archived, a column added
later costs a re-derive and no network traffic at all, so there is no reason to
add columns nothing renders. Everything else Whoop returns is still captured, in
the archive, where it is free.

### 6. Migration

Every new property is optional and the one new model is additive, so SwiftData's
implicit lightweight migration covers this and no `VersionedSchema` or
`SchemaMigrationPlan` is required. `LifeOSContainer.schema` gains
`WhoopRawRecord.self`.

This constrains the design rather than merely describing it: **no new property
on an existing model may be non-optional**, because that is precisely what turns
a lightweight migration into a store that will not open.

### 7. Verifying the wire format

Recovery, sleep and cycle need no verification step. Their fixtures in
`WhoopWireFormatTests.swift` were captured live and already carry every field
this design reads, so those DTOs are widened test-first against fixtures that
exist today.

Only `/v2/activity/workout` needs capture:

1. A temporary dump path in `WhoopClient.get`, behind a `WHOOP_DUMP_PAYLOADS`
   environment check, logs the workout endpoint's raw JSON through `OSLog`.
2. The user runs one sync and provides the output.
3. The workout DTO is written against that real payload, and a fixture is added
   to `WhoopWireFormatTests` alongside the other three.
4. The dump path is deleted in the same change that lands the workout DTO.

Step 4 is not optional. A debug path that logs a user's biometrics is not
something to leave behind a flag.

Because only one endpoint is gated, the rest of the work does not wait on it.
`WhoopClient.swift:5` is rewritten to say what is actually true: three
collections are fixture-backed, and a decode failure means the API moved.

## Testing

Pure and terminal-runnable, matching the existing package convention:

- `WhoopDerivationTests`: stage summing; fallback when the stage summary is
  absent; naps excluded from the day roll-up but still stored; workout mapping;
  kilojoule to kcal conversion.
- `WhoopPaginationTests`: follows `next_token`; stops on nil; respects the page
  cap and logs when it hits it.
- `WhoopArchiveTests`: archive then `rederive()` reproduces the same
  `DailyMetrics` as the direct path; re-archiving the same `externalID` updates
  rather than duplicating.
- One decoding fixture test per endpoint, built from the real payloads captured
  in the verification step.

## Risks

- **The workout field names may differ from the documented shape.** That is the
  reason for the capture step, and why the workout model is finalised after it
  rather than before. The other three collections carry no such risk: their
  fixtures are real.
- **Archive size.** A JSON payload per record per day is small, but unbounded
  over years. Not solved here; noted so it is a deliberate omission rather than
  an oversight.
- **Whoop rate limits.** Following pagination increases request count. The page
  cap bounds it, and the archive means a re-derive never costs a request.
