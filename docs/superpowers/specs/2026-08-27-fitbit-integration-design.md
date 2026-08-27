# Fitbit integration

Date: 2026-08-27

## What this is

A second wearable. Fitbit joins Whoop and Apple Health as a source for the
daily spine, pulled from the Fitbit Web API over OAuth, with Apple Health
remaining the fallback for anyone who will not grant it.

Fitbit is owned by Google, and on iOS the Fitbit Web API is the only route to
Google-held health data. Health Connect is Android only, and the older Google
Fit REST APIs are being turned down. There is no second path to evaluate.

The feature is not only a new source. Adding a second strap breaks the rule
that decides which reading wins, because that rule is currently a boolean that
cannot name who wrote a value. Replacing it is the larger half of the work and
lands first.

## Verified facts that shaped the design

Checked against Fitbit's documentation on 2026-08-27. Each one changed a
decision, so each is recorded with what it changed.

| Fact | Consequence |
|---|---|
| Refresh tokens rotate and are single use. A new refresh token is returned with every access token. | Tokens live on the server, not in the Keychain. Two devices sharing one refresh token would invalidate each other on every sync. |
| Access tokens last 8 hours. | Refresh on expiry, not on every call. |
| Rate limit is 150 requests per hour per consenting user, resetting at the top of the hour, reported by `Fitbit-Rate-Limit-Remaining` and `Fitbit-Rate-Limit-Reset`, with HTTP 429 on exhaustion. | Backfill is quota aware and resumable. Deep history pages across hours. |
| Native applications may use custom URL schemes as redirect URIs. | No callback bridge function. Whoop needed one because Whoop requires an https redirect. Fitbit does not. |
| Sleep by date range: maximum 100 days, returns full stages. | One request covers any backfill window the app offers. |
| HRV, SpO2, breathing rate and skin temperature by interval: maximum 30 days. | Backfill deeper than 30 days chunks these. |
| Daily activity summary is per date. | 30 days of steps costs 30 of the 150 requests. This is the collection that constrains backfill. |
| Intraday data requires case by case approval from Fitbit for Server type applications. | Minute level heart rate is out of scope for launch. |
| Daily Readiness requires Fitbit Premium. | Best effort. Its absence is not an error. |

## Architecture

Fitbit gets its own client and derivation. It does not share `WhoopClient`,
because the shape of the two APIs has nothing in common: Whoop's client is
large due to its pagination and raw splitting, and Fitbit's range endpoints
have neither.

What is shared is the one thing the feature actually forces into common: the
decision about which source owns a metric. That becomes `MetricArbiter`, and
both Whoop's and Fitbit's derivation write through it.

New files:

| Path | Purpose |
|---|---|
| `supabase/migrations/*_fitbit_connections.sql` | One row per user under RLS, holding the rotating token pair. Follows `plaid_items`. |
| `supabase/functions/fitbit-token/index.ts` | Authorization code exchange and refresh. Sole writer of the rotating token. |
| `supabase/functions/fitbit-sync/index.ts` | Fetches collections, respects the quota, returns raw payloads. |
| `LifeOSKit/Sources/Integrations/FitbitOAuth.swift` | PKCE authorize URL, redirect parsing, state checking. |
| `LifeOSKit/Sources/Integrations/FitbitWireFormat.swift` | Decoding for each collection. |
| `LifeOSKit/Sources/Integrations/FitbitDerivation.swift` | Payloads to `HealthMetric` values on the daily spine. |
| `LifeOSKit/Sources/Integrations/FitbitSync.swift` | Calls the sync function, archives raw, derives. |
| `LifeOSKit/Sources/Integrations/FitbitBackfill.swift` | Quota and cursor arithmetic, as a pure function. |
| `LifeOSKit/Sources/Integrations/MetricArbiter.swift` | Replaces `HealthFill`. Source ranked merge. |
| `LIfeOS/Features/Settings/ViewModel/FitbitConnectionViewModel.swift` | Connection state for the card. |

Changed files:

| Path | Change |
|---|---|
| `LifeOSKit/Sources/Persistence/DailyMetrics.swift` | Adds optional `sourcesData: Data?`. |
| `LifeOSKit/Sources/Integrations/HealthApply.swift` | Takes a `source:` argument, passes it to the arbiter. |
| `LifeOSKit/Sources/Integrations/HealthMetric.swift` | New cases; `precedence` retires in favour of ranks. |
| `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift` | Fourth card, primary wearable picker. |
| `LIfeOS/Features/Settings/Model/AppConfig.swift` | Fitbit client id, redirect, function endpoints. |

## Connecting

The app builds a PKCE authorize URL with `S256`, `redirect_uri` of
`lifeos://fitbit-callback`, and opens it in `ASWebAuthenticationSession`. The
user does not leave the app. The verifier and `state` are written to the
Keychain before the session opens, mirroring `WhoopPendingAuth`, because iOS
may terminate a backgrounded app before the redirect returns. A list of pending
attempts rather than one slot, for the same reason Whoop keeps a list: two taps
on Connect start two valid authorizations, and each redirect must be matched by
its own `state`.

Scopes requested:

    activity  cardio_fitness  heartrate  nutrition  oxygen_saturation
    profile   respiratory_rate  sleep  temperature  weight

Deliberately not requested: `location`, `social`, `settings`,
`electrocardiogram`, `irregular_rhythm_notifications`, `blood_glucose`. None
feed the daily spine, and every unused scope is a line on the consent screen
asking for something the app will not read.

The app posts `{code, verifier, redirect_uri}` with its Supabase JWT to
`fitbit-token`. The function exchanges with Fitbit using HTTP Basic auth,
writes the token pair to `fitbit_connections` keyed by `auth.uid()`, and
returns `{connected, scopes, fitbit_user_id}`.

The access token never reaches the device. This is stronger than the Whoop
arrangement, where the device holds a live credential, and it follows from the
rotation constraint rather than being an extra goal.

## Syncing

The app calls `fitbit-sync` with its JWT and a day window.

The function takes a transactional row lock on the connection before touching
the token:

    select * from fitbit_connections where user_id = auth.uid() for update

This lock is the reason the tokens moved server side. Without it, two devices
syncing at once each rotate the refresh token and invalidate the other, and the
user is signed out by their own second device.

It refreshes only when the 8 hour access token has actually expired, fetches
the collections, and returns the raw payloads.

Raw passthrough, not normalization, for two reasons. It preserves the archive
then derive shape Whoop already has, so a derivation bug is fixed by re-deriving
from stored payloads rather than by re-hitting a quota limited API. And it keeps
interpretation on device, where the test suites already are. The function's job
is credentials and quota, not meaning.

### Collections

| Collection | Endpoint shape | Max range |
|---|---|---|
| Sleep with stages | range | 100 days |
| HRV | interval | 30 days |
| SpO2 | interval | 30 days |
| Breathing rate | interval | 30 days |
| Skin temperature | interval | 30 days |
| Resting heart rate | time series range | 1 year |
| Cardio fitness (VO2 max) | interval | 30 days |
| Daily activity summary | per date | one day per request |
| Activity log (workouts) | paginated list | n/a |
| Weight and body fat (body time series) | range, one request per resource | 1095 days |
| Nutrition and water | per date | one day per request |
| Daily Readiness | interval, Premium only | 30 days |

### Quota budget

A 30 day backfill costs roughly 7 range requests, 30 per date activity
summaries, and about 3 for workouts and weight: near 40 of 150. Comfortable.

90 days would cost about 100 activity summaries and crowd the cap. So the
function reads `Fitbit-Rate-Limit-Remaining` on every response, stops while it
still holds headroom, and returns a resume cursor the app stores. Backfill
pages across hours instead of failing. `FitbitBackfill` holds this arithmetic
as a pure function so it is testable without an API.

## The arbiter

### Why the current rule cannot survive a second strap

`HealthFill.value(for:existing:health:)` decides using the metric and whether a
value is already present. That is sufficient today because there are two
writers and a fixed story: Whoop writes, Health fills gaps.

It cannot express a primary wearable choice. When Fitbit is primary and Whoop
has already written last night's sleep, Fitbit must overwrite, and
`fillGapsOnly` cannot tell a Whoop value from a typed one. The row records what
a value is and never who put it there.

### Provenance

`DailyMetrics.extras` is a `[String: Double]` bag and cannot hold a source
name. So `DailyMetrics` gains:

    public var sourcesData: Data?   // [metricRawValue: sourceID]

Additive and optional, so the SwiftData migration is lightweight.

### Ranks

| Rank | Source | Meaning |
|---|---|---|
| 4 | manual | A person typed it. No sync overwrites it. |
| 3 | primary wearable | Whichever of Whoop or Fitbit the user chose. |
| 2 | secondary wearable | The other one. |
| 1 | apple health | |
| 0 | unattributed | Written before this shipped. |

An incoming reading wins when its rank is greater than or equal to the stored
value's rank, or when there is no stored value.

Greater than or equal, not greater than. Equal rank means the same source
syncing again, which must overwrite: that is what lets the afternoon sync
correct the morning's step count, and it is the entire job the
`healthIsTheSource` case does today.

The two case `precedence` enum collapses into this. A metric no wearable claims
leaves Apple Health as the highest ranked source present, which reproduces
`healthIsTheSource` exactly. A metric a wearable claims leaves Health at rank 1
below the strap, which reproduces `fillGapsOnly`.

### A correctness gain that falls out

`weightKg` is `fillGapsOnly` today, so a Health written weight can never be
corrected by a later Health reading. It sticks until something clears it. Under
ranks, Health may overwrite its own value while a typed weight stays protected
at rank 4. Strictly better, and not a goal of this work, just a consequence.

### The migration trap

Existing rows are rank 0, so the first sync after upgrade overwrites them. For
almost every metric that is correct and invisible: the same sources produce the
same numbers, now attributed.

But a weight or water figure the user typed before this ships is also
unattributed, and would be silently replaced by a Health reading. Legacy
backfill is therefore not uniform:

- For `weightKg` and `waterML`, unattributed is read as **manual**.
- Everywhere else, unattributed is rank 0.

One special case. Skipping it destroys real user data.

## New metrics

`HealthMetric` gains cases for what Fitbit exposes and the enum lacks:

- `activeZoneMinutes`, group `movement`
- `sleepEfficiencyPercentage`, group `sleep`
- `readinessScore`, group `heart`, present only for Premium accounts

Mappings worth naming, because they are judgement calls rather than renames:

- Fitbit *light* sleep maps to `coreSleepMinutes`. Apple's core and Fitbit's
  light are the same stage under two vendors' names.
- Fitbit `caloriesBMR` maps to `restingEnergyKcal`.
- Fitbit `floors` maps to `flightsClimbed`.
- Fitbit's `deepRmssd` is stored as an extra rather than mapped onto `hrvMs`,
  which holds `dailyRmssd`. They are different measurements and averaging them
  would be wrong.

## Errors

Mapped onto states the UI already knows how to show.

| Condition | Handling | On screen |
|---|---|---|
| HTTP 429 | Back off to `Fitbit-Rate-Limit-Reset`, return partial results with the cursor. Not a failure; the sync is unfinished. | "Catching up on history" |
| `invalid_grant` on refresh | Refresh token spent or revoked. Function marks the connection `needs_reauth`. | "Reconnect" |
| One collection 4xx | Record against that collection, keep the rest. Whoop's original bug was letting one refused endpoint kill a whole sync. | Silent |
| Empty range from a sensorless device | Absence is normal. Not an error. | Metric simply absent |
| Premium only endpoint refused | Same as one collection 4xx. | Silent |

## UI

A fourth card in `ConnectionsSettingsScreen`, same shape as the other three, on
the `.body` hue.

The primary wearable picker appears **only when both Whoop and Fitbit are
connected**. A picker with one option is noise on the screen of everyone who
owns one strap. When shown it sits directly beneath the two cards it
arbitrates, reading:

> Sleep, HRV, resting heart rate and blood oxygen come from ___

Naming the affected metrics is what makes a changed number explicable to
someone who flips the setting and then wonders why last night looks different.

Statuses reuse the existing vocabulary: "Not connected", "Connecting…",
"Synced N days", "Reconnect". Backfill in progress gets its own line, because a
sync paused for quota is not a failure and must not read as one.

## Testing

Tests first. The split follows what is already there: pure logic on device,
Deno tests for functions.

| Test | Covers |
|---|---|
| `MetricArbiterTests` | Rank table, equal rank overwrite, manual protection, and the legacy weight and water case. |
| `FitbitWireFormatTests` | Decoding a captured fixture per collection, plus the empty range a sensorless device returns. |
| `FitbitDerivationTests` | Payloads to `HealthMetric` values, including light to core sleep mapping. |
| `FitbitOAuthTests` | PKCE challenge, state mismatch rejection, custom scheme redirect parsing. Mirrors `WhoopTests`. |
| `FitbitBackfillTests` | Cursor and quota arithmetic without an API. |
| `fitbit_token_test.ts` | Rotation persisted under the row lock, `invalid_grant` to `needs_reauth`. |
| `fitbit_sync_test.ts` | 429 backoff, one collection failing without killing the sync. |
| `DailyMetricsSourcesTests` | The `sourcesData` migration, including the legacy special case. |

## Shipping order

Five slices, each independently shippable.

1. **Arbiter and provenance.** `sourcesData`, `MetricArbiter`, migration. No
   Fitbit at all: Whoop and Health become correctly attributed. Ships value on
   its own through the weight correction fix, and de-risks everything after it.
2. **Connection.** OAuth round trip, `fitbit_connections`, `fitbit-token`, the
   card. Connect and disconnect work. No data yet.
3. **Range collections.** `fitbit-sync` plus sleep, HRV, SpO2, breathing rate,
   skin temperature, resting heart rate, VO2 max. Around 7 requests for 30
   days. This is where Fitbit becomes a real Whoop substitute.
4. **Per date collections.** Activity summary, workouts, weight, nutrition, and
   the quota aware backfill cursor.
5. **Primary wearable.** The picker and live arbitration between two straps.

The implementation plan covers slices 1 to 3. Slices 4 and 5 depend on what the
first three teach us about Fitbit's real payloads, and planning them now would
be planning against guesses.

## Out of scope

- Intraday heart rate. Requires case by case approval from Fitbit for Server
  type applications.
- Fitbit Subscriptions, the webhook API. Worth revisiting once polling is
  working, as a way to cut quota use.
- Scheduled server side sync. Rejected against the cost ceiling: sync fires
  when the app opens, so there is no idle backend cost per user.
- Writing data back to Fitbit. The app reads only.
- Android and Health Connect.

## Cost

The Fitbit Web API is free. The added backend surface is two edge functions
invoked on app open and one small table, which stays inside the existing
ceiling of roughly two dollars per user per month.
