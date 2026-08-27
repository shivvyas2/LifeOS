# Fitbit Integration Implementation Plan (slices 1 to 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Fitbit as a second wearable source for the daily spine, and replace the two-writer merge rule with a source-ranked arbiter that can express which strap owns a metric.

**Architecture:** Provenance is recorded per metric per day in a new `DailyMetrics.sourcesData` bag, and every writer (Apple Health, Whoop, and later Fitbit) merges through `MetricArbiter` instead of writing columns directly. Fitbit's OAuth tokens live server-side in `fitbit_connections` behind a row lock, because Fitbit refresh tokens rotate and are single use; two Edge Functions own the credential and the quota, and the device does all interpretation from raw payloads.

**Tech Stack:** Swift 6, SwiftData, swift-testing (`import Testing`, `@Test`, `#expect`), SwiftUI, Supabase Edge Functions on Deno, Postgres with RLS.

**Spec:** `docs/superpowers/specs/2026-08-27-fitbit-integration-design.md`

## Global Constraints

- Platforms: iOS 26.0 / macOS 26.0, `swift-tools-version: 6.0`. Set in `LifeOSKit/Package.swift`; do not change.
- Swift tests run from the `LifeOSKit` directory: `swift test --filter <SuiteName>`.
- Deno tests run from the repo root: `deno test supabase/functions/_shared/<name>_test.ts`.
- Test framework is swift-testing, not XCTest. `import Testing`, `@Suite`, `@Test`, `#expect`, `#require`.
- Module layering: `Persistence` has no dependencies. `Integrations` depends on `Persistence`. `Persistence` must never import `Integrations`, so `DailyMetrics` stores source names as raw `String`, and only `Integrations` knows the `MetricSource` type.
- Commit style: conventional commits, `type(scope): imperative summary`, short body explaining what and why. No em dashes in commit messages. No Claude or AI attribution of any kind, no `Co-Authored-By` trailer.
- Never commit to `main`. All work lands on `feat/fitbit-integration`.
- A missing value and a zero are never the same thing. Nothing in this plan may write a zero to stand in for a missing reading.
- Fitbit quota is 150 requests per hour per user, reported by the `Fitbit-Rate-Limit-Remaining` and `Fitbit-Rate-Limit-Reset` response headers.
- The Fitbit access token must never be returned to the device.

---

## Behaviour changes this plan makes deliberately

Slice 1 is a refactor that preserves every existing merge outcome except one. Read this before starting, because a reviewer who does not know it will read the exception as a bug.

**Preserved exactly:** Whoop still wins resting HR, HRV, SpO2, respiratory rate and sleep minutes over Apple Health. Apple Health still wins steps, active energy and exercise minutes, and still corrects its own earlier count the same day. A typed weight or water figure still survives a sync.

**Changed on purpose:** a weight or water value that Apple Health itself wrote can now be corrected by a later Apple Health reading. Today it is frozen by `fillGapsOnly` and sticks until something clears it. Under ranks, equal rank overwrites, so Health corrects its own value while a typed one stays protected at a higher rank.

---

## Deviations from the spec

Three, each deliberate. Anyone reviewing the plan against the spec should know they are choices, not oversights.

1. **The spec names `fitbit_token_test.ts` and `fitbit_sync_test.ts`.** This plan puts all the Deno tests in one `_shared/fitbit_test.ts` instead, because that is the repo's existing pattern: `plaid.ts` holds the decisions and `plaid_test.ts` tests them, while `plaid-sync/index.ts` has no test of its own. The testable logic is extracted into `_shared/fitbit.ts` and covered there; the `index.ts` files stay thin enough to read.
2. **`FitbitBackfill.swift` is not built here.** The spec lists it, but the quota arithmetic it describes lives server-side, where the `Fitbit-Rate-Limit-Remaining` header actually arrives. Slice 3 syncs a single 30-day window, which fits inside the quota with room to spare, so the cursor is not needed until slice 4 adds the per-date collections. Task 14 stops the fetch loop on low headroom; the resumable cursor is slice 4's.
3. **Sleep stages become `claimedByWearable` in slice 3, not slice 1.** Slice 1 stays a behaviour-preserving refactor. Until Fitbit reports stages, Apple Health is their only writer and the rank makes no difference, so moving them early would be an untested behaviour change bundled into a refactor.

---

## File Structure

**Slice 1, the arbiter:**

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Integrations/MetricSource.swift` (new) | The `MetricSource` enum and `SourceRanking`, which turns a source plus a metric into a rank. |
| `LifeOSKit/Sources/Integrations/MetricArbiter.swift` (new) | The merge decision, as a pure function. Replaces `HealthFill`. |
| `LifeOSKit/Sources/Integrations/HealthFill.swift` (delete) | Superseded. |
| `LifeOSKit/Sources/Persistence/DailyMetrics.swift` (modify) | Adds `sourcesData` and its accessors. |
| `LifeOSKit/Sources/Integrations/HealthMetric.swift` (modify) | `precedence` retires; `claimedByWearable`, `acceptsManualEntry`, `healthIsAuthoritative` replace it. |
| `LifeOSKit/Sources/Integrations/HealthApply.swift` (modify) | Merges through the arbiter and records provenance. |
| `LifeOSKit/Sources/Integrations/WhoopDerivation.swift` (modify) | The contested columns merge through the arbiter instead of assigning directly. |

**Slice 2, the connection:**

| File | Responsibility |
|---|---|
| `supabase/migrations/20260829090000_fitbit_connections.sql` (new) | One row per user, RLS with no policies, service role only. |
| `supabase/functions/_shared/fitbit.ts` (new) | Pure helpers: scope list, token request form, failure classification. |
| `supabase/functions/fitbit-token/index.ts` (new) | Authorization code exchange and refresh. Sole writer of the rotating token. |
| `LifeOSKit/Sources/Integrations/FitbitOAuth.swift` (new) | PKCE authorize URL, redirect parsing, `state` checking. |
| `LifeOSKit/Sources/Integrations/FitbitAuthStore.swift` (new) | Pending verifier and `state` in the Keychain. No tokens: they never reach the device. |
| `LIfeOS/Features/Settings/ViewModel/FitbitConnectionViewModel.swift` (new) | Connection state for the card. |
| `LIfeOS/Features/Settings/Model/AppConfig.swift` (modify) | Fitbit client id, redirect URI, function endpoints. |
| `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift` (modify) | The fourth card. |

**Slice 3, the range collections:**

| File | Responsibility |
|---|---|
| `supabase/functions/fitbit-sync/index.ts` (new) | Fetches the range collections under the row lock, returns raw payloads. |
| `LifeOSKit/Sources/Integrations/FitbitWireFormat.swift` (new) | Decoding, one type per collection. |
| `LifeOSKit/Sources/Integrations/FitbitDerivation.swift` (new) | Payloads to `HealthMetric` values on the spine. |
| `LifeOSKit/Sources/Integrations/FitbitSync.swift` (new) | Calls the function, archives raw, derives. |

Slices 4 and 5 (per-date collections with the quota cursor, and the primary wearable picker) are deliberately not planned. They depend on what slice 3 teaches about Fitbit's real payloads.

---

# Slice 1: the arbiter

## Task 1: MetricSource and the ranking

**Files:**
- Create: `LifeOSKit/Sources/Integrations/MetricSource.swift`
- Modify: `LifeOSKit/Sources/Integrations/HealthMetric.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/MetricSourceTests.swift`

**Interfaces:**
- Consumes: `HealthMetric` (existing enum, `Integrations`).
- Produces: `MetricSource` (`String`-raw enum, cases `manual`, `whoop`, `fitbit`, `appleHealth`); `SourceRanking(primaryWearable:)` with `func rank(_ source: MetricSource?, for metric: HealthMetric) -> Int`; `HealthMetric.claimedByWearable: Bool`, `HealthMetric.acceptsManualEntry: Bool`, `HealthMetric.healthIsAuthoritative: Bool`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/MetricSourceTests.swift`:

```swift
import Testing
@testable import Integrations

/// The rank table is the whole merge rule. It is pinned here because every
/// failure it can have is silent: a number that flips between syncs looks to
/// the user like their body changed, not like two sources disagreeing.
@Suite struct MetricSourceTests {

    private let whoopFirst = SourceRanking(primaryWearable: .whoop)
    private let fitbitFirst = SourceRanking(primaryWearable: .fitbit)

    /// A typed number outranks every sync, on every metric.
    @Test func manualOutranksEverything() {
        for metric in HealthMetric.allCases {
            let manual = whoopFirst.rank(.manual, for: metric)
            #expect(manual > whoopFirst.rank(.whoop, for: metric))
            #expect(manual > whoopFirst.rank(.fitbit, for: metric))
            #expect(manual > whoopFirst.rank(.appleHealth, for: metric))
        }
    }

    /// A metric a strap measures: the chosen strap outranks the other, and both
    /// outrank the phone.
    @Test func theChosenStrapOwnsAMetricItMeasures() {
        #expect(whoopFirst.rank(.whoop, for: .hrvMs) > whoopFirst.rank(.fitbit, for: .hrvMs))
        #expect(whoopFirst.rank(.fitbit, for: .hrvMs) > whoopFirst.rank(.appleHealth, for: .hrvMs))

        #expect(fitbitFirst.rank(.fitbit, for: .hrvMs) > fitbitFirst.rank(.whoop, for: .hrvMs))
        #expect(fitbitFirst.rank(.whoop, for: .hrvMs) > fitbitFirst.rank(.appleHealth, for: .hrvMs))
    }

    /// A metric no strap measures: the phone counts it, so the phone is the
    /// authority and a strap only fills a gap.
    @Test func thePhoneOwnsWhatOnlyThePhoneCounts() {
        for metric in [HealthMetric.steps, .activeEnergyKcal, .exerciseMinutes, .distanceKm] {
            #expect(whoopFirst.rank(.appleHealth, for: metric) > whoopFirst.rank(.whoop, for: metric))
        }
    }

    /// Weight and water are typed, so the phone is not the authority for them
    /// either, and a strap's reading beats a passive one.
    @Test func typedMetricsDoNotMakeThePhoneTheAuthority() {
        for metric in [HealthMetric.weightKg, .waterML] {
            #expect(!metric.healthIsAuthoritative)
            #expect(whoopFirst.rank(.whoop, for: metric) > whoopFirst.rank(.appleHealth, for: metric))
        }
    }

    /// A row written before provenance existed ranks below every identified
    /// source, so the first sync after upgrade attributes it correctly.
    @Test func anUnattributedValueRanksLowest() {
        for metric in HealthMetric.allCases {
            #expect(whoopFirst.rank(nil, for: metric) == 0)
            #expect(whoopFirst.rank(.appleHealth, for: metric) > 0)
        }
    }

    /// The five Whoop measures from a strap worn all night must stay claimed,
    /// or a phone estimate silently replaces a measurement.
    @Test func theStrapMeasuredMetricsStayClaimed() {
        for metric in [HealthMetric.restingHR, .hrvMs, .spo2Percentage,
                       .respiratoryRate, .sleepMinutes] {
            #expect(metric.claimedByWearable, "\(metric.rawValue) lost its guard")
        }
    }

    /// Exactly the two a person can type in this app.
    @Test func onlyWeightAndWaterAreTyped() {
        let typed = HealthMetric.allCases.filter(\.acceptsManualEntry)
        #expect(Set(typed) == Set([.weightKg, .waterML]))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter MetricSourceTests`
Expected: FAIL to compile, "cannot find 'SourceRanking' in scope".

- [ ] **Step 3: Add the vocabulary to HealthMetric**

In `LifeOSKit/Sources/Integrations/HealthMetric.swift`, delete the `Precedence` enum and the `precedence` property entirely, and add in their place:

```swift
    /// Measured by a strap worn on the body, so a wearable outranks the phone.
    ///
    /// The phone infers these from a wrist it is not on, or does not measure
    /// them at all. Everything else on the list is counted passively by the
    /// phone itself, where the phone is the better authority.
    ///
    /// Sleep stages are deliberately absent for now: nothing writes them but
    /// Apple Health today, and they join this list in slice 3 when Fitbit
    /// starts reporting them.
    public var claimedByWearable: Bool {
        switch self {
        case .restingHR, .hrvMs, .spo2Percentage, .respiratoryRate, .sleepMinutes:
            true
        default:
            false
        }
    }

    /// A person can type this into the app, so a background sync must not
    /// replace what they entered on purpose.
    public var acceptsManualEntry: Bool {
        switch self {
        case .weightKg, .waterML: true
        default: false
        }
    }

    /// Health is the top authority among syncing sources: nothing else measures
    /// this and nobody types it, so the latest reading is simply the truth.
    /// This is what lets an afternoon sync correct the morning's step count.
    public var healthIsAuthoritative: Bool {
        !claimedByWearable && !acceptsManualEntry
    }
```

- [ ] **Step 4: Write MetricSource and SourceRanking**

Create `LifeOSKit/Sources/Integrations/MetricSource.swift`:

```swift
import Foundation

/// Who put a number in the day's row.
///
/// Recorded per metric per day, because with two straps the value alone is no
/// longer enough to decide who wins. `fillGapsOnly` could not tell a Whoop
/// value from a typed one, which is exactly the distinction a second wearable
/// forces.
public enum MetricSource: String, Sendable, CaseIterable, Equatable {
    case manual
    case whoop
    case fitbit
    case appleHealth
}

/// Turns a source into a rank for a given metric.
///
/// A rank rather than a boolean, so that "the strap the user chose" can outrank
/// "the other strap" without either of them being hard-coded.
public struct SourceRanking: Sendable, Equatable {

    /// Whichever strap the user named as primary. Defaults to Whoop, which is
    /// the only one that exists before Fitbit ships, so an unset preference
    /// reproduces today's behaviour exactly.
    public let primaryWearable: MetricSource

    public init(primaryWearable: MetricSource = .whoop) {
        // A non-wearable primary is meaningless and would silently demote both
        // straps below the phone.
        self.primaryWearable = (primaryWearable == .fitbit) ? .fitbit : .whoop
    }

    /// 4 typed, 3 the authority, 2 a secondary reading, 1 a fallback, 0 unknown.
    public func rank(_ source: MetricSource?, for metric: HealthMetric) -> Int {
        guard let source else { return 0 }
        switch source {
        case .manual:
            return 4
        case .appleHealth:
            return metric.healthIsAuthoritative ? 3 : 1
        case .whoop, .fitbit:
            guard metric.claimedByWearable else { return 2 }
            return source == primaryWearable ? 3 : 2
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter MetricSourceTests`
Expected: PASS, 7 tests.

The build will still fail in `HealthFill.swift` and `HealthFillTests.swift`, which reference the deleted `precedence`. That is expected and Task 2 removes them. If the test runner refuses to run at all because of those files, delete `LifeOSKit/Sources/Integrations/HealthFill.swift` and `LifeOSKit/Tests/IntegrationsTests/HealthFillTests.swift` now and carry their coverage into Task 2, where it is rewritten in full.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/MetricSource.swift \
        LifeOSKit/Sources/Integrations/HealthMetric.swift \
        LifeOSKit/Tests/IntegrationsTests/MetricSourceTests.swift
git commit -m "feat(health): rank the sources that write a metric

A second strap breaks a boolean precedence rule, because it cannot tell
a Whoop value from a typed one. Replace it with a rank per source per
metric, where the strap the user chose outranks the other and both
outrank the phone for what a strap actually measures.

The rank table reproduces today's outcomes exactly. Weight and water
keep the phone off the top rank so a typed number stays protected."
```

---

## Task 2: MetricArbiter

**Files:**
- Create: `LifeOSKit/Sources/Integrations/MetricArbiter.swift`
- Delete: `LifeOSKit/Sources/Integrations/HealthFill.swift`
- Delete: `LifeOSKit/Tests/IntegrationsTests/HealthFillTests.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/MetricArbiterTests.swift`

**Interfaces:**
- Consumes: `MetricSource`, `SourceRanking`, `HealthMetric` from Task 1.
- Produces: `MetricArbiter.resolve(metric:existing:existingSource:incoming:incomingSource:ranking:) -> (value: Double?, source: MetricSource?)` and `MetricSource.legacy(for: HealthMetric) -> MetricSource?`.

`HealthFillTests.swift` contains three suites: `HealthFillTests`, `HealthMetricVocabularyTests` and `CycleConsentTests`. Only the first is about the merge rule. Before deleting the file, move `HealthMetricVocabularyTests` and `CycleConsentTests` verbatim into a new `LifeOSKit/Tests/IntegrationsTests/HealthMetricTests.swift`, minus the two tests that reference `precedence` (`whoopAndHandTypedFieldsStayFillGapsOnly` and `newMetricsLetHealthBeTheSource`), which Task 1 replaced.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/MetricArbiterTests.swift`:

```swift
import Testing
@testable import Integrations

/// Who wins when two sources have a number for the same day.
@Suite struct MetricArbiterTests {

    private let whoopFirst = SourceRanking(primaryWearable: .whoop)
    private let fitbitFirst = SourceRanking(primaryWearable: .fitbit)

    private func resolve(
        _ metric: HealthMetric,
        existing: Double?, from existingSource: MetricSource?,
        incoming: Double?, from incomingSource: MetricSource,
        ranking: SourceRanking? = nil
    ) -> (value: Double?, source: MetricSource?) {
        MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: existingSource,
            incoming: incoming, incomingSource: incomingSource,
            ranking: ranking ?? whoopFirst
        )
    }

    // MARK: - The rule that destroys data if it is wrong

    /// A source having no reading is not evidence of zero. Blanking a real
    /// value because a query came back empty is the one failure here that
    /// destroys data rather than merely showing the wrong number.
    @Test func aMissingReadingNeverClearsAnExistingValue() {
        for metric in HealthMetric.allCases {
            let kept = resolve(metric, existing: 42, from: .whoop, incoming: nil, from: .appleHealth)
            #expect(kept.value == 42)
            #expect(kept.source == .whoop)

            let empty = resolve(metric, existing: nil, from: nil, incoming: nil, from: .appleHealth)
            #expect(empty.value == nil)
            #expect(empty.source == nil)
        }
    }

    // MARK: - Preserved from HealthFill

    @Test func healthDoesNotOverwriteAWhoopValue() {
        #expect(resolve(.restingHR, existing: 52, from: .whoop, incoming: 55, from: .appleHealth).value == 52)
        #expect(resolve(.hrvMs, existing: 88, from: .whoop, incoming: 91, from: .appleHealth).value == 88)
        #expect(resolve(.sleepMinutes, existing: 431, from: .whoop, incoming: 402, from: .appleHealth).value == 431)
    }

    @Test func healthFillsAWhoopGap() {
        let filled = resolve(.restingHR, existing: nil, from: nil, incoming: 55, from: .appleHealth)
        #expect(filled.value == 55)
        #expect(filled.source == .appleHealth)
    }

    /// Equal rank overwrites. This is what lets the afternoon sync correct the
    /// morning's count, and it is the entire job the old `healthIsTheSource`
    /// case did.
    @Test func healthOverwritesItsOwnPassivelyMeasuredCounts() {
        #expect(resolve(.steps, existing: 4000, from: .appleHealth, incoming: 9770, from: .appleHealth).value == 9770)
        #expect(resolve(.activeEnergyKcal, existing: 210, from: .appleHealth, incoming: 480, from: .appleHealth).value == 480)
        #expect(resolve(.exerciseMinutes, existing: 12, from: .appleHealth, incoming: 31, from: .appleHealth).value == 31)
    }

    @Test func aHandEnteredValueSurvivesTheSync() {
        #expect(resolve(.waterML, existing: 500, from: .manual, incoming: 250, from: .appleHealth).value == 500)
        #expect(resolve(.weightKg, existing: 74.2, from: .manual, incoming: 75.0, from: .appleHealth).value == 74.2)
        #expect(resolve(.weightKg, existing: 74.2, from: .manual, incoming: 75.0, from: .whoop).value == 74.2)
    }

    // MARK: - The change made on purpose

    /// Today a Health-written weight is frozen by `fillGapsOnly` and can never
    /// be corrected by a later Health reading. Equal rank fixes that, while a
    /// typed weight stays protected above.
    @Test func healthCorrectsAWeightItWroteItself() {
        let corrected = resolve(.weightKg, existing: 74.2, from: .appleHealth, incoming: 75.0, from: .appleHealth)
        #expect(corrected.value == 75.0)
        #expect(corrected.source == .appleHealth)
    }

    // MARK: - Two straps

    @Test func theChosenStrapOverwritesTheOther() {
        #expect(resolve(.sleepMinutes, existing: 431, from: .whoop,
                        incoming: 402, from: .fitbit, ranking: fitbitFirst).value == 402)
        #expect(resolve(.sleepMinutes, existing: 402, from: .fitbit,
                        incoming: 431, from: .whoop, ranking: fitbitFirst).value == 402)
    }

    @Test func theSecondaryStrapStillFillsAGap() {
        let filled = resolve(.hrvMs, existing: nil, from: nil, incoming: 62, from: .fitbit)
        #expect(filled.value == 62)
        #expect(filled.source == .fitbit)
    }

    // MARK: - The migration trap

    /// A row written before provenance existed is overwritten by any
    /// identified source, which re-attributes it correctly on the first sync.
    @Test func anUnattributedValueYieldsToAnIdentifiedOne() {
        let taken = resolve(.steps, existing: 4000, from: nil, incoming: 9770, from: .appleHealth)
        #expect(taken.value == 9770)
        #expect(taken.source == .appleHealth)
    }

    /// But a weight or water figure the user typed before this shipped is also
    /// unattributed, and must not be silently replaced. This is the one case
    /// where skipping the special handling destroys real user data.
    @Test func anUnattributedTypedValueIsTreatedAsTyped() {
        #expect(resolve(.weightKg, existing: 74.2, from: nil, incoming: 75.0, from: .appleHealth).value == 74.2)
        #expect(resolve(.waterML, existing: 500, from: nil, incoming: 250, from: .appleHealth).value == 500)
        #expect(MetricSource.legacy(for: .weightKg) == .manual)
        #expect(MetricSource.legacy(for: .waterML) == .manual)
        #expect(MetricSource.legacy(for: .steps) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter MetricArbiterTests`
Expected: FAIL to compile, "cannot find 'MetricArbiter' in scope".

- [ ] **Step 3: Write the arbiter**

Create `LifeOSKit/Sources/Integrations/MetricArbiter.swift`:

```swift
import Foundation

/// The merge rule, as a pure function.
///
/// Kept apart from HealthKit, Fitbit and SwiftData so every branch can be
/// exercised without a device, an authorisation prompt, a network or a store.
/// Each sync that uses it is a loop around this one call.
public enum MetricArbiter {

    /// What the day's row should hold after a reading arrives, and who it
    /// should then be attributed to.
    ///
    /// Returns `existing` unchanged when there is nothing to write, so a caller
    /// can assign the result unconditionally.
    public static func resolve(
        metric: HealthMetric,
        existing: Double?,
        existingSource: MetricSource?,
        incoming: Double?,
        incomingSource: MetricSource,
        ranking: SourceRanking
    ) -> (value: Double?, source: MetricSource?) {
        // A source having no reading is not evidence of zero.
        guard let incoming else { return (existing, existingSource) }
        guard existing != nil else { return (incoming, incomingSource) }

        let held = existingSource ?? MetricSource.legacy(for: metric)

        // Greater than or equal, not greater than. Equal rank means the same
        // source syncing again, which must be allowed to correct itself.
        guard ranking.rank(incomingSource, for: metric) >= ranking.rank(held, for: metric) else {
            return (existing, held)
        }
        return (incoming, incomingSource)
    }
}

extension MetricSource {

    /// How to read a value written before provenance was recorded.
    ///
    /// Rank 0 for almost everything, so the first sync after upgrade
    /// re-attributes it. The numbers do not change: the same sources produce
    /// them, now named.
    ///
    /// Weight and water are the exception, and the exception matters. A figure
    /// the user typed before this shipped is unattributed too, and treating it
    /// as unknown would let the next Health sync silently replace it. That is
    /// the one path here that destroys data a person entered by hand, so an
    /// unattributed value for a typed metric is read as typed.
    public static func legacy(for metric: HealthMetric) -> MetricSource? {
        metric.acceptsManualEntry ? .manual : nil
    }
}
```

- [ ] **Step 4: Move the surviving vocabulary tests, then delete HealthFill**

Create `LifeOSKit/Tests/IntegrationsTests/HealthMetricTests.swift` holding the `HealthMetricVocabularyTests` and `CycleConsentTests` suites copied verbatim from `HealthFillTests.swift`, omitting the two tests named in the task preamble. Then:

```bash
git rm LifeOSKit/Sources/Integrations/HealthFill.swift \
       LifeOSKit/Tests/IntegrationsTests/HealthFillTests.swift
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter MetricArbiterTests`
Expected: PASS, 10 tests.

Run: `cd LifeOSKit && swift test --filter HealthMetricTests`
Expected: PASS.

`HealthApplyTests` will still fail to build until Task 4. That is expected.

- [ ] **Step 6: Commit**

```bash
git add -A LifeOSKit/Sources/Integrations LifeOSKit/Tests/IntegrationsTests
git commit -m "feat(health): decide a merge by rank instead of by a boolean

MetricArbiter replaces HealthFill. Equal rank overwrites, which is what
lets a source correct its own earlier reading, and is the job the old
healthIsTheSource case did.

An unattributed value ranks lowest so the first sync after upgrade
re-attributes it, except for weight and water, where an unattributed
value is read as typed. Without that exception a figure the user
entered by hand before this shipped would be silently replaced."
```

---

## Task 3: provenance on the day's row

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/DailyMetrics.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/DailyMetricsSourcesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks. `Persistence` must not import `Integrations`, so sources are raw `String` here.
- Produces: `DailyMetrics.sourcesData: Data?`, `DailyMetrics.sources: [String: String]`, `func source(_ key: String) -> String?`, `func setSource(_ key: String, _ value: String?)`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/DailyMetricsSourcesTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

/// Provenance rides alongside the values, keyed the same way the extras bag is.
@Suite @MainActor struct DailyMetricsSourcesTests {

    private func row() throws -> DailyMetrics {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let row = DailyMetrics(date: Calendar.current.startOfDay(for: .now))
        context.insert(row)
        return row
    }

    @Test func aRowStartsWithNoProvenance() throws {
        let row = try row()
        #expect(row.sourcesData == nil)
        #expect(row.sources.isEmpty)
        #expect(row.source("steps") == nil)
    }

    @Test func aSourceRoundTripsThroughTheBag() throws {
        let row = try row()
        row.setSource("steps", "appleHealth")
        row.setSource("hrvMs", "whoop")

        #expect(row.source("steps") == "appleHealth")
        #expect(row.source("hrvMs") == "whoop")
        #expect(row.sources.count == 2)
    }

    /// Clearing removes the key rather than storing an empty string, so an
    /// absent attribution stays absent rather than becoming a source named "".
    @Test func clearingASourceRemovesTheKey() throws {
        let row = try row()
        row.setSource("steps", "appleHealth")
        row.setSource("steps", nil)

        #expect(row.source("steps") == nil)
        #expect(row.sources.isEmpty)
        #expect(row.sourcesData == nil)
    }

    /// Unreadable bytes must not take the row down with them. A day whose
    /// provenance cannot be decoded still has its numbers, and losing the
    /// screen over the attribution would be the worse failure.
    @Test func unreadableProvenanceReadsAsEmptyRatherThanThrowing() throws {
        let row = try row()
        row.sourcesData = Data([0x00, 0x01, 0x02])
        #expect(row.sources.isEmpty)
        #expect(row.source("steps") == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter DailyMetricsSourcesTests`
Expected: FAIL to compile, "value of type 'DailyMetrics' has no member 'sourcesData'".

- [ ] **Step 3: Add the bag**

In `LifeOSKit/Sources/Persistence/DailyMetrics.swift`, add immediately after the `extrasData` property:

```swift
    /// Who wrote each value, as a JSON dictionary keyed by `HealthMetric.rawValue`.
    ///
    /// Parallel to `extrasData` rather than folded into it, because that bag is
    /// `[String: Double]` and a source is a name. Optional, so a store written
    /// before this existed migrates without a schema change and simply reports
    /// no provenance, which the arbiter reads as "unattributed".
    ///
    /// A raw `String` rather than a typed source: `Persistence` sits below
    /// `Integrations` and must not import it. The vocabulary lives up there.
    public var sourcesData: Data?
```

and after `setExtra`:

```swift
    /// The provenance bag, decoded. Empty rather than throwing when the bytes
    /// cannot be read, for the same reason `extras` is: a day whose
    /// attribution is unreadable still has its numbers.
    public var sources: [String: String] {
        get {
            guard let sourcesData, !sourcesData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: String].self, from: sourcesData)
            else { return [:] }
            return decoded
        }
        set {
            sourcesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    public func source(_ key: String) -> String? { sources[key] }

    /// Writing nil removes the key, so an absent attribution stays absent
    /// rather than becoming a source with an empty name.
    public func setSource(_ key: String, _ value: String?) {
        var bag = sources
        if let value { bag[key] = value } else { bag.removeValue(forKey: key) }
        sources = bag
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter DailyMetricsSourcesTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the whole Persistence suite for migration safety**

Run: `cd LifeOSKit && swift test --filter PersistenceTests`
Expected: PASS. An additive optional property is a lightweight SwiftData migration; if any existing test fails here, the property is not additive and the cause must be found before continuing.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/DailyMetrics.swift \
        LifeOSKit/Tests/PersistenceTests/DailyMetricsSourcesTests.swift
git commit -m "feat(persistence): record who wrote each metric on a day

The row held what a value is and never who put it there, which is the
distinction a second wearable forces. A parallel bag keyed the same way
extras is, holding a source name per metric.

Additive and optional so an existing store migrates and simply reports
no provenance, which the arbiter reads as unattributed."
```

---

## Task 4: Apple Health writes through the arbiter

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/HealthApply.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/HealthApplyTests.swift`

**Interfaces:**
- Consumes: `MetricArbiter.resolve`, `MetricSource`, `SourceRanking` (Tasks 1 and 2), `DailyMetrics.source`/`setSource` (Task 3).
- Produces: `HealthApply.write(_ day: HealthDay, into store: MetricsStore, ranking: SourceRanking = SourceRanking()) throws`.

- [ ] **Step 1: Write the failing test**

Append to `LifeOSKit/Tests/IntegrationsTests/HealthApplyTests.swift`, inside the existing `HealthApplyTests` suite:

```swift
    /// The write records who wrote it, or the next sync cannot arbitrate.
    @Test func aHealthWriteRecordsItsProvenance() throws {
        let store = try store()
        try HealthApply.write(HealthDay(date: day, values: [.steps: 9770, .restingHR: 55]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.source(HealthMetric.steps.rawValue) == MetricSource.appleHealth.rawValue)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.appleHealth.rawValue)
    }

    /// A value Whoop wrote and attributed is not replaced by the phone.
    @Test func anAttributedWhoopValueSurvivesAHealthSync() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.restingHR = 52
            row.setSource(HealthMetric.restingHR.rawValue, MetricSource.whoop.rawValue)
        }

        try HealthApply.write(HealthDay(date: day, values: [.restingHR: 55]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.whoop.rawValue)
    }

    /// The migration trap, at the level where it would actually bite: a weight
    /// typed before provenance existed carries no attribution, and a sync must
    /// still leave it alone.
    @Test func anUnattributedWeightIsNotReplacedByASync() throws {
        let store = try store()
        try store.upsert(date: day) { row in row.weightKg = 74.2 }

        try HealthApply.write(HealthDay(date: day, values: [.weightKg: 75.0]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 74.2)
    }

    /// Metrics in the extras bag get provenance too, not just the named columns.
    @Test func theLongTailIsAttributedAsWell() throws {
        let store = try store()
        try HealthApply.write(HealthDay(date: day, values: [.vo2Max: 48.2]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.extra(HealthMetric.vo2Max.rawValue) == 48.2)
        #expect(row.source(HealthMetric.vo2Max.rawValue) == MetricSource.appleHealth.rawValue)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter HealthApplyTests`
Expected: FAIL to compile, because `HealthApply` still calls the deleted `HealthFill`.

- [ ] **Step 3: Rewrite HealthApply**

Replace the body of `LifeOSKit/Sources/Integrations/HealthApply.swift`. The doc comment at the top of the type stays; the `write` function and the helpers become:

```swift
    /// Merges one day, honouring the ranks.
    ///
    /// Uses `MetricsStore.upsert`, which is a merge rather than a replace, so
    /// the columns Health has nothing to say about are left exactly as Whoop
    /// or the user left them.
    @MainActor
    public static func write(
        _ day: HealthDay,
        into store: MetricsStore,
        ranking: SourceRanking = SourceRanking()
    ) throws {
        try store.upsert(date: day.date) { row in
            for (metric, incoming) in day.values {
                let resolved = resolve(
                    metric, incoming: incoming, existing: existing(metric, in: row),
                    ranking: ranking, row: row
                )
                write(resolved, for: metric, into: row)
            }
        }
    }

    /// The named columns, read as a Double so one merge path serves them all.
    @MainActor
    private static func existing(_ metric: HealthMetric, in row: DailyMetrics) -> Double? {
        switch metric {
        case .steps:             row.steps.map(Double.init)
        case .exerciseMinutes:   row.exerciseMinutes.map(Double.init)
        case .sleepMinutes:      row.sleepMinutes.map(Double.init)
        case .activeEnergyKcal:  row.activeEnergyKcal
        case .weightKg:          row.weightKg
        case .waterML:           row.waterML
        case .restingHR:         row.restingHR
        case .hrvMs:             row.hrvMs
        case .spo2Percentage:    row.spo2Percentage
        case .respiratoryRate:   row.respiratoryRate
        default:                 row.extra(metric.rawValue)
        }
    }

    /// Decides, and records the attribution as a side effect so the next sync
    /// can arbitrate against it.
    @MainActor
    private static func resolve(
        _ metric: HealthMetric,
        incoming: Double?,
        existing: Double?,
        ranking: SourceRanking,
        row: DailyMetrics
    ) -> Double? {
        let held = row.source(metric.rawValue).flatMap(MetricSource.init(rawValue:))
        let outcome = MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: held,
            incoming: incoming, incomingSource: .appleHealth,
            ranking: ranking
        )
        row.setSource(metric.rawValue, outcome.source?.rawValue)
        return outcome.value
    }

    /// The one place the `HealthMetric` vocabulary meets `DailyMetrics` columns.
    @MainActor
    private static func write(_ value: Double?, for metric: HealthMetric, into row: DailyMetrics) {
        switch metric {
        case .steps:             row.steps = whole(value)
        case .exerciseMinutes:   row.exerciseMinutes = whole(value)
        case .sleepMinutes:      row.sleepMinutes = whole(value)
        case .activeEnergyKcal:  row.activeEnergyKcal = value
        case .weightKg:          row.weightKg = value
        case .waterML:           row.waterML = value
        case .restingHR:         row.restingHR = value
        case .hrvMs:             row.hrvMs = value
        case .spo2Percentage:    row.spo2Percentage = value
        case .respiratoryRate:   row.respiratoryRate = value
        default:
            // The long tail. Same merge rule, stored in the bag rather than in
            // a column of its own. See `DailyMetrics.extrasData`.
            row.setExtra(metric.rawValue, value)
        }
    }

    private static func whole(_ value: Double?) -> Int? {
        value.map { Int($0.rounded()) }
    }
```

Note the switch is now written twice, once to read and once to write. That is deliberate: the alternative is a closure pair per metric, which is harder to read and hides the column mapping this file exists to make obvious.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter HealthApplyTests`
Expected: PASS, including every pre-existing test in the suite. The pre-existing `whoopValuesSurviveAHealthSync` test writes Whoop values with no attribution, so it exercises the unattributed path; it must still pass, because resting HR is claimed by a wearable and Health ranks 1 against an unattributed 0.

If `whoopValuesSurviveAHealthSync` fails, that is a real finding, not a test to adjust: an unattributed Whoop value ranks 0 and Health ranks 1, so Health now wins. Fix it by attributing the setup writes in that test to `.whoop`, which is what Task 5 makes true in production. Do not weaken the rank table.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/HealthApply.swift \
        LifeOSKit/Tests/IntegrationsTests/HealthApplyTests.swift
git commit -m "feat(health): merge the Apple Health sync through the arbiter

Every write now records who made it, including the long tail in the
extras bag, so the next sync has something to arbitrate against.

Reading and writing the columns are two switches rather than a closure
pair per metric, which keeps the column mapping this file exists to
make obvious actually obvious."
```

---

## Task 5: Whoop writes through the arbiter

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift:70-110`
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopArbitrationTests.swift`

**Interfaces:**
- Consumes: `MetricArbiter`, `MetricSource`, `SourceRanking`, `DailyMetrics.setSource`.
- Produces: `WhoopDerivation.init(..., ranking: SourceRanking = SourceRanking())`. Whoop-only columns (`whoopRecoveryPct`, `whoopDayStrain`, `whoopSleepPerformancePct`, `whoopCalories`, `whoopAverageHR`, `whoopMaxHR`, `whoopSleepConsistencyPct`, `whoopSleepEfficiencyPct`, `whoopSleepDebtMinutes`, `whoopRecoveryIsCalibrating`, `skinTempCelsius`) keep assigning directly: nothing else writes them, so there is nothing to arbitrate.

The contested columns are exactly the seven that have a `HealthMetric` and another writer: `restingHR`, `hrvMs`, `spo2Percentage`, `respiratoryRate`, `sleepMinutes`, `exerciseMinutes`, `weightKg`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/WhoopArbitrationTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// Whoop used to assign its columns unconditionally, which made it the winner
/// by write order rather than by rule. Now it goes through the same arbiter as
/// everything else.
@Suite @MainActor struct WhoopArbitrationTests {

    private func store() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private let day = Calendar.current.startOfDay(for: .now)

    /// The headline rule, now expressed as a rank rather than as write order.
    @Test func whoopOwnsTheMetricsItMeasures() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.restingHR = 55
            row.setSource(HealthMetric.restingHR.rawValue, MetricSource.appleHealth.rawValue)
        }

        try WhoopDerivation(store: store).derive(
            recoveries: [.init(date: day, restingHeartRate: 52)],
            sleeps: [], cycles: [], workouts: [], body: nil
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.whoop.rawValue)
    }

    /// The phone counts exercise minutes better than a strap infers them, so
    /// Whoop fills a gap there rather than overwriting. This preserves the
    /// outcome the old write order produced, where the Health sync ran second.
    @Test func whoopDoesNotOverwriteThePhonesExerciseMinutes() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.exerciseMinutes = 31
            row.setSource(HealthMetric.exerciseMinutes.rawValue, MetricSource.appleHealth.rawValue)
        }

        try WhoopDerivation(store: store).derive(
            recoveries: [], sleeps: [], cycles: [],
            workouts: [.init(date: day, durationMinutes: 64)], body: nil
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.exerciseMinutes == 31)
    }

    /// A typed weight is not replaced by the figure someone once entered in the
    /// Whoop app.
    @Test func whoopDoesNotOverwriteATypedWeight() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.weightKg = 74.2
            row.setSource(HealthMetric.weightKg.rawValue, MetricSource.manual.rawValue)
        }

        try WhoopDerivation(store: store).derive(
            recoveries: [], sleeps: [], cycles: [], workouts: [],
            body: (sample: .init(weightKg: 80.0), date: day)
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 74.2)
    }

    /// Whoop's own scored columns have no second writer, so they are assigned
    /// directly and must not acquire provenance they do not need.
    @Test func whoopOnlyColumnsAreWrittenDirectly() throws {
        let store = try store()
        try WhoopDerivation(store: store).derive(
            recoveries: [.init(date: day, recoveryPercentage: 66)],
            sleeps: [], cycles: [], workouts: [], body: nil
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.whoopRecoveryPct == 66)
    }
}
```

The initialisers used above (`WhoopDerivation(store:)`, and the sample types' memberwise inits) must match the real signatures in `WhoopDerivation.swift` and `WhoopSamples.swift`. Read both files first and adjust the test's construction calls to the actual signatures, keeping the assertions exactly as written. Only the assertions are the specification here.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter WhoopArbitrationTests`
Expected: FAIL. `whoopDoesNotOverwriteThePhonesExerciseMinutes` and `whoopDoesNotOverwriteATypedWeight` fail on the assignment, because Whoop currently overwrites unconditionally.

- [ ] **Step 3: Route the contested columns through the arbiter**

In `LifeOSKit/Sources/Integrations/WhoopDerivation.swift`, add a stored `ranking` property with a defaulted initialiser parameter, and a private helper:

```swift
    private let ranking: SourceRanking

    /// Merges one Whoop reading into a column another source also writes.
    ///
    /// Whoop used to assign these directly, which made it the winner by write
    /// order: it ran first and the Health sync ran second and overwrote what it
    /// was allowed to. That worked only while there were exactly two writers.
    @MainActor
    private func merged(
        _ metric: HealthMetric,
        incoming: Double?,
        existing: Double?,
        row: DailyMetrics
    ) -> Double? {
        let held = row.source(metric.rawValue).flatMap(MetricSource.init(rawValue:))
        let outcome = MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: held,
            incoming: incoming, incomingSource: .whoop,
            ranking: ranking
        )
        row.setSource(metric.rawValue, outcome.source?.rawValue)
        return outcome.value
    }
```

Then inside the `upsertBatch` closure, replace the seven contested assignments. For example, `if let value = recovery?.restingHeartRate { row.restingHR = value }` becomes:

```swift
            row.restingHR = merged(.restingHR, incoming: recovery?.restingHeartRate,
                                   existing: row.restingHR, row: row)
```

Apply the same shape to `hrvMs`, `spo2Percentage`, `respiratoryRate`, and `sleepMinutes` (which is an `Int?` column, so wrap: `row.sleepMinutes = merged(.sleepMinutes, incoming: sleep?.asleepMinutes.map(Double.init), existing: row.sleepMinutes.map(Double.init), row: row).map { Int($0.rounded()) }`). Do the same for the `exerciseMinutes` sum and the `weightKg` write.

Leave every `whoop`-prefixed column and `skinTempCelsius` exactly as they are.

Note the `if let` guards disappear: `merged` returns `existing` unchanged when `incoming` is nil, so the assignment is safe unconditionally. That is the point of the arbiter returning a value rather than an optional decision.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter WhoopArbitrationTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run every suite that touches the spine**

Run: `cd LifeOSKit && swift test`
Expected: PASS. `WhoopTests`, `WhoopArchiveTests`, `MetricsStoreTests` and `HealthApplyTests` all read this write path. Any failure here is a real behaviour change and must be understood, not patched by loosening an assertion.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopDerivation.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopArbitrationTests.swift
git commit -m "feat(whoop): merge the contested columns through the arbiter

Whoop assigned its columns unconditionally, which made it the winner by
write order rather than by rule: it ran first and the Health sync ran
second and overwrote what it was permitted to. That holds only while
there are exactly two writers.

The seven columns another source also writes now go through the arbiter
and record their provenance. Whoop's own scored columns keep assigning
directly, because nothing else writes them."
```

---

# Slice 2: the connection

## Task 6: the fitbit_connections table

**Files:**
- Create: `supabase/migrations/20260829090000_fitbit_connections.sql`

**Interfaces:**
- Produces: table `public.fitbit_connections` with columns `user_id uuid primary key`, `fitbit_user_id text`, `access_token text`, `refresh_token text`, `access_expires_at timestamptz`, `scopes text`, `needs_reauth boolean`, `created_at`, `updated_at`. Read only by the service role from inside an Edge Function.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260829090000_fitbit_connections.sql`:

```sql
-- One connected Fitbit account per user.
--
-- The tokens live here rather than in the device Keychain, which is where the
-- Whoop tokens live, and the reason is specific to Fitbit: its refresh tokens
-- rotate and are single use. A new refresh token is returned with every access
-- token, and the old one stops working. Two devices sharing one credential
-- would therefore invalidate each other on every sync, and the user would be
-- signed out by their own second phone.
--
-- A single server-side row with a lock around it is the only arrangement where
-- exactly one writer rotates the token.
create table public.fitbit_connections (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,

  -- Fitbit's own id for the account, so a reconnect to a different Fitbit
  -- account is distinguishable from a refresh of the same one.
  fitbit_user_id text,

  -- SECURITY: stored in plaintext, matching plaid_items. Anyone holding the
  -- service-role key can read every user's health credential. Accepted for a
  -- first release on the same terms, and to be revisited with Supabase Vault
  -- before this carries a second person's data.
  access_token text not null,

  -- The rotating half. Single use: every refresh replaces it.
  refresh_token text not null,

  -- Fitbit access tokens last 8 hours. Stored so the function refreshes on
  -- expiry rather than discovering it through a 401.
  access_expires_at timestamptz not null,

  -- Space-separated, as Fitbit returns them. Kept so the app can tell a
  -- missing collection caused by a declined scope from one caused by a device
  -- that has no such sensor.
  scopes text not null default '',

  -- Set when a refresh is refused with invalid_grant. The credential is dead
  -- and only the user signing in again can replace it, so the card must say
  -- Reconnect rather than retrying forever.
  needs_reauth boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner, which is the intent: the access token must never
-- reach a device. The service role bypasses RLS and is the only reader, from
-- inside an Edge Function that has already resolved the caller.
alter table public.fitbit_connections enable row level security;
```

No index is needed: `user_id` is the primary key and the only access pattern.

- [ ] **Step 2: Verify the migration applies**

Run: `supabase db reset` if a local stack is running, or `supabase db push --dry-run` to check the statement parses against the remote. Expected: no error, `fitbit_connections` created.

If no Supabase stack is available in this environment, verify by inspection that every column referenced in Tasks 8 and 15 exists here, and note in the commit body that it was not applied locally.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260829090000_fitbit_connections.sql
git commit -m "feat(fitbit): hold the connection server side

Fitbit refresh tokens rotate and are single use, so a credential shared
between two devices invalidates itself on every sync and signs the user
out from their own second phone. One row per user with a lock around it
is the only arrangement where exactly one writer rotates the token.

RLS with no policies, matching plaid_items: the service role inside an
Edge Function is the only reader, and the token never reaches a device."
```

---

## Task 7: the pure Fitbit helpers

**Files:**
- Create: `supabase/functions/_shared/fitbit.ts`
- Test: `supabase/functions/_shared/fitbit_test.ts`

**Interfaces:**
- Produces: `FITBIT_SCOPES: string[]`, `FITBIT_TOKEN_URL: string`, `tokenForm(body): URLSearchParams`, `classifyFitbitFailure(status: number, body: string): FitbitFailure`, `type FitbitFailure = "needs_reauth" | "rate_limited" | "forbidden_scope" | "upstream_failure"`, `quotaRemaining(headers: Headers): number | null`.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/fitbit_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyFitbitFailure,
  FITBIT_SCOPES,
  quotaRemaining,
  tokenForm,
} from "./fitbit.ts";

// A refused refresh token is the end of the connection. Nothing the server
// holds can be used again, so it must be told apart from every retryable
// failure or the app retries forever against a dead credential.
Deno.test("a refused grant is its own kind", () => {
  assertEquals(
    classifyFitbitFailure(400, JSON.stringify({ errors: [{ errorType: "invalid_grant" }] })),
    "needs_reauth",
  );
  assertEquals(classifyFitbitFailure(401, ""), "needs_reauth");
});

// The quota is 150 requests per hour per user. Exhausting it is not a failure,
// it is an unfinished sync, and it must not read as a broken connection.
Deno.test("a rate limit is its own kind, because the sync resumes", () => {
  assertEquals(classifyFitbitFailure(429, ""), "rate_limited");
});

// A collection refused for a scope the user declined must not take the other
// collections down with it.
Deno.test("a refused scope is its own kind", () => {
  assertEquals(
    classifyFitbitFailure(403, JSON.stringify({ errors: [{ errorType: "insufficient_scope" }] })),
    "forbidden_scope",
  );
});

Deno.test("anything else is an opaque upstream failure", () => {
  assertEquals(classifyFitbitFailure(500, ""), "upstream_failure");
});

// Fitbit is not obliged to send JSON when it is having a bad day.
Deno.test("a non-JSON body does not throw", () => {
  assertEquals(classifyFitbitFailure(400, "<html>nope</html>"), "upstream_failure");
});

Deno.test("the quota headroom is read from the response headers", () => {
  const headers = new Headers({ "Fitbit-Rate-Limit-Remaining": "97" });
  assertEquals(quotaRemaining(headers), 97);
  assertEquals(quotaRemaining(new Headers()), null);
});

// An authorization code exchange and a refresh are the same endpoint with
// different grant types, and getting the grant_type wrong fails opaquely.
Deno.test("an exchange carries the verifier, a refresh carries the token", () => {
  const exchange = tokenForm({ code: "abc", verifier: "v", redirect_uri: "lifeos://x" });
  assertEquals(exchange.get("grant_type"), "authorization_code");
  assertEquals(exchange.get("code"), "abc");
  assertEquals(exchange.get("code_verifier"), "v");

  const refresh = tokenForm({ refresh_token: "r" });
  assertEquals(refresh.get("grant_type"), "refresh_token");
  assertEquals(refresh.get("refresh_token"), "r");
  assertEquals(refresh.get("code"), null);
});

// Every scope the app requests must be one it reads. An unused scope is a line
// on the consent screen asking for something the app will never look at.
Deno.test("the scope list holds no scope the app does not read", () => {
  const unused = ["location", "social", "settings", "electrocardiogram",
                  "irregular_rhythm_notifications", "blood_glucose"];
  for (const scope of unused) {
    assertEquals(FITBIT_SCOPES.includes(scope), false, `${scope} is requested but never read`);
  }
  assertEquals(FITBIT_SCOPES.includes("sleep"), true);
  assertEquals(FITBIT_SCOPES.includes("heartrate"), true);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `deno test supabase/functions/_shared/fitbit_test.ts`
Expected: FAIL, module `./fitbit.ts` not found.

- [ ] **Step 3: Write the helpers**

Create `supabase/functions/_shared/fitbit.ts`:

```ts
// Pure Fitbit helpers, shared by fitbit-token and fitbit-sync.
//
// Everything here is a function of its arguments, so it is tested with
// `deno test` and no network. The functions that do talk to Fitbit are thin
// wrappers around these decisions.

export const FITBIT_TOKEN_URL = "https://api.fitbit.com/oauth2/token";
export const FITBIT_API_BASE = "https://api.fitbit.com";

/// Every scope the app reads, and no scope it does not.
///
/// Deliberately absent: location, social, settings, electrocardiogram,
/// irregular_rhythm_notifications, blood_glucose. None of them feed the daily
/// spine, and each one is a line on the consent screen asking a person for
/// something this app will never look at.
export const FITBIT_SCOPES = [
  "activity",
  "cardio_fitness",
  "heartrate",
  "nutrition",
  "oxygen_saturation",
  "profile",
  "respiratory_rate",
  "sleep",
  "temperature",
  "weight",
];

export type FitbitFailure =
  | "needs_reauth"
  | "rate_limited"
  | "forbidden_scope"
  | "upstream_failure";

/// Why a Fitbit request failed, in the only four kinds the app acts on
/// differently. Collapsing these leaves the app retrying forever against a
/// dead credential, or reporting an exhausted quota as a broken connection.
export function classifyFitbitFailure(status: number, body: string): FitbitFailure {
  if (status === 429) return "rate_limited";
  if (status === 401) return "needs_reauth";

  let errorType = "";
  try {
    const parsed = JSON.parse(body);
    errorType = parsed?.errors?.[0]?.errorType ?? "";
  } catch {
    // Fitbit is not obliged to send JSON when it is having a bad day.
    return "upstream_failure";
  }

  if (errorType === "invalid_grant" || errorType === "expired_token") return "needs_reauth";
  if (status === 403 || errorType === "insufficient_scope") return "forbidden_scope";
  return "upstream_failure";
}

/// How many requests remain in this hour, or null when Fitbit did not say.
/// Null is treated as "unknown, stop being clever and take the conservative
/// path", never as zero and never as unlimited.
export function quotaRemaining(headers: Headers): number | null {
  const raw = headers.get("Fitbit-Rate-Limit-Remaining");
  if (raw === null) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

/// The token endpoint's body. An exchange and a refresh are the same endpoint
/// with different grant types, and getting that wrong fails opaquely.
export function tokenForm(body: {
  code?: string;
  verifier?: string;
  redirect_uri?: string;
  refresh_token?: string;
}): URLSearchParams {
  const form = new URLSearchParams();
  if (body.refresh_token) {
    form.set("grant_type", "refresh_token");
    form.set("refresh_token", body.refresh_token);
    return form;
  }
  form.set("grant_type", "authorization_code");
  if (body.code) form.set("code", body.code);
  if (body.redirect_uri) form.set("redirect_uri", body.redirect_uri);
  if (body.verifier) form.set("code_verifier", body.verifier);
  return form;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `deno test supabase/functions/_shared/fitbit_test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/fitbit.ts supabase/functions/_shared/fitbit_test.ts
git commit -m "feat(fitbit): classify a failure into the kinds the app acts on

Four kinds, because the app does something different with each. A
refused grant ends the connection, an exhausted quota is an unfinished
sync rather than a fault, a declined scope must not take the other
collections down, and everything else is opaque.

The scope list is pinned by a test to hold nothing the app does not
read, since an unused scope is a line on the consent screen asking for
something that will never be looked at."
```

---

## Task 8: the fitbit-token function

**Files:**
- Create: `supabase/functions/fitbit-token/index.ts`

**Interfaces:**
- Consumes: `resolveUser`, `serviceClient`, `json` from `_shared/supabase.ts`; `FITBIT_TOKEN_URL`, `tokenForm`, `classifyFitbitFailure` from `_shared/fitbit.ts`.
- Produces: `POST /functions/v1/fitbit-token` taking `{code, verifier, redirect_uri}` and returning `{connected: true, fitbit_user_id, scopes}`. Never returns a token.
- Environment: `FITBIT_CLIENT_ID`, `FITBIT_CLIENT_SECRET`, set with `supabase secrets set`.

- [ ] **Step 1: Write the function**

Create `supabase/functions/fitbit-token/index.ts`:

```ts
// Fitbit authorization code exchange.
//
// FITBIT_CLIENT_SECRET must never be in the iOS binary: an .ipa is a zip file,
// so a secret compiled into the app is public the moment it ships. Set it with
//
//   supabase secrets set FITBIT_CLIENT_SECRET=...
//
// The client sends { code, verifier, redirect_uri } and receives only a
// confirmation. Unlike the Whoop arrangement, it does not receive the tokens
// either: Fitbit refresh tokens rotate and are single use, so exactly one
// writer may hold them, and that writer is this database row.

import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import { classifyFitbitFailure, FITBIT_TOKEN_URL, tokenForm } from "../_shared/fitbit.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // A security boundary, not a formality: this writes a health credential
  // keyed by user, so the id must come from the caller's own token and never
  // from the request body.
  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  const clientID = Deno.env.get("FITBIT_CLIENT_ID");
  const clientSecret = Deno.env.get("FITBIT_CLIENT_SECRET");
  // Deliberately does not say which one is missing.
  if (!clientID || !clientSecret) return json({ error: "server_not_configured" }, 500);

  let body: { code?: string; verifier?: string; redirect_uri?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!body.code || !body.redirect_uri) return json({ error: "missing_code" }, 400);

  const response = await fetch(FITBIT_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${clientID}:${clientSecret}`)}`,
    },
    body: tokenForm(body),
  });

  const text = await response.text();
  if (!response.ok) {
    // Logged with the body so the cause is visible in function logs, while the
    // client receives only a kind, because Fitbit's errors echo request
    // parameters.
    console.error(`fitbit token exchange failed: ${response.status} ${text.slice(0, 300)}`);
    return json({ error: classifyFitbitFailure(response.status, text) }, 502);
  }

  const tokens = JSON.parse(text) as {
    access_token: string;
    refresh_token: string;
    expires_in: number;
    scope: string;
    user_id: string;
  };

  const expiresAt = new Date(Date.now() + (tokens.expires_in ?? 28_800) * 1000);

  // Upsert, not insert: reconnecting replaces a dead credential in place, and
  // a second row per user is meaningless when the primary key is the user.
  const { error } = await serviceClient()
    .from("fitbit_connections")
    .upsert({
      user_id: userID,
      fitbit_user_id: tokens.user_id,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      access_expires_at: expiresAt.toISOString(),
      scopes: tokens.scope ?? "",
      needs_reauth: false,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (error) {
    console.error(`fitbit connection write failed: ${error.message}`);
    return json({ error: "storage_failure" }, 500);
  }

  // No token in the response. This is the whole point of the arrangement.
  return json({ connected: true, fitbit_user_id: tokens.user_id, scopes: tokens.scope ?? "" }, 200);
});
```

- [ ] **Step 2: Check it type-checks**

Run: `deno check supabase/functions/fitbit-token/index.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/fitbit-token/index.ts
git commit -m "feat(fitbit): exchange the authorization code on the server

The client secret cannot live in the app bundle, and neither can the
tokens: Fitbit rotates the refresh token on every use, so exactly one
writer may hold it. The function returns a confirmation and no
credential at all.

Reconnecting upserts in place, because a second row per user is
meaningless when the user is the primary key."
```

---

## Task 9: FitbitOAuth and the pending attempt

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FitbitOAuth.swift`
- Create: `LifeOSKit/Sources/Integrations/FitbitAuthStore.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FitbitOAuthTests.swift`

**Interfaces:**
- Consumes: `Data.base64URLEncodedString()`, already defined as an internal extension in `WhoopOAuth.swift` and visible across the `Integrations` module.
- Produces: `FitbitOAuth.session(clientID:redirectURI:scopes:verifier:state:) -> FitbitOAuth.Session` with fields `url`, `verifier`, `state`; `FitbitOAuth.code(from:expectedState:) throws -> String`; `FitbitOAuth.state(in:) -> String?`; `FitbitAuthError`; `FitbitPendingAuth(verifier:state:startedAt:)` with `isFresh(now:within:)`; protocol `FitbitAuthStoring` with `pendingAuths()`, `savePending(_:)`, `clearPending()`; `KeychainFitbitAuthStore`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/FitbitOAuthTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

/// The client side of the round trip. The exchange happens on the server, so
/// what is pinned here is the half that can be got wrong silently: the
/// challenge, and the checks on the way back.
@Suite struct FitbitOAuthTests {

    private let redirect = "lifeos://fitbit-callback"

    /// Fitbit permits a custom scheme for a native app, so there is no bridge
    /// hop and the user never leaves the app. Whoop needed one because Whoop
    /// requires https.
    @Test func theAuthorizeURLCarriesEverythingFitbitRequires() throws {
        let session = FitbitOAuth.session(clientID: "ABC123", redirectURI: redirect)
        let items = try #require(URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }

        #expect(session.url.host == "www.fitbit.com")
        #expect(value("client_id") == "ABC123")
        #expect(value("response_type") == "code")
        #expect(value("redirect_uri") == redirect)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") != nil)
        #expect(value("state") == session.state)
    }

    /// RFC 7636: base64url, no padding. A padded challenge is rejected, and the
    /// rejection names nothing useful.
    @Test func theChallengeIsBase64URLWithoutPadding() {
        let challenge = FitbitOAuth.challenge(for: "a-verifier-of-some-length")
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }

    /// The scopes are space separated in one parameter, not repeated. Fitbit
    /// silently issues a narrower grant for a malformed scope list, and the
    /// first sign of it is a collection returning 403 much later.
    @Test func theScopesAreOneSpaceSeparatedParameter() throws {
        let session = FitbitOAuth.session(clientID: "ABC123", redirectURI: redirect,
                                          scopes: ["sleep", "heartrate"])
        let items = try #require(URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems)
        let scopes = items.filter { $0.name == "scope" }

        #expect(scopes.count == 1)
        #expect(scopes.first?.value == "sleep heartrate")
    }

    @Test func aMatchingRedirectYieldsItsCode() throws {
        let url = URL(string: "\(redirect)?code=the-code&state=xyz")!
        #expect(try FitbitOAuth.code(from: url, expectedState: "xyz") == "the-code")
    }

    /// A mismatch means the redirect did not originate from our request, so the
    /// code is discarded rather than exchanged.
    @Test func aMismatchedStateIsRejected() {
        let url = URL(string: "\(redirect)?code=the-code&state=someone-elses")!
        #expect(throws: FitbitAuthError.stateMismatch) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    @Test func aDenialIsReportedAsADenial() {
        let url = URL(string: "\(redirect)?error=access_denied&state=xyz")!
        #expect(throws: FitbitAuthError.denied("access_denied")) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    @Test func aRedirectWithNoCodeIsRejected() {
        let url = URL(string: "\(redirect)?state=xyz")!
        #expect(throws: FitbitAuthError.missingCode) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    /// Two taps on Connect start two valid authorizations, and whichever
    /// redirect returns must be matched by its own state. Keeping only the
    /// newest makes the earlier attempt's redirect fail as a mismatch, which
    /// looks exactly like an attack.
    @Test func theStateCanBeReadBeforeTheAttemptIsFound() {
        let url = URL(string: "\(redirect)?code=c&state=the-state")!
        #expect(FitbitOAuth.state(in: url) == "the-state")
    }

    /// An abandoned attempt must not authorise a redirect arriving much later.
    @Test func anOldAttemptIsNotFresh() {
        let pending = FitbitPendingAuth(verifier: "v", state: "s",
                                        startedAt: Date(timeIntervalSinceNow: -1_800))
        #expect(!pending.isFresh())
        #expect(FitbitPendingAuth(verifier: "v", state: "s").isFresh())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter FitbitOAuthTests`
Expected: FAIL to compile, "cannot find 'FitbitOAuth' in scope".

- [ ] **Step 3: Write FitbitOAuth**

Create `LifeOSKit/Sources/Integrations/FitbitOAuth.swift`:

```swift
import Foundation
import CryptoKit

/// Fitbit OAuth, client side only.
///
/// **This type never sees the client secret, and never sees a token either.**
/// The exchange runs in an Edge Function, and unlike Whoop the tokens stay
/// there: Fitbit rotates the refresh token on every use, so exactly one writer
/// may hold it.
///
/// The app does the half that is safe: build the authorize URL, hold the PKCE
/// verifier, and hand the returned `code` to the server.
public enum FitbitOAuth {
    public static let authorizeEndpoint = URL(string: "https://www.fitbit.com/oauth2/authorize")!

    /// Every scope the app reads. Kept in step with `FITBIT_SCOPES` in
    /// `supabase/functions/_shared/fitbit.ts`, which is pinned by its own test.
    public static let defaultScopes = [
        "activity", "cardio_fitness", "heartrate", "nutrition",
        "oxygen_saturation", "profile", "respiratory_rate", "sleep",
        "temperature", "weight",
    ]

    /// One authorization attempt. `verifier` and `state` must survive until the
    /// redirect comes back, and `state` must be compared on return.
    public struct Session: Sendable, Equatable {
        public let url: URL
        public let verifier: String
        public let state: String
    }

    /// PKCE binds the authorization code to this app instance, so an
    /// intercepted redirect cannot be replayed by another client.
    public static func session(
        clientID: String,
        redirectURI: String,
        scopes: [String] = defaultScopes,
        verifier: String = randomURLSafeString(),
        state: String = randomURLSafeString()
    ) -> Session {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            // One parameter, space separated. Repeating the parameter makes
            // Fitbit issue a narrower grant without saying so, and the first
            // sign of it is a collection returning 403 much later.
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return Session(url: components.url!, verifier: verifier, state: state)
    }

    /// Pulls the code out of the redirect, rejecting a mismatched `state`.
    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw FitbitAuthError.denied(error)
        }
        guard let state = items.first(where: { $0.name == "state" })?.value else {
            throw FitbitAuthError.missingState
        }
        guard state == expectedState else {
            throw FitbitAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw FitbitAuthError.missingCode
        }
        return code
    }

    /// The `state` a redirect carries, so the matching attempt can be found
    /// before its verifier is needed.
    public static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    public static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }
}

public enum FitbitAuthError: Error, Equatable {
    case denied(String)
    case missingState
    case stateMismatch
    case missingCode
}
```

- [ ] **Step 4: Write the pending attempt store**

Create `LifeOSKit/Sources/Integrations/FitbitAuthStore.swift`, holding `FitbitPendingAuth` and `FitbitAuthStoring` plus `KeychainFitbitAuthStore`. Copy the structure of `WhoopTokenStore.swift`'s pending-auth half exactly, including the account scoping via `KeychainAuthSessionStore.currentAccountKey`, and change the service to `"ai.lifeos.fitbit"`. It stores **only** pending attempts, never tokens:

```swift
/// The half-finished authorization: PKCE verifier and the `state` we issued.
///
/// Persisted because the sign-in happens in a web session, so the app is
/// backgrounded and may be terminated before the redirect returns. Holding
/// this only in memory means a suspended app comes back unable to verify or
/// exchange anything, and the user sees an unexplained failure.
public struct FitbitPendingAuth: Codable, Sendable, Equatable {
    public let verifier: String
    public let state: String
    public let startedAt: Date

    public init(verifier: String, state: String, startedAt: Date = .now) {
        self.verifier = verifier
        self.state = state
        self.startedAt = startedAt
    }

    /// An abandoned attempt should not authorise a redirect arriving much later.
    public func isFresh(now: Date = .now, within: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(startedAt) < within
    }
}

/// Deliberately has no token methods. Fitbit tokens live on the server,
/// because they rotate and only one writer may hold them.
public protocol FitbitAuthStoring: Sendable {
    /// All in-flight attempts, newest first. A list rather than one slot:
    /// tapping Connect twice starts two valid authorizations, and whichever
    /// redirect returns must be matched by its own `state`.
    func pendingAuths() -> [FitbitPendingAuth]
    func savePending(_ pending: FitbitPendingAuth) throws
    func clearPending()
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter FitbitOAuthTests`
Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FitbitOAuth.swift \
        LifeOSKit/Sources/Integrations/FitbitAuthStore.swift \
        LifeOSKit/Tests/IntegrationsTests/FitbitOAuthTests.swift
git commit -m "feat(fitbit): build the authorize URL and check the way back

Fitbit permits a custom scheme for a native app, so there is no bridge
hop and the user never leaves the app. Whoop needed one only because
Whoop requires an https redirect.

The store holds pending attempts and nothing else: there are no tokens
on the device to keep. Attempts are a list, because two taps on Connect
start two valid authorizations and each redirect must be matched by its
own state."
```

---

## Task 10: the connection view model and the card

**Files:**
- Create: `LIfeOS/Features/Settings/ViewModel/FitbitConnectionViewModel.swift`
- Modify: `LIfeOS/Features/Settings/Model/AppConfig.swift`
- Modify: `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift`
- Modify: `Config/Secrets.example.xcconfig`, `Config/App-Info.plist`

**Interfaces:**
- Consumes: `FitbitOAuth`, `FitbitAuthStoring`, `KeychainFitbitAuthStore`.
- Produces: `FitbitConnectionViewModel` with `state: State` (cases `unconfigured`, `disconnected`, `connecting`, `connected(lastSyncedDays: Int?)`, `needsReauth`, `failed(String)`), `isConnected: Bool`, `statusDetail: String`, `func connect()`, `func handle(_ url: URL) async`, `func disconnect() async`; `AppConfig.fitbitClientID`, `AppConfig.fitbitRedirectURI`, `AppConfig.fitbitTokenEndpoint`, `AppConfig.fitbitSyncEndpoint`, `AppConfig.isFitbitConfigured`.

- [ ] **Step 1: Add the configuration**

In `LIfeOS/Features/Settings/Model/AppConfig.swift`, add alongside the Whoop entries:

```swift
    static var fitbitClientID: String? { string("FitbitClientID") }
    static var fitbitRedirectURI: String? { string("FitbitRedirectURI") }

    /// The confidential-client exchange. Fitbit tokens never reach the app, so
    /// unlike Whoop there is no token endpoint the client reads from: this one
    /// only ever returns a confirmation.
    static var fitbitTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/fitbit-token")
    }

    static var fitbitSyncEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/fitbit-sync")
    }

    static var isFitbitConfigured: Bool {
        fitbitClientID?.isEmpty == false && fitbitTokenEndpoint != nil
    }
```

Add `FitbitClientID` and `FitbitRedirectURI` keys to `Config/App-Info.plist` reading `$(FitbitClientID)` and `$(FitbitRedirectURI)`, and add both with empty values to `Config/Secrets.example.xcconfig`. Set the real client id in the gitignored `Config/Secrets.xcconfig`. The redirect URI is `lifeos://fitbit-callback`.

- [ ] **Step 2: Write the view model**

Create `LIfeOS/Features/Settings/ViewModel/FitbitConnectionViewModel.swift`, modelled on `WhoopConnectionViewModel` but with these differences, each of which follows from the tokens living on the server:

- There is no token store to consult, so `refreshState()` asks the server. Until slice 3 adds a status endpoint, it holds the last known state in `UserDefaults` under a key scoped to the current account, and treats an unknown state as `.disconnected`.
- `connect()` opens the authorize URL in `ASWebAuthenticationSession` with `callbackURLScheme` taken from `AppConfig.appURLScheme`, not in Safari. The Safari hand-off exists for Whoop only because Whoop's login sits behind a Cloudflare challenge that will not clear inside a web-auth session. If Fitbit's login turns out to have the same problem, fall back to `UIApplication.shared.open` exactly as `WhoopConnectionViewModel.connect()` does, and record why in a comment.
- `handle(_:)` matches the redirect's `state` against the freshest pending attempt, exchanges via `AppConfig.fitbitTokenEndpoint` with the Supabase JWT in the `Authorization` header, and clears the pending attempt on success.
- `disconnect()` calls the server rather than clearing a local Keychain item.

Use `Logger(subsystem: "com.shivvyas.lifeos", category: "fitbit")` and log failures in full, for the reason given at the top of `WhoopConnectionViewModel`.

- [ ] **Step 3: Add the card**

In `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift`, add `@Bindable var fitbit: FitbitConnectionViewModel` and a fourth `connectionCard` between the Whoop and Apple Health cards:

```swift
                    connectionCard(
                        icon: "figure.run.circle.fill", hue: .body,
                        title: "Fitbit", status: fitbit.statusDetail,
                        chip: fitbitChip
                    ) { fitbit.connect() }
                    .disabled(fitbit.state == .unconfigured)
```

Add a `fitbitChip` computed property following `whoopChip`, returning the "Reconnect" verb for `.needsReauth` rather than a failure string, because a dead credential is an action the user can take and not an error to read.

Update every call site of `ConnectionsSettingsScreen(...)` to pass the new model. Find them with `grep -rn "ConnectionsSettingsScreen(" LIfeOS`.

- [ ] **Step 4: Build the app**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS Config
git commit -m "feat(fitbit): offer the connection in settings

A fourth card beside Whoop, Apple Health and the banks. Sign-in runs in
a web auth session rather than handing off to Safari, because Fitbit
permits a custom scheme redirect and the user never has to leave.

A dead credential shows Reconnect rather than an error string: it is an
action the user can take, not a fault they can only read."
```

---

# Slice 3: the range collections

## Task 11: the metrics Fitbit adds

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/HealthMetric.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/HealthMetricTests.swift`

**Interfaces:**
- Produces: `HealthMetric.activeZoneMinutes`, `.sleepEfficiencyPercentage`, `.readinessScore`; sleep-stage metrics become `claimedByWearable`.

- [ ] **Step 1: Write the failing test**

Append to `HealthMetricTests.swift`:

```swift
@Suite struct FitbitMetricsTests {

    /// The three Fitbit reports that the vocabulary had no case for.
    @Test func theNewMetricsDescribeThemselves() {
        for metric in [HealthMetric.activeZoneMinutes, .sleepEfficiencyPercentage, .readinessScore] {
            #expect(!metric.title.isEmpty)
            #expect(HealthMetric.Group.allCases.contains(metric.group))
        }
        #expect(HealthMetric.activeZoneMinutes.group == .movement)
        #expect(HealthMetric.sleepEfficiencyPercentage.group == .sleep)
        #expect(HealthMetric.readinessScore.group == .heart)
    }

    @Test func theNewMetricsFormatWithTheirUnits() {
        #expect(HealthMetric.activeZoneMinutes.formatted(42) == "42 min")
        #expect(HealthMetric.sleepEfficiencyPercentage.formatted(91.4) == "91.4 %")
    }

    /// A strap measures a sleep stage and a phone infers it from movement, so
    /// the strap outranks the phone now that one reports them.
    @Test func sleepStagesAreClaimedByAStrap() {
        for metric in [HealthMetric.deepSleepMinutes, .remSleepMinutes,
                       .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes] {
            #expect(metric.claimedByWearable, "\(metric.rawValue) is still phone-owned")
        }
    }

    /// None of them are typed, so none of them are protected from a sync.
    @Test func theNewMetricsAreNotHandEntered() {
        for metric in [HealthMetric.activeZoneMinutes, .sleepEfficiencyPercentage, .readinessScore] {
            #expect(!metric.acceptsManualEntry)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter FitbitMetricsTests`
Expected: FAIL to compile, "type 'HealthMetric' has no member 'activeZoneMinutes'".

- [ ] **Step 3: Add the cases**

In `HealthMetric.swift`, add `case activeZoneMinutes` to the Movement block, `case sleepEfficiencyPercentage` to the Sleep block, and `case readinessScore` to the Heart block. Then add each to `group`, `title` (`"Active zone minutes"`, `"Sleep efficiency"`, `"Readiness"`), `unitLabel` (`"min"`, `"%"`, `""`), and `decimals` (`0`, `1`, `0`).

Extend `claimedByWearable` to include the sleep stages:

```swift
    public var claimedByWearable: Bool {
        switch self {
        case .restingHR, .hrvMs, .spo2Percentage, .respiratoryRate,
             .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes,
             .sleepEfficiencyPercentage, .readinessScore:
            true
        default:
            false
        }
    }
```

Sleep stages join the list now, and not in slice 1, because until Fitbit reports them Apple Health was their only writer and the rank made no difference. Now it does: a strap measures a stage and a phone infers it from movement.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter IntegrationsTests`
Expected: PASS. `HealthMetricVocabularyTests.everyMetricHasATitleAndAGroup` and `rawValuesAreUnique` cover the new cases automatically, which is the point of writing them as loops over `allCases`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/HealthMetric.swift \
        LifeOSKit/Tests/IntegrationsTests/HealthMetricTests.swift
git commit -m "feat(health): add the metrics Fitbit reports and the phone does not

Active zone minutes, sleep efficiency and readiness had no case in the
vocabulary. Storage is keyed by rawValue and the screens list whatever
a day holds, so each one appears on its own the first time there is a
reading for it.

Sleep stages become strap-claimed now that something other than the
phone reports them. A strap measures a stage; a phone infers it from
movement."
```

---

## Task 12: decoding the range collections

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FitbitWireFormat.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FitbitWireFormatTests.swift`

**Interfaces:**
- Produces: `FitbitCollection` (enum, cases `sleep`, `hrv`, `spo2`, `breathing`, `skinTemperature`, `restingHeartRate`, `cardioFitness`, each with `var maximumRangeDays: Int`); `FitbitSleepPayload`, `FitbitHRVPayload`, `FitbitSpO2Payload`, `FitbitBreathingPayload`, `FitbitTemperaturePayload`, `FitbitHeartPayload`, `FitbitCardioPayload`, all `Decodable`; `FitbitPayloads` (the whole sync response, one optional payload per collection); `FitbitDay` (`date: Date`, `values: [HealthMetric: Double]`).

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/FitbitWireFormatTests.swift` with a fixture per collection, taken from Fitbit's published response shapes. The sleep fixture is the one that matters most, because it is the only nested payload:

```swift
import Testing
import Foundation
@testable import Integrations

/// Decoding, pinned against Fitbit's published response shapes.
///
/// Wire format is the one thing that cannot be verified without a live token,
/// so it is pinned against fixtures instead. A silent decode failure here
/// looks exactly like a person having no data.
@Suite struct FitbitWireFormatTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func sleepDecodesItsStages() throws {
        let payload = try decode(FitbitSleepPayload.self, """
        {"sleep":[{"dateOfSleep":"2026-08-26","duration":28800000,"efficiency":91,
          "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages",
          "levels":{"summary":{
            "deep":{"count":4,"minutes":78},
            "light":{"count":29,"minutes":244},
            "rem":{"count":6,"minutes":110},
            "wake":{"count":31,"minutes":48}}}}]}
        """)

        let night = try #require(payload.sleep.first)
        #expect(night.dateOfSleep == "2026-08-26")
        #expect(night.minutesAsleep == 432)
        #expect(night.timeInBed == 480)
        #expect(night.efficiency == 91)
        #expect(night.levels?.summary.deep?.minutes == 78)
        #expect(night.levels?.summary.rem?.minutes == 110)
        #expect(night.levels?.summary.light?.minutes == 244)
        #expect(night.levels?.summary.wake?.minutes == 48)
    }

    /// A classic log has no stages at all. It must decode, not throw, or one
    /// unstaged night takes the whole range down with it.
    @Test func aClassicSleepLogDecodesWithoutStages() throws {
        let payload = try decode(FitbitSleepPayload.self, """
        {"sleep":[{"dateOfSleep":"2026-08-25","duration":21600000,"efficiency":88,
          "minutesAsleep":360,"minutesAwake":20,"timeInBed":380,"type":"classic"}]}
        """)

        let night = try #require(payload.sleep.first)
        #expect(night.minutesAsleep == 360)
        #expect(night.levels == nil)
    }

    @Test func hrvDecodesTheDailyAndDeepValues() throws {
        let payload = try decode(FitbitHRVPayload.self, """
        {"hrv":[{"dateTime":"2026-08-26","value":{"dailyRmssd":34.2,"deepRmssd":41.6}}]}
        """)
        #expect(payload.hrv.first?.value.dailyRmssd == 34.2)
        #expect(payload.hrv.first?.value.deepRmssd == 41.6)
    }

    @Test func restingHeartRateDecodesOutOfTheActivitiesEnvelope() throws {
        let payload = try decode(FitbitHeartPayload.self, """
        {"activities-heart":[{"dateTime":"2026-08-26","value":{"restingHeartRate":54}}]}
        """)
        #expect(payload.days.first?.value.restingHeartRate == 54)
    }

    @Test func spo2AndBreathingAndTemperatureDecode() throws {
        let spo2 = try decode(FitbitSpO2Payload.self, """
        [{"dateTime":"2026-08-26","value":{"avg":95.7,"min":91.2,"max":98.4}}]
        """)
        #expect(spo2.first?.value.avg == 95.7)

        let breathing = try decode(FitbitBreathingPayload.self, """
        {"br":[{"dateTime":"2026-08-26","value":{"breathingRate":14.8}}]}
        """)
        #expect(breathing.br.first?.value.breathingRate == 14.8)

        let temperature = try decode(FitbitTemperaturePayload.self, """
        {"tempSkin":[{"dateTime":"2026-08-26","value":{"nightlyRelative":-0.3}}]}
        """)
        #expect(temperature.tempSkin.first?.value.nightlyRelative == -0.3)
    }

    /// A device with no such sensor returns an empty collection. Absence is
    /// normal and must decode to nothing, never to a zero and never to a throw.
    @Test func aSensorlessDeviceReturnsAnEmptyRange() throws {
        #expect(try decode(FitbitHRVPayload.self, #"{"hrv":[]}"#).hrv.isEmpty)
        #expect(try decode(FitbitSleepPayload.self, #"{"sleep":[]}"#).sleep.isEmpty)
        #expect(try decode(FitbitSpO2Payload.self, "[]").isEmpty)
    }

    /// The range caps are Fitbit's, and exceeding one is a 400 that names
    /// nothing useful.
    @Test func eachCollectionKnowsItsRangeCap() {
        #expect(FitbitCollection.sleep.maximumRangeDays == 100)
        #expect(FitbitCollection.restingHeartRate.maximumRangeDays == 365)
        for collection in [FitbitCollection.hrv, .spo2, .breathing,
                           .skinTemperature, .cardioFitness] {
            #expect(collection.maximumRangeDays == 30)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter FitbitWireFormatTests`
Expected: FAIL to compile, "cannot find 'FitbitSleepPayload' in scope".

- [ ] **Step 3: Write the wire format**

Create `LifeOSKit/Sources/Integrations/FitbitWireFormat.swift`. Every numeric field is optional, because a Fitbit response omits what a device did not record and a non-optional field turns one missing number into a whole failed range.

```swift
import Foundation

// MARK: - Sleep

public struct FitbitSleepPayload: Decodable, Sendable {
    public struct Night: Decodable, Sendable {
        public let dateOfSleep: String
        public let efficiency: Double?
        public let minutesAsleep: Double?
        public let minutesAwake: Double?
        public let timeInBed: Double?
        public let type: String?
        /// Absent on a classic log, which has no stages at all. One unstaged
        /// night must not take the whole range down with it.
        public let levels: Levels?
    }
    public struct Levels: Decodable, Sendable {
        public let summary: Summary
    }
    public struct Summary: Decodable, Sendable {
        public let deep: Stage?
        public let light: Stage?
        public let rem: Stage?
        public let wake: Stage?
    }
    public struct Stage: Decodable, Sendable {
        public let count: Int?
        public let minutes: Double?
    }
    public let sleep: [Night]
}

// MARK: - Interval collections

public struct FitbitHRVPayload: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable {
        public let dailyRmssd: Double?
        public let deepRmssd: Double?
    }
    public let hrv: [Day]
}

/// SpO2 by interval is a bare array, not an envelope. Fitbit is not consistent
/// about this and a wrapper struct here decodes to nothing, silently.
public typealias FitbitSpO2Payload = [FitbitSpO2Day]

public struct FitbitSpO2Day: Decodable, Sendable {
    public struct Value: Decodable, Sendable {
        public let avg: Double?
        public let min: Double?
        public let max: Double?
    }
    public let dateTime: String
    public let value: Value
}

public struct FitbitBreathingPayload: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable {
        public let breathingRate: Double?
    }
    public let br: [Day]
}

public struct FitbitTemperaturePayload: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable {
        /// Fitbit reports skin temperature as a nightly *variation* from the
        /// user's own baseline, not an absolute. Stored as its own metric
        /// rather than mapped onto a body temperature, which it is not.
        public let nightlyRelative: Double?
    }
    public let tempSkin: [Day]
}

public struct FitbitHeartPayload: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable {
        public let restingHeartRate: Double?
    }
    /// The wire name is `activities-heart`, which is not a Swift identifier.
    public let days: [Day]

    private enum CodingKeys: String, CodingKey {
        case days = "activities-heart"
    }
}

public struct FitbitCardioPayload: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable {
        /// Fitbit sends either a single number or a range like "40-44",
        /// depending on whether the user ran with GPS. Kept as the string it
        /// arrives as; the derivation takes the midpoint of a range.
        public let vo2Max: String?
    }
    public let cardioScore: [Day]
}

// MARK: - The whole response

/// One sync's worth of raw collections. Every field optional: a collection
/// that failed for a declined scope is absent, and the other six still land.
public struct FitbitPayloads: Decodable, Sendable {
    public var sleep: FitbitSleepPayload?
    public var hrv: FitbitHRVPayload?
    public var spo2: FitbitSpO2Payload?
    public var breathing: FitbitBreathingPayload?
    public var skinTemperature: FitbitTemperaturePayload?
    public var restingHeartRate: FitbitHeartPayload?
    public var cardioFitness: FitbitCardioPayload?

    public init(
        sleep: FitbitSleepPayload? = nil, hrv: FitbitHRVPayload? = nil,
        spo2: FitbitSpO2Payload? = nil, breathing: FitbitBreathingPayload? = nil,
        skinTemperature: FitbitTemperaturePayload? = nil,
        restingHeartRate: FitbitHeartPayload? = nil,
        cardioFitness: FitbitCardioPayload? = nil
    ) {
        self.sleep = sleep; self.hrv = hrv; self.spo2 = spo2
        self.breathing = breathing; self.skinTemperature = skinTemperature
        self.restingHeartRate = restingHeartRate; self.cardioFitness = cardioFitness
    }
}

/// One day's worth of Fitbit readings, ready to merge.
public struct FitbitDay: Sendable, Equatable {
    public let date: Date
    public let values: [HealthMetric: Double]

    public init(date: Date, values: [HealthMetric: Double]) {
        self.date = date
        self.values = values
    }
}
```

Add the collection enum:

```swift
/// The collections pulled by range. Per-date collections (activity summary,
/// nutrition) arrive in slice 4, where the quota cursor lives.
public enum FitbitCollection: String, CaseIterable, Sendable {
    case sleep, hrv, spo2, breathing, skinTemperature, restingHeartRate, cardioFitness

    /// Fitbit's own cap. Exceeding it is a 400 that names nothing useful.
    public var maximumRangeDays: Int {
        switch self {
        case .sleep: 100
        case .restingHeartRate: 365
        case .hrv, .spo2, .breathing, .skinTemperature, .cardioFitness: 30
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter FitbitWireFormatTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FitbitWireFormat.swift \
        LifeOSKit/Tests/IntegrationsTests/FitbitWireFormatTests.swift
git commit -m "feat(fitbit): decode the range collections

Wire format is the one thing that cannot be verified without a live
token, so it is pinned against fixtures. A silent decode failure looks
exactly like a person having no data, which is why the empty range and
the unstaged classic sleep log both have tests of their own.

Every field a device might not record is optional, because one missing
number must not fail a whole range."
```

---

## Task 13: deriving a day from Fitbit

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FitbitDerivation.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FitbitDerivationTests.swift`

**Interfaces:**
- Consumes: the payload types from Task 12, `MetricArbiter`, `SourceRanking`, `MetricsStore`.
- Produces: `FitbitDerivation(store:ranking:)` with `func derive(_ payloads: FitbitPayloads) throws`, and `FitbitDerivation.days(from: FitbitPayloads) -> [FitbitDay]` as the pure half.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/FitbitDerivationTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// Payloads to values on the spine. The mapping is the part that can be
/// perfectly decoded and still land in the wrong column.
@Suite @MainActor struct FitbitDerivationTests {

    private func store() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private let day = Calendar.current.startOfDay(
        for: ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
    )

    /// Fitbit calls it light and Apple calls it core. They are the same stage
    /// under two vendors' names, and filing Fitbit's light anywhere else would
    /// leave the sleep panel with a blank row and an unexplained total.
    @Test func lightSleepBecomesCore() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(.fixtureWithStages)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.extra(HealthMetric.coreSleepMinutes.rawValue) == 244)
        #expect(row.extra(HealthMetric.deepSleepMinutes.rawValue) == 78)
        #expect(row.extra(HealthMetric.remSleepMinutes.rawValue) == 110)
        #expect(row.sleepMinutes == 432)
    }

    @Test func everyDerivedValueIsAttributedToFitbit() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(.fixtureWithStages)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.source(HealthMetric.sleepMinutes.rawValue) == MetricSource.fitbit.rawValue)
        #expect(row.source(HealthMetric.coreSleepMinutes.rawValue) == MetricSource.fitbit.rawValue)
    }

    /// Whoop is primary by default, so Fitbit fills its gaps and does not
    /// overwrite what the strap measured.
    @Test func fitbitDoesNotOverwriteThePrimaryStrap() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.sleepMinutes = 400
            row.setSource(HealthMetric.sleepMinutes.rawValue, MetricSource.whoop.rawValue)
        }

        try FitbitDerivation(store: store).derive(.fixtureWithStages)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 400)
    }

    /// But when the user names Fitbit as primary, it wins.
    @Test func fitbitOverwritesWhenItIsPrimary() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.sleepMinutes = 400
            row.setSource(HealthMetric.sleepMinutes.rawValue, MetricSource.whoop.rawValue)
        }

        try FitbitDerivation(store: store, ranking: SourceRanking(primaryWearable: .fitbit))
            .derive(.fixtureWithStages)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 432)
    }

    /// deepRmssd is a different measurement from dailyRmssd. Averaging them or
    /// writing both to hrvMs would be a fabricated number.
    @Test func onlyTheDailyRmssdBecomesHRV() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(.fixtureWithStages)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.hrvMs == 34.2)
    }

    /// An empty payload writes nothing at all, rather than a row of zeroes.
    @Test func anEmptyPayloadWritesNothing() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(.empty)
        #expect(try store.metrics(from: day, to: day).isEmpty)
    }
}
```

Add a `FitbitPayloads` fixture extension in the test file supplying `.fixtureWithStages` (built from the same JSON as Task 12's fixtures) and `.empty`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter FitbitDerivationTests`
Expected: FAIL to compile, "cannot find 'FitbitDerivation' in scope".

- [ ] **Step 3: Write the derivation**

Create `LifeOSKit/Sources/Integrations/FitbitDerivation.swift`. Structure it as `WhoopDerivation` is: a pure `days(from:)` that turns payloads into `[FitbitDay]`, and a `derive` that writes them through `MetricsStore.upsertBatch`, merging every value through `MetricArbiter` with `incomingSource: .fitbit` and recording provenance, exactly as Task 5's `merged` helper does.

The mappings, each of which is a judgement rather than a rename and belongs in a comment:

```swift
// Fitbit calls it light and Apple calls it core. The same stage under two
// vendors' names.
values[.coreSleepMinutes] = night.levels?.summary.light?.minutes
values[.deepSleepMinutes] = night.levels?.summary.deep?.minutes
values[.remSleepMinutes]  = night.levels?.summary.rem?.minutes
values[.awakeMinutes]     = night.levels?.summary.wake?.minutes
values[.sleepMinutes]     = night.minutesAsleep
values[.timeInBedMinutes] = night.timeInBed
values[.sleepEfficiencyPercentage] = night.efficiency

// dailyRmssd only. deepRmssd measures a different thing over a different
// window, and averaging the two would be a number Fitbit never reported.
values[.hrvMs] = hrv.value.dailyRmssd
```

`dateOfSleep` and `dateTime` are `"yyyy-MM-dd"` strings in the user's local time. Parse them with a `DateFormatter` pinned to `Calendar.current.timeZone` and `Locale(identifier: "en_US_POSIX")`, then take `startOfDay`. Using an ISO8601 parser here shifts every night by a day for anyone west of UTC.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter FitbitDerivationTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FitbitDerivation.swift \
        LifeOSKit/Tests/IntegrationsTests/FitbitDerivationTests.swift
git commit -m "feat(fitbit): derive a day and merge it through the arbiter

Fitbit's light sleep is Apple's core: the same stage under two vendors'
names, and filing it anywhere else leaves a blank row and a total that
does not add up.

Only dailyRmssd becomes HRV. deepRmssd measures a different thing over
a different window, so it is kept as an extra rather than averaged into
a number Fitbit never reported.

Dates are parsed in the local time zone, because Fitbit sends a plain
yyyy-MM-dd and an ISO parser shifts every night for anyone west of UTC."
```

---

## Task 14: the fitbit-sync function

**Files:**
- Create: `supabase/functions/fitbit-sync/index.ts`
- Modify: `supabase/functions/_shared/fitbit.ts`
- Modify: `supabase/functions/_shared/fitbit_test.ts`

**Interfaces:**
- Consumes: `resolveUser`, `serviceClient`, `json`; `FITBIT_API_BASE`, `classifyFitbitFailure`, `quotaRemaining`, `tokenForm`, `FITBIT_TOKEN_URL`.
- Produces: `POST /functions/v1/fitbit-sync` taking `{days: number}` and returning `{payloads: {sleep, hrv, spo2, breathing, skinTemperature, restingHeartRate, cardioFitness}, failures: {collection: FitbitFailure}, needs_reauth: boolean}`; and `rangePath(collection, start, end): string` added to `_shared/fitbit.ts` with tests.

- [ ] **Step 1: Write the failing test for the path builder**

Append to `supabase/functions/_shared/fitbit_test.ts`:

```ts
import { rangePath } from "./fitbit.ts";

// Each collection sits at its own path shape, and Fitbit answers a wrong one
// with a 404 that names nothing.
Deno.test("each collection knows its own path shape", () => {
  assertEquals(
    rangePath("sleep", "2026-07-28", "2026-08-26"),
    "/1.2/user/-/sleep/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("hrv", "2026-07-28", "2026-08-26"),
    "/1/user/-/hrv/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("restingHeartRate", "2026-07-28", "2026-08-26"),
    "/1/user/-/activities/heart/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("skinTemperature", "2026-07-28", "2026-08-26"),
    "/1/user/-/temp/skin/date/2026-07-28/2026-08-26.json",
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `deno test supabase/functions/_shared/fitbit_test.ts`
Expected: FAIL, `rangePath` is not exported.

- [ ] **Step 3: Add rangePath**

Append to `supabase/functions/_shared/fitbit.ts`:

```ts
/// Where each range collection lives. Sleep is the only one on v1.2, and
/// Fitbit answers a wrong path with a 404 that names nothing.
export function rangePath(collection: string, start: string, end: string): string {
  switch (collection) {
    case "sleep":            return `/1.2/user/-/sleep/date/${start}/${end}.json`;
    case "hrv":              return `/1/user/-/hrv/date/${start}/${end}.json`;
    case "spo2":             return `/1/user/-/spo2/date/${start}/${end}.json`;
    case "breathing":        return `/1/user/-/br/date/${start}/${end}.json`;
    case "skinTemperature":  return `/1/user/-/temp/skin/date/${start}/${end}.json`;
    case "restingHeartRate": return `/1/user/-/activities/heart/date/${start}/${end}.json`;
    case "cardioFitness":    return `/1/user/-/cardioscore/date/${start}/${end}.json`;
    default: throw new Error(`unknown collection ${collection}`);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `deno test supabase/functions/_shared/fitbit_test.ts`
Expected: PASS, 8 tests.

- [ ] **Step 5: Write the sync function**

Create `supabase/functions/fitbit-sync/index.ts`. The shape, in order:

1. `resolveUser(req)`; 401 if absent.
2. Load the connection **under a lock**. Supabase's PostgREST cannot express `for update`, so add a small SQL function in the same migration directory and call it with `rpc`. Create `supabase/migrations/20260829091000_fitbit_lock.sql`:

```sql
-- Claims the connection row for the duration of the calling transaction.
--
-- The lock is the whole reason the tokens are server side. Fitbit rotates the
-- refresh token on every use, so two devices syncing at once would each
-- rotate it and invalidate the other, and the user would be signed out by
-- their own second phone.
create or replace function public.claim_fitbit_connection(p_user_id uuid)
returns public.fitbit_connections
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.fitbit_connections;
begin
  select * into claimed
  from public.fitbit_connections
  where user_id = p_user_id
  for update;
  return claimed;
end;
$$;

revoke all on function public.claim_fitbit_connection(uuid) from public, anon, authenticated;
```

3. If `needs_reauth` is already true, return `{needs_reauth: true}` immediately without calling Fitbit.
4. If `access_expires_at` is in the past, refresh via `FITBIT_TOKEN_URL` with `tokenForm({refresh_token})` and Basic auth. On success, write back **both** new tokens and the new expiry. On `classifyFitbitFailure(...) === "needs_reauth"`, set `needs_reauth = true` and return `{needs_reauth: true}`.
5. Fetch the seven collections, clamping each range to its own `maximumRangeDays` (100 for sleep, 365 for resting heart rate, 30 for the rest). Fetch them with `await` in sequence rather than `Promise.all`, so `quotaRemaining` from each response can stop the loop before the quota is gone.
6. Collect each collection's raw JSON into `payloads`, and each failure into `failures` keyed by collection. **One collection failing must never abort the others.** Wrap each fetch in its own try/catch.
7. Return `{payloads, failures, needs_reauth: false}`.

- [ ] **Step 6: Check it type-checks**

Run: `deno check supabase/functions/fitbit-sync/index.ts`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/fitbit-sync supabase/functions/_shared \
        supabase/migrations/20260829091000_fitbit_lock.sql
git commit -m "feat(fitbit): fetch the range collections under a row lock

The lock is why the tokens are server side at all: Fitbit rotates the
refresh token on every use, so two devices syncing at once each rotate
it and invalidate the other.

Collections are fetched in sequence rather than in parallel so the
quota headroom in each response can stop the loop before the hour's 150
requests are gone, and each one is caught on its own so a declined
scope does not take the rest of the sync down with it."
```

---

## Task 15: FitbitSync on the device

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FitbitSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FitbitSyncTests.swift`

**Interfaces:**
- Consumes: `FitbitDerivation`, the `FitbitWireFormat` types, and `WhoopArchive` from `Persistence`.
- Produces: `FitbitSync(endpoint:session:derivation:archive:)` with `func sync(days: Int, token: String) async throws -> Int` returning the number of days written, and `FitbitSyncError` with cases `notConnected`, `reauthenticationRequired`, `partial(failed: [String])`.

**On the archive type.** `WhoopArchive` is already a generic raw-record store: `store(kind:externalID:payload:)` keyed by an arbitrary `kind` string. Reuse it with kinds prefixed `fitbit-` (`fitbit-sleep`, `fitbit-hrv`, and so on) rather than adding a second archive. Its name is now a misnomer; renaming it to `RawArchive` is a mechanical follow-up worth doing separately, because it touches Whoop code this plan otherwise leaves alone.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/FitbitSyncTests.swift`. The repo's `URLProtocol` stub pattern is in `LifeOSKit/Tests/IntegrationsTests/AuthSessionProfileTests.swift` (`AuthStubURLProtocol` and its `Reply` type, with `ProfileStubURLProtocol` as a second instance of the same shape). Read that file and follow it; do **not** invent a new stubbing approach.

```swift
import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// The device half of the sync. There are no tokens here to test: they live on
/// the server, because Fitbit rotates them. What is pinned is what the app does
/// with each kind of answer the function can give.
@Suite @MainActor struct FitbitSyncTests {

    private func store() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private let day = Calendar.current.startOfDay(
        for: ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
    )

    /// A dead credential is not a retry. The app stops and asks the user to
    /// reconnect rather than spinning against a token nothing can revive.
    @Test func aNeedsReauthResponseEndsTheSync() async throws {
        let sync = makeSync(replying: .status(200, #"{"needs_reauth":true,"payloads":{},"failures":{}}"#))

        await #expect(throws: FitbitSyncError.reauthenticationRequired) {
            try await sync.sync(days: 30, token: "jwt")
        }
    }

    /// One declined scope must not lose the other six collections. The write
    /// happens first and the partial failure is reported after it.
    @Test func aPartialFailureStillWritesWhatArrived() async throws {
        let store = try store()
        let sync = makeSync(store: store, replying: .status(200, """
        {"needs_reauth":false,
         "payloads":{"sleep":{"sleep":[{"dateOfSleep":"2026-08-26","efficiency":91,
           "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages"}]}},
         "failures":{"hrv":"forbidden_scope"}}
        """))

        await #expect(throws: FitbitSyncError.partial(failed: ["hrv"])) {
            try await sync.sync(days: 30, token: "jwt")
        }

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 432)
    }

    /// Archive first: a re-derive reads from the archive, and a payload that
    /// was never stored cannot be re-derived from.
    @Test func rawPayloadsAreArchivedBeforeTheyAreDerived() async throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let sync = makeSync(context: context, replying: .status(200, """
        {"needs_reauth":false,
         "payloads":{"sleep":{"sleep":[{"dateOfSleep":"2026-08-26","efficiency":91,
           "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages"}]}},
         "failures":{}}
        """))

        _ = try await sync.sync(days: 30, token: "jwt")

        let archived = try context.fetch(FetchDescriptor<WhoopRawRecord>())
        #expect(archived.contains { $0.kind == "fitbit-sleep" })
    }

    /// A person with no Fitbit data is not a failure, and must not surface as
    /// one on the connections card.
    @Test func anEmptySyncIsNotAnError() async throws {
        let sync = makeSync(replying: .status(200, #"{"needs_reauth":false,"payloads":{},"failures":{}}"#))

        let written = try await sync.sync(days: 30, token: "jwt")
        #expect(written == 0)
    }

    /// The caller's Supabase JWT has to reach the function, or every sync is a
    /// 401 that looks like a broken connection.
    @Test func theRequestCarriesTheCallersToken() async throws {
        let sync = makeSync(replying: .status(200, #"{"needs_reauth":false,"payloads":{},"failures":{}}"#))
        _ = try await sync.sync(days: 30, token: "jwt")

        let sent = try #require(FitbitStubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
    }
}
```

Write the `makeSync(store:context:replying:)` helper and a `FitbitStubURLProtocol` (copying `AuthStubURLProtocol`, plus a `lastRequest` static so the header assertion above can read it) at the bottom of the file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter FitbitSyncTests`
Expected: FAIL to compile.

- [ ] **Step 3: Write FitbitSync**

Create `LifeOSKit/Sources/Integrations/FitbitSync.swift`, modelled on `WhoopSync` minus the token handling, which no longer exists on the device. Order inside `sync`:

1. POST to the endpoint with the Supabase JWT and `{days}`.
2. If the response says `needs_reauth`, throw `.reauthenticationRequired`.
3. **Archive the raw payloads first**, for the reason stated in `WhoopSync`: a re-derive reads from the archive, and a payload that was never stored cannot be re-derived from.
4. Decode and derive.
5. If `failures` is non-empty, throw `.partial(failed:)` **after** the write, so a declined scope does not discard the six collections that succeeded.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter FitbitSyncTests`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS, every target.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FitbitSync.swift \
        LifeOSKit/Tests/IntegrationsTests/FitbitSyncTests.swift
git commit -m "feat(fitbit): archive the payloads, then derive the days

Archive first, for the reason WhoopSync gives: a re-derive reads from
the archive, and a payload that was never stored cannot be re-derived
from.

A partial failure throws after the write, not before, so one declined
scope does not discard the six collections that arrived intact."
```

---

## Done when

- `cd LifeOSKit && swift test` passes on every target.
- `deno test supabase/functions/_shared/fitbit_test.ts` passes.
- `deno check supabase/functions/fitbit-token/index.ts supabase/functions/fitbit-sync/index.ts` is clean.
- The app builds and Connections shows four cards.
- Connecting a real Fitbit account writes a `fitbit_connections` row and a sync fills a day with sleep stages, HRV, SpO2, breathing rate, skin temperature, resting heart rate and VO2 max.
- `./scripts/check-typography.sh` exits zero, if any view was touched.

Slices 4 and 5 follow in a separate plan, written once slice 3 has met Fitbit's real payloads.
