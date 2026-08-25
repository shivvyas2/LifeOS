# Coach LLM Routing Design Spec

**Date:** 2026-08-25
**Status:** Approved for planning
**Scope of this document:** The V2 `Insights` module — the AI coach's inference layer. Covers how a request chooses between the on-device Foundation Model and a cloud model reached through OpenRouter, and how spending is capped. Does not cover coach UI, conversation history, or tool calling over `Persistence` beyond the read boundary described in Section 6.

---

## 1. What this is

The coach needs a language model. Two are available, and they are good at different things.

Apple's on-device model is free, private, offline, and always warm. It is also small: a context window measured in low thousands of tokens, and reasoning that degrades sharply on multi-step analysis. A cloud model is the inverse — capable and expensive, requiring network and a key that must never ship in the binary.

This document specifies a layer that uses the on-device model for everything it can handle and escalates to cloud only where the on-device model genuinely cannot serve, with a spend ceiling that cannot be breached.

The target: **under $1.00/month per user in typical use, and structurally incapable of exceeding a $2.00 monthly allowance.**

---

## 2. Correction to the V1 spec

`2026-08-10-life-os-design.md:85` states:

> V2's insight layer must be written against `LanguageModelSession` so that swapping tiers later is a configuration change, not a rewrite. Do not hand-roll a provider abstraction; Apple ships one.

**This is not achievable on iOS 26.** Verified against the iOS 26.2 SDK
(`FoundationModels.framework/.../arm64e-apple-ios.swiftinterface`):

- `SystemLanguageModel` is a `final class`, not a protocol.
- There is no public `LanguageModel` or `LanguageModelExecutor` protocol.
- `LanguageModelSession` exposes no seam for a non-Apple backend.

Those protocols arrive in iOS 27. Until then a thin abstraction of our own is **required, not optional**. The design goal is therefore not to avoid an abstraction but to keep it small enough that adopting Apple's — when it ships — deletes our remote engine rather than rewriting our callers.

The V1 spec's underlying intent survives intact: `@Generable` types, `GenerationSchema`, and `LanguageModelSession` remain the vocabulary. Only the claim that Apple already ships the seam is wrong.

---

## 3. Decisions on record

| Decision | Choice | Rationale |
|---|---|---|
| Scenarios in scope | Daily brief, ask-anything chat, weekly/trend review, meal photo → macros | All four; they exercise every tier |
| Routing policy | Declared tier floor + escalate on failure | Deterministic and cheap; escalation catches the unpredicted cases |
| Data leaving the device | Aggregates only, never raw records | Privacy and cost improve together |
| Proxy scope | Thin — app owns prompts, Edge Function owns key, model map, and budget | Prompts stay beside on-device prompts; model swaps ship without App Store review |
| Shared contract | One `@Generable` type per task, serving both tiers | `GenerationSchema` is `Codable` and `GeneratedContent` has `init(json:)`, so this is possible without a second type system |
| Spend ceiling | $2.00 per user per calendar month, plus a global ceiling, enforced by a database check constraint | A hard invariant, not a soft guard. Internal — never surfaced to the user except on exhaustion. |
| Streaming | Deferred past V2.0 | Three of four tasks don't want it; it doubles the engine surface |

---

## 4. Module architecture

A new `Insights` target in `LifeOSKit`, depending on `Persistence` only. This follows the V1 rule at `2026-08-10-life-os-design.md:112` — `Insights` reads `Persistence` and never calls HealthKit or Whoop directly.

**Nothing outside `Insights` imports `FoundationModels`.**

```
LifeOSKit/Sources/Insights/
  CoachTask.swift          Contract: the protocol every task conforms to
  Tasks/
    DailyBrief.swift       @Generable output, instructions, tier floor
    WeeklyReview.swift
    CoachAnswer.swift      Ask-anything
    MealEstimate.swift     Vision; cloud floor
  Engines/
    Engine.swift           The two-method protocol both engines satisfy
    OnDeviceEngine.swift   LanguageModelSession wrapper
    RemoteEngine.swift     Calls the coach Edge Function
  CoachRouter.swift        Tier selection and escalation
  Context/
    MetricsDigest.swift    Persistence -> aggregates; the privacy boundary
  SchemaJSON.swift         GenerationSchema -> JSON Schema
```

`Package.swift` gains:

```swift
.library(name: "Insights", targets: ["Insights"]),
.target(name: "Insights", dependencies: ["Persistence"]),
.testTarget(name: "InsightsTests", dependencies: ["Insights"]),
```

---

## 5. The shared contract

### Why one type can serve both tiers

Two facts from the iOS 26.2 interface make this work:

- `GenerationSchema` conforms to `Codable`. A task's output schema can be encoded to JSON and sent to OpenRouter as a structured-output schema.
- `GeneratedContent` has `init(json: String) throws`, and `Generable` requires `init(_ content: GeneratedContent) throws`. A JSON reply from any provider can be decoded back into the same `@Generable` type.

So the round trip is symmetric:

| | On-device | Cloud |
|---|---|---|
| Schema out | implicit in `respond(to:generating:)` | `JSONEncoder().encode(T.generationSchema)` |
| Call | `session.respond(to:generating: T.self)` | POST to the Edge Function |
| Decode in | `response.content` | `try T(GeneratedContent(json: body))` |

One `@Generable` declaration. One schema. One decode path.

### The protocol

```swift
public protocol CoachTask: Sendable {
    associatedtype Output: Generable
    var floor: Tier { get }
    var instructions: String { get }
    func prompt(_ digest: MetricsDigest) -> String
}

public enum Tier: Sendable {
    case onDevice
    case cloud(Role)
    public enum Role: String, Sendable, Codable {
        case reasoning, vision
    }
}

protocol Engine: Sendable {
    func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output
}
```

`Role` is deliberately abstract. The app never names a model. The Edge Function maps role to model, so changing `.reasoning` from Sonnet to Opus is a function deploy, not an App Store release.

### Tier floors

| Task | Floor | Why |
|---|---|---|
| `DailyBrief` | `.onDevice` | Structured input, short structured output, once a day |
| `CoachAnswer` | `.onDevice` | Most turns are simple lookups; hard ones escalate |
| `WeeklyReview` | `.cloud(.reasoning)` | 7 days of context and genuine multi-step reasoning |
| `MealEstimate` | `.cloud(.vision)` | Foundation Models is text-only |

### The one exception

`MealEstimate` does not fit the protocol cleanly. Vision needs image bytes, which are neither in `MetricsDigest` nor `Generable` input. It carries a separate `attachment: Data` and the remote engine forwards it as a base64 image block.

This is a deliberate wart. Bending `CoachTask` to accommodate one caller would make the other three worse.

---

## 6. `MetricsDigest` — the privacy boundary

The aggregates-only rule is enforced by a type, not by convention.

```swift
public struct MetricsDigest: Sendable {
    public struct Day: Sendable {
        let date: Date
        let recoveryPct: Int?
        let sleepMinutes: Int?
        let strain: Double?
        let steps: Int?
        let exerciseMinutes: Int?
    }
    let days: [Day]
    let averages: Averages
    let goals: GoalSummary
}
```

Built from `MetricsStore.metrics(from:to:)`, it carries derived numbers only. It never carries:

- Raw Whoop payloads (`WhoopRawRecord`)
- HRV or heart-rate series
- User identifiers, tokens, or account data
- `DailyMetrics` instances themselves

`DailyMetrics` is a SwiftData `@Model` class and is not `Sendable`. `Engine.run` takes `MetricsDigest`. The compiler therefore prevents a raw model object from crossing into an engine — the privacy rule is checked at build time rather than at review time.

This is also the largest token lever in the system: a digest is roughly 200 tokens per day where raw rows are thousands.

---

## 7. Routing and escalation

### Algorithm

```
1. If task.floor is .cloud            -> remote.
2. If on-device model unavailable     -> remote.
3. Try on-device.
4. On error, consult the table below  -> escalate, retry, or surface.
```

Step 2 uses `SystemLanguageModel.default.availability`:

| `UnavailableReason` | Handling |
|---|---|
| `.deviceNotEligible` | Permanent. Resolve once at launch and cache. |
| `.appleIntelligenceNotEnabled` | User-fixable. Cache, invalidate on foreground. |
| `.modelNotReady` | Transient (downloading). Re-check per request. |

### Escalation table

Derived from the real `LanguageModelSession.GenerationError` cases.

| Case | Action | Rationale |
|---|---|---|
| `.exceededContextWindowSize` | **Escalate** | The expected trigger. Cloud has room. |
| `.assetsUnavailable` | **Escalate** | Weights absent from disk. |
| `.rateLimited` | **Escalate** | System-level throttle; waiting does not help. |
| `.unsupportedLanguageOrLocale` | **Escalate** | Permanent for that user. |
| `.decodingFailure` | Retry once, then escalate | Small model lost the schema; a larger one usually holds it. |
| `.concurrentRequests` | **Retry locally** | This is our bug — the router must serialize. Escalating bills money for a race condition. |
| `.unsupportedGuide` | **Fail loudly** | A `@Guide` the model cannot honor is a static property of our schema. Escalating hides a bug we would never find. |
| `.refusal` | **Surface, never escalate** | See below. |
| `.guardrailViolation` | **Surface, never escalate** | See below. |

### Why refusals must not escalate

Re-routing a refused request to a different provider to obtain the answer anyway is guardrail laundering. In a health application the refusals will cluster around disordered eating, self-harm, and extreme restriction — precisely the contexts where quietly routing around a safety decision is most harmful.

A refusal is shown to the user as a refusal. `GenerationError.Refusal` carries an `explanation` we can surface.

---

## 8. The Edge Function

`supabase/functions/coach/index.ts`, following the established `whoop-token` pattern: secrets read from the function environment, never logged, never returned, never in this repository.

### Contract

```
POST /coach
  { role, instructions, prompt, schema, maxTokens, image? }
->
  { content }                          200
  { error: "budget_exceeded" }         402
  { error: "server_not_configured" }   500
```

### Responsibilities

1. Authenticate the caller (Supabase JWT) and resolve `user_id`.
2. Map `role` -> concrete OpenRouter model.
3. Compute worst-case cost and **reserve** it (Section 9). Refuse if it does not fit.
4. Call OpenRouter with `OPENROUTER_API_KEY`, `response_format` from `schema`, and `usage: { include: true }`.
5. **Settle** the reservation against actual reported cost.
6. Return content only. Never the key, never the model name, never raw provider errors.

### Role map

Lives in the function beside the price table, because the two always change together.

| Role | Initial model | Notes |
|---|---|---|
| `reasoning` | Claude Sonnet 5 | $3.00/$15.00 per 1M input/output at first-party rates ($2.00/$10.00 introductory through 2026-08-31). Escalate to Claude Opus 5 ($5.00/$25.00) if weekly-review quality disappoints. |
| `vision` | Claude Haiku 4.5 | $1.00/$5.00 per 1M — a third of Sonnet 5's rate. Reading macros off a meal photo is perception, not reasoning; it does not need a frontier model. Image dimensions capped client-side (Section 9). Confirm image support via the Models API `capabilities` field before wiring it. |

Only two roles exist because only two are used. A cheap classification role is easy to add when something needs it, and pointless before then.

OpenRouter applies its own margin on top of first-party rates; the price table in the function must reflect OpenRouter's quoted prices, not the numbers above.

### Secrets

`OPENROUTER_API_KEY` is Tier 3 per `2026-08-10-life-os-design.md:289` — set with `supabase secrets set`, never in xcconfig, never in the app target, never in git.

---

## 9. The $2/month allowance

Each user gets **$2.00 of cloud inference per calendar month**. The requirement is that spending *cannot* exceed it, not that it usually does not.

The allowance is **internal**. It exists to bound what the app costs to run, not to be a feature. Users are never shown a balance, a meter, a percentage, or a dollar figure. The only time the allowance becomes visible is when it runs out, and then it is one sentence.

### Why check-then-call is insufficient

```
read spend -> if under cap -> call -> add cost
```

Two concurrent requests both read $1.98 and both proceed. The ceiling is breached by design. Any scheme that reads and writes in separate statements has this gap.

### The invariant is enforced by the schema

Rather than relying on every call site writing its guard correctly, exceeding the allowance is made **representationally impossible**:

```sql
create table coach_budget (
  user_id         uuid not null,
  period_start    date not null,               -- first day of the calendar month, UTC
  ceiling_micros  bigint not null default 2000000,   -- $2.00
  spent_micros    bigint not null default 0,
  reserved_micros bigint not null default 0,
  primary key (user_id, period_start),
  constraint within_allowance
    check (spent_micros + reserved_micros <= ceiling_micros)
);

create table coach_reservation (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null,
  period_start  date not null,
  amount_micros bigint not null,
  created_at    timestamptz not null default now(),
  foreign key (user_id, period_start) references coach_budget(user_id, period_start)
);
```

Any statement that would push a row over its ceiling raises a check violation. The Edge Function catches that and returns `budget_exceeded`. A bug in the reservation SQL cannot silently overspend — it can only fail loudly.

`ceiling_micros` is a column rather than a literal so the allowance can be raised for a single user, or globally, without a schema change.

### Monthly periods need no reset job

The period is part of the primary key. A new calendar month means a new row, created lazily on first use with `spent_micros = 0`. There is no cron job to reset balances and therefore no cron job to fail silently and strand every user at zero.

Reservation is one atomic upsert:

```sql
insert into coach_budget (user_id, period_start, reserved_micros)
values ($uid, date_trunc('month', now() at time zone 'utc')::date, $reserve)
on conflict (user_id, period_start) do update
   set reserved_micros = coach_budget.reserved_micros + $reserve
returning user_id;
```

No `where` guard is needed on the update: the check constraint is the guard, on both the insert path and the update path. Concurrent callers serialize on the row.

### Reserve, then settle

Every request pre-authorizes its **worst case** before a token is generated, and trues up afterward. Because the reserved amount is the maximum the call could cost, the ceiling holds even if every in-flight request simultaneously returns its longest permitted answer.

### What makes the worst case computable

- **`max_tokens` is mandatory on every request.** It bounds the output side. Without it the worst case is unbounded and the entire scheme is theatre. The Edge Function rejects a request that omits it.
- **Micro-dollars as `bigint`, never floats.** $2.00 is `2_000_000`. Float accumulation drifts, and drift in the wrong direction defeats the cap.
- **Images are resized client-side** to a fixed maximum dimension before upload, so `.vision` requests carry a predictable token ceiling rather than an unknown one. The worst-case estimate uses a conservative constant for image tokens.

Worst case = `(estimated_input_tokens x input_price) + (max_tokens x output_price)`, rounded up.

`estimated_input_tokens` is computed from the serialized request body the function is about to send, as `ceil(bytes / 3)` — deliberately more pessimistic than the usual ~4 bytes/token rule, plus a fixed constant for an attached image. The estimator may over-predict freely; settlement returns the difference. It must never under-predict, which is what the estimator test in Section 12 asserts.

### Settlement

OpenRouter returns actual usage when the request sets `usage: { include: true }`. Settlement replaces the reservation with the real figure in one transaction:

```sql
update coach_budget
   set reserved_micros = reserved_micros - $reserved,
       spent_micros    = spent_micros + $actual
 where user_id = $uid and period_start = $period;
delete from coach_reservation where id = $rid;
```

Typical settlement releases 60-80% of the reservation.

### Leaked reservations

If the function dies between reserving and settling, that money is locked forever and the user hits the ceiling having spent a fraction of it. Two mitigations, both required:

1. Settle in a `finally` block — covers the normal error path.
2. A sweeper releases any `coach_reservation` older than the request timeout — covers isolate termination, where `finally` does not run.

### The table must be client-unwritable

```sql
alter table coach_budget enable row level security;
create policy read_own on coach_budget for select using (auth.uid() = user_id);
-- no insert/update/delete policy: only service_role writes.
```

If the app can write this table, the cap is decoration.

### Global ceiling

A per-user allowance does not protect the account. Ten accounts is $20/month.

`coach_budget` carries a sentinel row (`user_id = '00000000-0000-0000-0000-000000000000'`) with its own, larger `ceiling_micros`. Reservation upserts both the user row and the sentinel row **inside one transaction**: if either violates its check constraint, the transaction rolls back and the request is refused. Settlement decrements both in one transaction, so the two can never drift.

The V1 spec establishes this as a single-user sideloaded app, so this is a backstop against unexpected account creation rather than a scaling concern — but Supabase permits signups by default, and it is a few lines.

### Defense in depth

Everything above is our code, and our code can be wrong. Therefore **also set a hard spend limit on the OpenRouter key itself** via their provisioning-key limits.

That ceiling does not depend on our reservation logic being correct. Three independent limits — the check constraint, the global sentinel row, and the provider key — of which only the first two are our code. This is the guarantee; the SQL is what keeps us from ever hitting it and turning a graceful degrade into a hard provider failure.

### What the user sees

Nothing, until the allowance is gone. Then:

> **You're out of limit.**

No balance, no countdown, no "you have used 80%." When the allowance is exhausted, cloud tiers become unavailable and the coach keeps working on-device; tasks with a cloud floor show that one line, once, as a state rather than an error dialog per request.

The `degraded` state (Section 11) must **not** mention the allowance. "This ran on-device" and "you are out of budget" are different sentences, and only the second one is ever shown.

---

## 10. Cost model

| Task | Tier | Volume | Cost |
|---|---|---|---|
| Daily brief | on-device | 30/mo | $0 |
| Chat, on-device turns | on-device | majority | $0 |
| Chat, escalated | `.reasoning` (Sonnet 5) | ~30/mo | ~$0.60 |
| Weekly review | `.reasoning` (Sonnet 5) | 4/mo | ~$0.07 |
| Meal photo | `.vision` (Haiku 4.5) | ~60/mo | ~$0.20 |
| | | **Total** | **~$0.87/mo** |

Figures are first-party Anthropic rates; OpenRouter adds a margin.

### Headroom

Against a $2.00 allowance that leaves roughly 55% spare, which is the right amount: enough that a heavy month does not hit the wall, tight enough that a runaway bug does.

This margin was not free. Routing `.vision` to Sonnet 5 alongside `.reasoning` — the obvious choice, one model for everything — put the projection at ~$1.30/mo, only 35% under the allowance, and a user who logs meals diligently would have hit the limit most months. Splitting vision onto Haiku 4.5 costs one extra line in the role map and buys back that margin.

**The two levers to reach for if real usage overruns, in order:**

1. **Escalated chat is the largest and least predictable line.** It is driven by how often the on-device model fails, which is a measured quantity, not a guess — the escalation reason is recorded per request (Section 14). If `.exceededContextWindowSize` dominates, shrink `MetricsDigest` before raising the allowance.
2. **Meal photos scale linearly with diligence.** A user logging every meal costs triple the projection. Cap the resized image dimension harder before changing models.

Three structural choices produce the baseline, in order of impact:

1. **The daily brief never goes to cloud, and is generated once per day rather than once per app-open.** Cached in SwiftData keyed by date. Without this, cost scales with how often Today is opened — the single largest avoidable expense in the system.
2. **`MetricsDigest` rather than rows** — roughly an order of magnitude fewer tokens.
3. **Chat attempts on-device first**, so most turns cost nothing.

---

## 11. Error handling

Results reach the UI as three states rather than thrown errors:

| State | Meaning | UI |
|---|---|---|
| `answered` | Succeeded at or above the requested tier | Normal render |
| `degraded` | On-device answered where cloud was wanted | Render, with a quiet note — never mentioning the allowance |
| `refused` | Apple's guardrail declined | Show the refusal explanation; no retry button |
| `exhausted` | Allowance spent, and the task has a cloud floor | "You're out of limit." Once, as a state. |

`degraded` and `exhausted` are deliberately separate states even though the allowance can cause both. A weekly review that silently ran on-device reads as the coach inexplicably getting worse, so it says something — but it says "this ran on-device," never "you are out of budget." The allowance surfaces in exactly one string, in one state.

`refused` is split out from `exhausted` because they need opposite affordances: a refusal must not offer a retry, an exhausted allowance resolves itself next month.

---

## 12. Testing

| Test | What it protects |
|---|---|
| **Schema pin** — encode `DailyBrief.generationSchema`, assert JSON shape | The one assumption this design rests on. If Apple's encoding is not JSON-Schema-compatible, this fails on day one rather than after the remote path is built. Fallback is a `GenerationSchema` -> JSON Schema adapter, roughly 50 lines, still one source type. |
| **Budget concurrency** — N concurrent reservations against a $2 row | The cap is a correctness claim and needs a test that could falsify it. Asserts total reserved never exceeds the ceiling and that the right number are refused. Should be impossible to fail given the check constraint — which is the point: the test proves the constraint is actually in the migration. |
| **Reservation leak** — reserve, kill before settle, run sweeper | The failure mode that silently destroys the budget. |
| **Escalation table** — inject each `GenerationError` case | Especially that `.refusal` does not escalate. |
| **Digest boundary** — assert no raw Whoop field reaches an engine | The privacy rule. |
| **Month rollover** — reserve in month N, assert month N+1 starts at zero without a reset job | The lazy-row scheme is what removes the cron job; this proves it works. |
| **Worst-case estimator** — assert estimate >= actual across recorded fixtures | If the estimate can under-predict, the cap can be breached. |

Engines are protocol-mocked. No test calls OpenRouter or Apple's model.

---

## 13. Deferred

| Item | Why |
|---|---|
| Streaming | Both tiers support it, but three of four tasks do not want it, and it doubles the `Engine` surface. Chat gets a thinking indicator in V2.0. An escalated chat turn is a multi-second wait, so this should land soon after. |
| Tool calling over `Persistence` | `Tool.parameters` is a `GenerationSchema`, so the same schema-sharing trick extends to tools. Not needed while `MetricsDigest` covers the context. |
| iOS 27 `LanguageModelExecutor` | When available, `RemoteEngine` conforms to Apple's protocol and `CoachRouter` collapses. Callers do not change — that is the point of keeping the abstraction thin. |
| Private Cloud Compute tier | A third tier between on-device and OpenRouter: key-free and privacy-preserving. Slots in as another `Engine` when iOS 27 ships. |

---

## 14. Risks

| Risk | Mitigation |
|---|---|
| `GenerationSchema` JSON is not OpenRouter-compatible | Schema pin test fails immediately; adapter fallback is scoped and small |
| Worst-case estimator under-predicts, breaching the cap | Estimator test over fixtures; OpenRouter key limit as the independent backstop |
| On-device model escalates far more often than expected, raising cost | Escalation reason is recorded per request; if `.exceededContextWindowSize` dominates, shrink the digest before raising the budget |
| On-device quality is poor enough that users always want cloud | Measured, not assumed. If the daily brief is not good enough on-device, that is a finding to act on, not a reason to pre-emptively route everything to cloud |
| Aggregates still identify the user in combination | Digest carries no identifiers; OpenRouter sees a bearer token and numbers |
