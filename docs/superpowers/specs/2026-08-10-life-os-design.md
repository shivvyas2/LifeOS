# Life OS — Design Spec

**Date:** 2026-08-10
**Status:** Approved for planning
**Scope of this document:** V1 (Foundation + Health). Later slices are sketched only to prove the architecture accommodates them.

---

## 1. What this is

A personal iOS app that pulls every signal from the devices Shiv already wears and carries — Apple Watch, iPhone, Whoop, Renpho scale — into one place, and eventually reasons over all of it to say what's working and what isn't.

Long-term the app is a life dashboard: health, nutrition, habits, goals, journal, notes, money, and content planning, with an AI coach that can see across all of them. That breadth is the point — a coach that sees only sleep gives generic advice; a coach that sees skipped meditation, an over-budget week, a "low focus" journal entry, and five hours of sleep can say something no single-purpose app can.

V1 builds the foundation and the health domain only.

### Audience

Personal use. One user, sideloaded on Shiv's own devices. No multi-user support, no App Store distribution, no subscription. This is a firm constraint that simplifies auth, privacy, and review considerations throughout.

---

## 2. Constraints and reality checks

These were established during brainstorming and shape the roadmap. They are recorded here so they are not rediscovered mid-implementation.

### Reachable without friction

- **Apple Watch + iPhone data** — HealthKit. Steps, workouts, sleep, heart rate, HRV, active energy, water. Full read access, native.
- **Renpho weight** — Renpho syncs to Apple Health. No Renpho API integration is needed or wanted; weight arrives through HealthKit like everything else.
- **Whoop** — official OAuth 2.0 API. Recovery, strain, HRV, sleep performance, workouts.

### Reachable only with deliberate work

- **Calories and food** — no automatic source exists. Something must log it. Decision: photo → AI estimate (Section 8), deferred to a later slice.
- **Water** — HealthKit `dietaryWater` exists but nothing writes it automatically. Requires manual logging.

### Blocked or heavily constrained

- **iPhone / iPad screen time** — Apple's DeviceActivity API is deliberately sealed. Usage figures can only be *rendered* inside a `DeviceActivityReport` extension. The host app cannot read those values into its own memory, cannot persist them, cannot send them to a server, and cannot feed them to the AI coach. A screen-time view is possible; screen-time *analysis alongside health data* is not. Also requires Apple's Family Controls distribution entitlement.
- **MacBook screen time** — no API exists at any privilege level. Manual entry only, if ever.

**Consequence:** "one app that sees everything" is true for health, fitness, nutrition, and every manually-tracked domain. It is false for screen time, and the design does not pretend otherwise. Screen time is dropped from the roadmap until a `DeviceActivityReport`-only view is judged worth the entitlement application.

### Whoop via HealthKit is not sufficient

Whoop writes sleep, workouts, and heart rate to Apple Health, but **not Recovery % or Day Strain** — those are proprietary and exist only through Whoop's API. Since those two numbers are the primary reason to wear a Whoop, the direct API integration is in V1 rather than deferred.

---

## 3. Roadmap

V1 is the only slice specified in detail. Each subsequent slice gets its own spec.

| Slice | Contents |
|---|---|
| **V1 (this spec)** | Design system, local data layer, Supabase sync, HealthKit ingestion, Whoop OAuth + ingestion, Today / Body / Activity / Recovery / Settings screens |
| **V2** | AI coach: daily brief + ask-anything chat, on-device via Foundation Models with tool calling |
| **V3** | Nutrition: photo → Claude vision → calories and macros, water logging |
| **V4** | Habits + streaks, Goals + progress bars |
| **V5** | Journal, Notes |
| **V6** | Money (manual entry: income, expenses, net worth, savings rate) |
| **V7** | Content planner calendar |

Slices V4–V7 are each a SwiftData model, a hue token, and a screen assembled from existing design-system components. They are deliberately cheap by construction — that is the return on building the design system and `DailyMetrics` properly in V1.

---

## 4. Platform and stack

- **Language:** Swift 6, strict concurrency. (The existing project is Swift 5.0 and must be migrated as the first task.)
- **UI:** SwiftUI.
- **Minimum OS:** iOS 26.0. This provides `FoundationModels` (`SystemLanguageModel`, `@Generable`, tool calling), which V2 depends on.
- **Local persistence:** SwiftData.
- **Backend:** Supabase (Postgres, Auth, Edge Functions).
- **Device target:** iPhone 16/17 series. Apple Intelligence confirmed available, so on-device inference is the default path in V2.

### iOS 27 adoption (deferred, not V1)

iOS 27 is at public beta as of this writing, with general release expected ~2026-09-14. It adds two things this app will want:

- Public `LanguageModel` / `LanguageModelExecutor` protocols, letting third-party providers (Anthropic is a launch partner) sit behind the same `LanguageModelSession` API as the on-device model.
- `PrivateCloudComputeLanguageModel` — Apple's cloud model with a 32K context window, still privacy-preserving and key-free.

**Design implication for V1:** none directly, but V2's insight layer must be written against `LanguageModelSession` so that swapping tiers later is a configuration change, not a rewrite. Do not hand-roll a provider abstraction; Apple ships one.

### Naming note

The Xcode project is named `LIfeOS` (capital I) with bundle ID `shivvyas.LIfeOS`. Renaming is optional and cosmetic. If done, do it as the first commit before any code exists; otherwise leave it and never revisit it.

---

## 5. Architecture

### Module boundaries

A local Swift package `LifeOSKit` provides compile-time separation. The app target contains only views and app-level wiring.

| Target | Responsibility | May depend on |
|---|---|---|
| `DesignSystem` | Gradients, dot grid, cards, numerals, tokens | nothing |
| `Persistence` | SwiftData models and queries | nothing |
| `HealthData` | All HealthKit reading | `Persistence` |
| `WhoopKit` | Whoop OAuth + API client | `Persistence` |
| `SyncKit` | Supabase client, push/pull, conflict resolution | `Persistence` |
| `Insights` (V2) | AI coach | `Persistence` |

**Rules:**
- Nothing outside `HealthData` imports `HealthKit`.
- Nothing outside `WhoopKit` knows Whoop exists.
- Nothing outside `SyncKit` imports the Supabase SDK.
- `Insights` reads `Persistence` only — it never calls HealthKit or Whoop directly.

The payoff is that the Whoop client can be rewritten without touching a view, and each module fits in a single context window when being worked on.

### Data topology: local-first

**SwiftData on-device is the source of truth for the UI.** Every screen reads local. The app is fully functional offline — in a gym basement, on a plane, with no signal.

Supabase serves three purposes:
1. **Backup** — the phone is not the only copy.
2. **Sync** — future iPad and Mac clients read the same data.
3. **Server-side jobs** — nightly Whoop pull, Whoop webhooks, and the Whoop token exchange, none of which can happen on a sleeping phone.

Sync is background and non-blocking. A failed sync never blocks a read or a write.

### The spine: `DailyMetrics`

**One row per calendar day** is the join key for the entire app.

```
DailyMetrics
  date (unique, day-granularity)   — primary key
  weightKg
  steps
  activeEnergyKcal
  exerciseMinutes
  sleepMinutes
  waterML
  restingHR
  hrvMs
  whoopRecoveryPct
  whoopDayStrain
  whoopSleepPerformancePct
  updatedAt
  syncedAt
```

HealthKit and Whoop are both **writers** into this row. The UI and (in V2) the coach are **readers** of it.

This single decision buys:
- Trends become a sort, not a multi-source async join.
- The AI coach queries one table rather than orchestrating two network APIs mid-conversation.
- Offline works by default, because nothing renders from a live network call.
- Adding a source later (a new wearable) means writing into the same row, not a new pipeline.

Records that are genuinely not daily — individual workouts, individual sleep sessions — get their own models (`WorkoutRecord`, `SleepRecord`) and roll *up* into `DailyMetrics`. `DailyMetrics` is derived state and is always safe to recompute from source records.

A single `UserGoals` record holds the daily targets (steps, sleep, exercise minutes, water) that define whether a day counts as on-target in the dot grid. See Section 10.

### Conflict resolution

Last-write-wins per field, using `updatedAt`. Justified because there is exactly one human user and writes originate from distinct sources that rarely contest the same field: HealthKit writes health fields, the Whoop job writes Whoop fields, the user writes manual fields. Field-level rather than row-level LWW prevents the nightly Whoop job from clobbering a manual entry made the same day.

---

## 6. HealthKit integration

### Types read

| Metric | HKQuantityTypeIdentifier / other |
|---|---|
| Weight | `bodyMass` |
| Steps | `stepCount` |
| Active energy | `activeEnergyBurned` |
| Exercise minutes | `appleExerciseTime` |
| Resting HR | `restingHeartRate` |
| HRV | `heartRateVariabilitySDNN` |
| Water | `dietaryWater` |
| Sleep | `HKCategoryTypeIdentifier.sleepAnalysis` |
| Workouts | `HKWorkoutType` |

Read-only. The app requests no write permissions in V1.

### Freshness

- `HKAnchoredObjectQuery` with a persisted anchor per type, so each sync fetches only what changed.
- `enableBackgroundDelivery` so iOS wakes the app when new samples land.
- `HKStatisticsCollectionQuery` for daily aggregates (steps, energy) rather than summing raw samples client-side.

### Authorization

HealthKit authorization status for *read* access is deliberately opaque — the API will not tell you whether the user denied a type, only whether you asked. Therefore: never branch on read authorization status. Query, and treat an empty result as "no data," rendering an explicit empty state rather than a zero. **A zero and a missing value must never look the same on screen** — this is a health app, and a false zero is worse than a blank.

### Privacy note

Apple prohibits storing HealthKit data in iCloud, and restricts sharing it with third parties. Syncing to the user's own Supabase project with explicit consent is permitted. As a personal, non-distributed app this is not a review concern, but the constraint is recorded in case distribution is ever reconsidered.

---

## 7. Whoop integration

### API

- Base URL: `https://api.prod.whoop.com`
- API version: **v2**. v1 is deprecated. Note that v2 identifies sleep by UUID rather than integer ID, and recovery webhooks reference the associated *sleep* UUID, not the cycle ID.
- Auth: OAuth 2.0 authorization code, Bearer token.
- Scopes: `offline`, `read:cycles`, `read:sleep`, `read:recovery`, `read:workout`, `read:body_measurement`, `read:profile`. The `offline` scope is required to obtain a refresh token.

### Endpoints used

| Data | Endpoint |
|---|---|
| Physiological cycles (day strain) | cycle collection |
| Recovery (score, HRV, RHR) | recovery collection |
| Sleep (performance, duration, stages) | sleep collection |
| Workouts | workout collection |

All are paginated and sorted by start time descending.

### OAuth flow — secret stays server-side

Whoop's token exchange requires a client secret. Shipping that secret inside the app binary would make it extractable with `strings`. It therefore never touches the device:

1. App generates a PKCE verifier and challenge.
2. App opens `ASWebAuthenticationSession` against Whoop's authorize URL.
3. Whoop redirects to `lifeos://whoop/callback` with an authorization **code**.
4. App POSTs `{ code, code_verifier }` to the `whoop-token-exchange` Edge Function.
5. Edge Function exchanges the code using `WHOOP_CLIENT_SECRET` from its own environment and returns `{ access_token, refresh_token, expires_in }`.
6. App stores both tokens in **Keychain**.

Refresh follows the same shape through the Edge Function. If a refresh fails with an auth error, the app clears Keychain and surfaces a "reconnect Whoop" state in Settings rather than retrying silently.

### Nightly job and webhooks

- A scheduled Edge Function (pg_cron) pulls the previous day's cycle, recovery, and sleep into Postgres overnight. Morning data is present before the app is opened.
- A `whoop-webhook` Edge Function receives push updates. Signature verified against `WHOOP_WEBHOOK_SECRET`; unverified requests are rejected. This is possible only because a public HTTPS endpoint now exists.

---

## 8. Supabase

### Schema

Mirrors the local SwiftData models: `daily_metrics`, `workout_records`, `sleep_records`, `whoop_raw` (unprocessed API payloads, retained so re-derivation never requires re-fetching), and `sync_state`.

### Row Level Security

**RLS enabled on every table, without exception.** Policies scope all access to `auth.uid()`. This is what makes shipping the anon key in the app safe.

### Auth

Supabase Auth with a single account. Session persisted in Keychain.

### Edge Functions

| Function | Purpose | Secrets used |
|---|---|---|
| `whoop-token-exchange` | Exchange auth code / refresh token | `WHOOP_CLIENT_SECRET` |
| `whoop-sync` | Scheduled nightly pull | `WHOOP_CLIENT_SECRET`, `SERVICE_ROLE_KEY` |
| `whoop-webhook` | Receive Whoop push events | `WHOOP_WEBHOOK_SECRET`, `SERVICE_ROLE_KEY` |
| `analyze-meal` (V3) | Food photo → macros via Claude vision | `ANTHROPIC_API_KEY` |

---

## 9. Secrets management

There is no runtime `.env` on iOS. The app is a signed bundle; anything shipped inside it is extractable. The governing rule is therefore **what must never leak, must live server-side.**

### Tier 1 — build-time config, gitignored

`Config/Secrets.xcconfig`, injected into Info.plist and read at runtime via `Bundle`:

```
SUPABASE_URL      = https://xxxx.supabase.co
SUPABASE_ANON_KEY = eyJhbGci...
WHOOP_CLIENT_ID   = ...
```

None of these are true secrets. The Supabase anon key is *designed* to ship in clients — it is safe precisely because RLS gates every row. The Whoop client ID is public by OAuth design.

- `Config/Secrets.xcconfig` → `.gitignore`
- `Config/Secrets.example.xcconfig` → committed, with placeholder values, as the template

### Tier 2 — Keychain, runtime only

Never in git, never in the binary: Whoop access token, Whoop refresh token, Supabase session.

### Tier 3 — Edge Function environment, never on device

Set via `supabase secrets set`: `WHOOP_CLIENT_SECRET`, `WHOOP_WEBHOOK_SECRET`, `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

**`service_role` bypasses RLS entirely.** It belongs only in Edge Function environments — never in xcconfig, never in the app target, never in git. This is the single most damaging secret in the system.

---

## 10. Design system

### Principle

The hub is neutral; the domains are colored. This resolves the two visual languages in the reference material into one hierarchy rather than a collision.

### Tokens

- **Hues.** Each module owns one: Body teal, Activity amber, Recovery blue, Nutrition purple (V3), Money green (V6), Habits orange (V4).
- **Accent.** Orange, fixed, never varies by module. It means exactly two things: *today*, and *act*. Used for the current day, the FAB, the selected tab, and alert states. Everything else is the module hue or neutral.
- **Canvas.** Warm off-white for the neutral hub.

### Components

- **`GradientCanvas(hue:)`** — one primitive rendering saturated-at-top → near-white-at-bottom. Adding a module later is a hue token, not a new screen design.
- **Card, two treatments by zone** — frosted `.ultraThinMaterial` while over the saturated region, solid white with a soft shadow once the background has gone pale. This is what makes cards legible against both ends of a gradient.
- **`DotGrid`** — the shared vocabulary of the whole app. Filled = target met, hollow = missed, orange = today, gray = future, faint outline = no data. It is the month view on Today, the streak display on Habits (V4), and "days on target" inside any domain screen. One component, reused everywhere; this is what will make ten modules read as one app.

  **"Target met" is defined explicitly**, because the dot grid is the app's central claim and a vague rule makes it meaningless. A day counts as on-target when it meets a configurable threshold count — default **3 of 4**:
  1. Steps ≥ goal (default 8,000)
  2. Sleep ≥ goal (default 7h)
  3. Exercise minutes ≥ goal (default 30)
  4. Water ≥ goal (default 2,500 ml)

  Goals live in a `UserGoals` model, editable in Settings. A day with no data is **not** a miss — it renders as no-data and is excluded from streak arithmetic entirely.
- **`HeroNumeral`** — ~96pt, semibold, tight tracking, always paired with a small quiet label beneath. **Never render a numeral without its unit.**
- **`WeekStrip`** — pinned top, seven days, today filled orange.
- **Tab bar** — circular icons, plus a floating dark FAB for logging.

  **In V1 the FAB logs water and weight only** — the two metrics with no automatic source. Both write to local `DailyMetrics`; the app requests no HealthKit write permissions in V1. The FAB's menu grows in later slices (meals in V3, habits in V4). Without this, V1 has a FAB with nothing to log and a `waterML` field nothing ever fills.

### Dark mode

Every hue has a dark variant: deep saturated top → near-black bottom, with card materials inverted. Defined as tokens in V1. Retrofitting a gradient system to dark mode later is significantly harder than doing it once at the start.

---

## 11. V1 screens

| Screen | Treatment | Hero |
|---|---|---|
| **Today** | Neutral off-white canvas | Oversized date, week strip, month `DotGrid` of days on target, current streak, and four tiles — steps, sleep, weight, recovery — each showing today's value against its goal |
| **Body** | Teal gradient | Weight numeral, weekly bar chart, trend delta |
| **Activity** | Amber gradient | Steps numeral, tiles: distance, active time, calories |
| **Recovery** | Blue gradient | Whoop Recovery % numeral, tiles: HRV, resting HR, day strain, sleep performance |
| **Settings** | Neutral | Connection status for Health / Whoop / Supabase, permissions, last-sync times, reconnect actions |

Today is deliberately the "am I on track" screen — answerable from the dot grid before reading a single number.

---

## 12. Error handling

- **No signal** — every screen renders from local SwiftData. Sync failure is surfaced only in Settings as a last-synced timestamp, never as a blocking error.
- **Missing data vs zero** — an absent metric renders as an explicit empty state, never as `0`. Non-negotiable in a health app.
- **Whoop auth expiry** — clear Keychain, surface a reconnect state in Settings. No silent retry loops.
- **Whoop rate limits** — respect `Retry-After`; exponential backoff in the nightly job.
- **HealthKit denial** — cannot be detected for read types. Empty results render as empty states; Settings links to the Health app's permission screen.
- **Sync conflict** — field-level last-write-wins, no user-facing prompt.

---

## 13. Testing

- **`Persistence`** — `DailyMetrics` upsert semantics, field-level merge, and rollup derivation from `WorkoutRecord` / `SleepRecord`. Pure logic, fully unit-testable.
- **`HealthData`** — protocol-wrap the HealthKit store so aggregation and anchor handling are tested against fixtures. HealthKit itself is not testable in the simulator with real data.
- **`WhoopKit`** — API response decoding against recorded v2 payload fixtures; token refresh state machine including the expiry path.
- **`SyncKit`** — conflict resolution, tested with constructed clock skew and competing writes.
- **`DesignSystem`** — SwiftUI previews for every component in light and dark, at each hue.
- **Manual** — HealthKit background delivery and the full Whoop OAuth round trip require a physical device.

---

## 14. Risks

| Risk | Mitigation |
|---|---|
| Whoop v2 payloads differ from documentation | Persist raw payloads in `whoop_raw` from day one; re-derive without re-fetching |
| HealthKit background delivery is unreliable in practice | Also sync on foreground; never depend solely on background wake |
| Sync conflict logic grows subtle | Keep field-level LWW; resist adding merge strategies without a real observed conflict |
| Scope creep from the V4–V7 modules | Each slice gets its own spec. V1 ships with five screens or it is not V1 |
| iOS 27 slips or changes the provider protocol | V1 does not depend on it; V2 targets `SystemLanguageModel` on iOS 26 and treats the rest as upside |

---

## 15. Decisions on record

| Decision | Choice | Reason |
|---|---|---|
| Audience | Personal only | Removes accounts, review, and multi-user architecture |
| Weight source | HealthKit, via Renpho's Health sync | No Renpho API integration needed |
| Whoop | Direct API in V1 | Recovery % and Strain exist nowhere else |
| Whoop client secret | Edge Function only | Would otherwise be extractable from the binary |
| Food logging | Photo → AI estimate | Lowest friction; deferred to V3 |
| AI coach | On-device Foundation Models, tool calling | Free, private, offline; Claude API only where vision is required |
| Data topology | Local-first, Supabase syncs | A health app that waits on the network is one you stop opening |
| Screen time | Dropped | Apple's API forbids reading the values into the app |
| V1 scope | Foundation + health, five screens | De-risks the hard integrations before breadth |
