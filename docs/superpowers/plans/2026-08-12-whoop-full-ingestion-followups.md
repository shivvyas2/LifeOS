# Whoop full ingestion: deferred findings

**Date:** 2026-08-12
**Status:** Open. None of these block anything; none were fixed.

Every task in `2026-08-12-whoop-full-ingestion.md` passed its own spec and
quality review, and three needed fix rounds which were closed. The findings
below were rated Minor and deferred rather than fixed.

The whole-branch review that would normally triage this list was not run: the
work was merged on request before it happened. So this list has been read by
nobody but its reviewers.

## Already in the code, and wrong

- **`DailyMetrics` doc comment contradicts the line below it.** The comment says
  height and max heart rate are "deliberately absent" two lines above
  `whoopMaxHR`. The intent was that the *profile's* max heart rate from the body
  endpoint is absent, which is a different thing from the day's measured max.
  Authoring error in the plan, propagated verbatim into the code.

- **`WhoopSync.sync()` counts timestamps, not days.** It returns
  `Set(recoveries.map(\.date) + cycles.map(\.date)).count`, which counts distinct
  instants. The figure surfaces in Settings as "Synced N days" and overcounts.
  Pre-existing, not introduced by this work. `WhoopDerivation.rederive()` shows
  the correct pattern.

- **`isCalibrating` is parsed and then dropped.** Whoop reports
  `user_calibrating` on a recovery, the DTO reads it, `WhoopRecoverySample`
  carries it, and nothing writes it, because no column was added. Either add
  `whoopIsCalibrating: Bool?` and write it, or stop parsing it. A calibrating
  score is not a low score, so if it is ever surfaced it must not collapse into
  one.

## Fidelity and correctness, low risk today

- **`WhoopRawSplit` re-encodes rather than preserving bytes.** It parses each
  record to `[String: Any]` and re-serialises. Unknown fields survive, which is
  the important part, but key order and whitespace can shift, so the archive is
  semantically faithful and not byte-faithful. The doc comment claims more than
  that and should be corrected. Only matters if exact-byte replay ever becomes
  load-bearing.

- **`WhoopSleepMath` treats an individually-missing stage as zero.** When some
  stage totals are present and others nil, the sum branch substitutes 0 for the
  missing ones, which sits awkwardly against the project rule that nil is not
  zero. Whoop populates the three stage totals together on a scored record, so
  the path is not currently reachable. Untested.

- **A page-cap truncation is only visible in `OSLog`.** `WhoopClient.get` stops
  at 20 pages and logs, but returns an array indistinguishable from a complete
  result, so nothing downstream can tell a partial sync from a quiet fortnight.

## Test gaps

- **The DTO to sample mapping has no end-to-end test.** `WhoopWireFormatTests`
  asserts the DTOs decode, but nothing calls `client.recoveries()` through a
  stubbed session and checks the resulting sample fields. A field swap inside a
  `sample` property would compile and pass everything. `StubURLProtocol` now
  exists, so this is cheap to close.

- **A test constructs `Stages(...)` through its memberwise initialiser**, so
  every future field added to `Stages` breaks that call site with no clue why.
  Decoding from a small JSON literal instead would make it immune.

- **`makeStore()` in `WhoopTests` is unused** after the derivation refactor.

## Shape and consistency

- **`WhoopArchive.store` is overloaded for single and batch**, where
  `MetricsStore` deliberately distinguishes `upsert` from `upsertBatch` so call
  sites are greppable and unambiguous.

- **The find-or-insert body is duplicated** between `WhoopArchive`'s single and
  batch paths. Two paths meant to mean the same thing are where drift starts,
  which this plan already learned once the hard way. Collapsing the single form
  into the batch one with a one-element array would remove it.

- **`upsertSleepRecord` and `upsertWorkoutRecord` save once per record**, against
  the batching rationale documented in `MetricsStore` itself. A 14 day sync is
  tens of main-actor saves.

- **`bodyMeasurement` duplicates the status-code switch** already in
  `WhoopClient.get`. A small private helper would remove it.

- **Sample memberwise initialisers interleave required parameters among
  defaulted ones**, so the defaults do not shorten most call sites.
