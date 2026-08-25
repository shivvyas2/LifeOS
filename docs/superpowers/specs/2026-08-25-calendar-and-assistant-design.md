# Calendar + AI Assistant Design Spec

**Date:** 2026-08-25
**Status:** Approved in brainstorming; reconciled against the coach LLM routing spec; awaiting spec review
**Scope of this document:** Project 4 of the August 2026 roadmap. Adds a calendar layer to LifeOS, and a conversational assistant over it built as the first consumer of tool calling in the existing `Insights` coach stack.

---

## 1. What this is

LifeOS gains two coupled capabilities, ported in spirit (not in code) from the user's existing React Native app `shivvyas2/Calander-Assistant`, also known as DayGuide:

1. **A calendar layer.** Events from Apple EventKit and, later, the Google Calendar API, merged and deduped into a local SwiftData cache, surfaced as an agenda card on Today.
2. **An AI assistant.** A chat sheet that answers questions about the schedule and creates, moves, and deletes events, by calling tools rather than describing what the user should do.

The interaction being reproduced is DayGuide's: the user says "move my 6am workout to 8" and the model calls a function. The architecture is not DayGuide's. DayGuide is TypeScript on React Native with a dedicated Gemini proxy; LifeOS is Swift on SwiftUI, and it already has an inference layer.

### 1.1 Relationship to the coach

`2026-08-25-coach-llm-routing-design.md` specifies `Insights`: a `CoachTask` contract, an `Engine` protocol with on-device and remote implementations, a `CoachRouter` with an escalation policy, a thin Edge Function proxy that owns the key and the role-to-model map, and a $2 per user per month allowance enforced by reserve-then-settle against a database check constraint.

**This spec adds no second inference layer.** The assistant is a consumer of `Insights`. Specifically:

- It uses `CoachRouter`, not its own client.
- It calls `supabase/functions/coach/index.ts`, not a second proxy.
- It names a `Tier.Role`, never a model ID.
- It spends from the same $2 allowance, through the same reserve-and-settle path.

The coach spec defers tool calling, noting that `Tool.parameters` is a `GenerationSchema` and `GenerationSchema` is `Codable`, so the schema-sharing trick that lets one `@Generable` type serve both tiers extends to tools. This spec is the first feature to need that, and Section 8 builds it. The coach adopts it later at no additional cost.

### 1.2 What carries over from DayGuide

| DayGuide element | Carried over? | Note |
|---|---|---|
| Tool-calling loop with a round cap | Yes | Cap lowered from 10 to 6 |
| Server-side proxy holding the key | Yes, the coach's | Not a second one |
| Two calendar sources merged with dedup | Yes | Dedup rule `title + startDate` kept verbatim |
| Sync window of 30 days back, 90 days forward | Yes | |
| Tools conditionally offered by connection state | Yes | |
| Gmail tools (`draft_email`, `send_email`) | No | Out of scope, see Section 17 |
| Confirmation requested via system prompt text | No | Replaced by a structural gate, see Section 10 |
| Events mirrored to Supabase with realtime | No | Local only, see Section 5 |
| Chat history in Supabase | No | Local only |
| A cloud model on every turn | No | Floors on-device, see Section 9 |

---

## 2. Roadmap context

The August 2026 roadmap is Project 1 (Health restructure + app-wide restyle), Project 0.5 (Cloud Run API backbone), Project 2 (Nutrition + AI meal logging), Project 3 (Wake-triggered morning check-in). This project is **Project 4**, and it **starts now, in parallel with Project 1**. The work is ordered so nothing in the first two phases touches a file Project 1 rewrites. See Section 15.

Two couplings:

- **The coach must land first, or at least its `Insights` skeleton.** Phase B depends on `CoachTask`, `Engine`, `CoachRouter`, and the `coach` Edge Function existing. Tasks 1, 3, 4 and 6 of `2026-08-25-coach-on-device-foundation.md` are the hard prerequisite. Phase A has no such dependency and can proceed immediately.
- **Project 0.5 (Cloud Run).** The coach's proxy is a Supabase Edge Function today, while Project 0.5 states that Cloud Run replaces Edge Functions as the home for server logic. That tension is the coach spec's to resolve, not this one's. This spec follows the coach: whatever hosts `coach`, hosts the assistant's requests too. There is nothing here to migrate separately.

---

## 3. Decisions on record

| Decision | Choice | Rejected alternatives |
|---|---|---|
| Assistant scope | Calendar only | Calendar + read-only LifeOS context; full LifeOS agent |
| Calendar source | Both EventKit and Google API, merged, staged | EventKit only; Google API only |
| Inference layer | Reuse `Insights` and the coach proxy | A dedicated `assistant-chat` function on Anthropic direct |
| Tier floor | On-device, escalating through `CoachRouter` | Cloud floor on `.reasoning`; on-device reads with cloud writes |
| Event storage | SwiftData cache, no Supabase mirror | Read-through with no cache; SwiftData plus Supabase mirror |
| Write safety | Create freely, confirm edits and deletes | Confirm every write; write freely with undo |
| Sequencing | Start now, parallel with Project 1 | After Project 1; after Project 3 |

**Consequence of "calendar only":** the assistant's tools reach `CalendarStore` and the calendar write path. They do not reach `DailyMetrics`, `PlanEntry`, `HabitTick`, `MoneyEntry`, or any Whoop record. It cannot read recovery to reason about workout timing. This is deliberate, and it is a different boundary from the coach's, which sees `MetricsDigest` and no calendar.

---

## 4. Module layout

No calendar target. `Calendar` would shadow `Foundation.Calendar` at every use site, and the pieces divide cleanly along the existing seams anyway.

**`LifeOSKit/Sources/Persistence/`**

- `CalendarEvent.swift`: the `@Model` plus `CalendarEventSnapshot`, following the `PlanEntry` / `PlanItemSnapshot` split.
- `CalendarStore.swift`: windowed queries, upsert, dedup, free-slot computation.
- `ChatMessage.swift`: conversation persistence.

**`LifeOSKit/Sources/Integrations/`**

- `CalendarSource.swift`, `EventKitSource.swift`, `GoogleCalendarSource.swift` (Phase D), `CalendarMerge.swift`, `CalendarSync.swift`.

**`LifeOSKit/Sources/Insights/`**, additions to the coach's target rather than a new one

- `CoachTool.swift`: the tool contract (Section 8).
- `ToolLoop.swift`: the provider-neutral round loop (Section 9).
- `Engines/Engine.swift`: gains a tool-calling entry point alongside the existing single-shot `run`.

These are general capabilities, not calendar ones. `Insights` keeps its rule of depending on `Persistence` only and stays free of calendar knowledge.

**New target `Assistant`**, depending on `Insights` and `Persistence`

- `CalendarTools.swift`: the six `CoachTool` conformances.
- `CalendarWriting.swift`: the write protocol the app satisfies with `CalendarSync`.
- `AssistantTask.swift`: the `CoachTask` describing the conversation, its instructions and its tier floor.

`Assistant` exists because its tools must reach the calendar write path, which lives in `Integrations`, and `Insights` may not depend on `Integrations`. Injecting `CalendarWriting` keeps the dependency graph acyclic and lets tests drive the tools with a fake.

```swift
.library(name: "Assistant", targets: ["Assistant"]),
.target(name: "Assistant", dependencies: ["Insights", "Persistence"]),
.testTarget(name: "AssistantTests", dependencies: ["Assistant"]),
```

**App target**

- `LIfeOS/Features/Today/View/AgendaCard.swift`, `EventSheet.swift`
- `LIfeOS/Features/Assistant/{ViewModel,Model,View}/`

**Server**

- `supabase/functions/coach/index.ts` gains a tool-calling request shape. No new function.

**Config**

- `Config/App-Info.plist` gains `NSCalendarsFullAccessUsageDescription`.

---

## 5. Data model

```swift
public enum CalendarEventSource: String, Codable, Sendable, CaseIterable {
    case eventKit, google
}

@Model
public final class CalendarEvent {
    public var id: UUID
    /// Stored raw so the enum can gain cases without a migration, matching PlanEntry.
    public var sourceRaw: String
    /// EKEvent.eventIdentifier, or the Google event id. Unique within a source.
    public var sourceID: String
    public var calendarTitle: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    /// True when this row is one occurrence of a recurring series. Gated
    /// writes are refused against these; see Section 17.
    public var isRecurring: Bool
    public var location: String?
    public var notes: String?
    public var lastSyncedAt: Date
}

@Model
public final class ChatMessage {
    public var id: UUID
    public var conversationID: UUID
    public var roleRaw: String        // "user" | "assistant"
    public var text: String
    /// Rendered as activity chips. Empty for plain replies.
    public var toolSummaries: [String]
    public var createdAt: Date
}
```

`CalendarEventSnapshot` is the detached `Equatable, Identifiable, Sendable` value type handed to views and to tools. Nothing above `CalendarStore` holds a `CalendarEvent`, for the reason `TodaySnapshot` exists: a view holding a SwiftData object can fault it mid-layout.

`Sendable` matters more here than it does for `PlanItemSnapshot`. Tool results cross into an engine, and the coach spec relies on exactly this to make its privacy boundary a compile-time check rather than a review-time one. A `CalendarEvent` cannot cross that line because it is not `Sendable`; a snapshot can.

`LifeOSContainer.schema` gains `CalendarEvent.self` and `ChatMessage.self`. The natural key is `(sourceRaw, sourceID)`; `id` is local and never leaves the device.

**No Supabase mirror.** Calendar contents and chat history stay on device. What does leave, on an escalated turn only, is described in Section 14.

---

## 6. Sources, sync, and merge

### 6.1 The protocol

```swift
public protocol CalendarSource: Sendable {
    var source: CalendarEventSource { get }
    var isAuthorized: Bool { get async }
    func requestAccess() async throws -> Bool
    func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot]
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func delete(sourceID: String) async throws
}
```

Phase D adds `GoogleCalendarSource` behind this and changes nothing else.

### 6.2 Sync

`CalendarSync` is an actor holding an ordered array of sources. A pass:

1. Window is 30 days back to 90 days forward from `startOfDay(for: .now)`, matching DayGuide.
2. Fetch from every authorized source. A source that throws is logged and skipped; the others still populate. Partial data beats an empty screen.
3. Merge, see 6.3.
4. Upsert into `CalendarStore` by natural key; delete cached rows in-window whose natural key is absent from the fetch, so deletions made in another app propagate.
5. Save. `ModelContext.didSave` fires and `RootView` reloads every view model through the path it already has.

Triggers: `scenePhase == .active`, and after any write. This matches how Whoop sync was wired in `d5f9ca9`. No polling, no timer.

### 6.3 Merge

DayGuide's rule, kept verbatim: two events collide when `title.lowercased()` is equal and `startDate` is equal. On collision **EventKit wins**, because that copy is writable offline and is what the OS shows the user elsewhere.

`CalendarMerge` is a pure function over two arrays with no I/O, and is the single unit test target for this behaviour.

**Why the merge matters more than it looks.** If the user's Google account is added under iOS Settings, EventKit already returns those events, so in the common configuration Phase D's Google source is fully redundant and the dedup rule is the only thing preventing every event from appearing twice. The Google source earns its keep only for accounts not added to iOS, which is why it is last and optional.

### 6.4 Writes

`CalendarStore` never writes to a provider. Writes route through `CalendarSync.write(...)`, which dispatches to the source owning the event by its `source` field, then re-syncs the affected window so the cache reflects what the provider actually stored. Providers normalise all-day handling and timezones, so trusting the local draft after a write would drift.

`CalendarSync` conforms to `Assistant.CalendarWriting`. That protocol is the only calendar mutation surface the tools can reach.

---

## 7. Inference: what this spec does not build

For the avoidance of a second stack, stated explicitly.

| Concern | Owner | This spec |
|---|---|---|
| Provider API key | `coach` Edge Function env | never sees it |
| Model selection | `COACH_MODEL_REASONING` / `_VISION` | names a `Role` |
| Price lookup and fail-closed behaviour | coach function, OpenRouter catalog | inherits |
| Spend ceiling and reserve/settle | `coach` function plus the DB check constraint | inherits |
| On-device availability checks | `CoachRouter` | inherits |
| Escalation policy | `CoachRouter` escalation table | inherits |
| Refusal handling | `CoachRouter`, surfaced never escalated | inherits |

The earlier revision of this document specified a separate `assistant-chat` function on the Anthropic API with a hardcoded model ID and its own `assistant_usage` table capped at 100 messages a month. All of that is deleted. It duplicated the proxy, introduced a second key and provider, put a model ID in a place where changing it needs a deploy, and created a second budget that could not jointly honour a $2 ceiling.

### 7.1 The one server change

`supabase/functions/coach/index.ts` gains a second request shape. Everything else about it, including auth, the role map, price lookup, and reserve/settle, is unchanged and applies to both shapes.

```
POST /coach

  single-shot (existing)
    { role, instructions, prompt, schema, maxTokens, image? }
    -> { content }

  tool-calling (new)
    { role, instructions, messages[], tools[], maxTokens }
    -> { content?, toolCalls: [{ id, name, arguments }] }

  errors (unchanged)
    { error: "budget_exceeded" }        402
    { error: "server_not_configured" }  500
```

`messages[]` and `tools[]` are provider-neutral on the wire. The function translates to whatever the configured model expects, which today is OpenAI-style `tool_calls` through OpenRouter. **No Anthropic-specific block types appear anywhere in Swift or in this document's contract.** That was a defect of the earlier revision: it wrote `tool_use` / `tool_result` / `is_error` into the client, which would have pinned the app to one provider and defeated the env-var model swap.

---

## 8. Tools

### 8.1 The contract

```swift
public protocol CoachTool: Sendable {
    var name: String { get }
    var description: String { get }
    /// Codable, so the same declaration serves both tiers.
    var parameters: GenerationSchema { get }
    /// True for tools the loop must not execute without confirmation.
    var requiresConfirmation: Bool { get }
    func call(_ arguments: GeneratedContent) async throws -> String
}
```

One declaration, two bindings, mirroring the output-schema trick the coach already uses:

| | On-device | Cloud |
|---|---|---|
| Declare | adapt to `LanguageModelSession.Tool` | `JSONEncoder().encode(parameters)` into `tools[]` |
| Invoke | Foundation Models calls `call` | `toolCalls[]` dispatched to `call` |
| Return | tool output | appended to `messages[]` |

`CoachTool` lives in `Insights` because it is general. The coach's deferred "tool calling over `Persistence`" adopts it unchanged.

### 8.2 The six calendar tools

Defined in `Assistant/CalendarTools.swift`. Four never leave the device even on an escalated turn, because they read the local cache.

| Tool | Reads/writes | Confirmed |
|---|---|---|
| `get_events(start, end)` | `CalendarStore` | no |
| `find_free_time(start, end, duration_minutes)` | `CalendarStore` | no |
| `analyze_schedule(start, end)` | `CalendarStore` | no |
| `create_event(title, start, end, is_all_day, location, notes)` | `CalendarWriting` | no |
| `update_event(id, ...)` | `CalendarWriting` | **yes** |
| `delete_event(id)` | `CalendarWriting` | **yes** |

`find_free_time` computed from the cache is why DayGuide's `get_free_busy`, which called Google's `freeBusy` endpoint, is unnecessary. It also works offline.

Tool availability follows DayGuide: with no authorized calendar source, no calendar tools are offered and the instructions say so, so the model explains what to connect rather than calling something that would fail.

`id` is the local `CalendarEvent.id` as a UUID string, never a provider id. The model only sees ids `get_events` handed it, and `CalendarStore` rejects unknown ones.

`update_event` and `delete_event` fail with an explaining message when the target has `isRecurring == true`, so the model tells the user to edit the series in their calendar app. See Section 17.

---

## 9. The loop and the tier floor

### 9.1 Floor

`AssistantTask` declares `floor: .onDevice`. Most turns are a lookup and at most one write, well within the on-device model's reach, and reads then work with no network. Escalation is `CoachRouter`'s existing table, unchanged: `.exceededContextWindowSize`, `.assetsUnavailable`, `.rateLimited` and `.unsupportedLanguageOrLocale` escalate; `.decodingFailure` retries once then escalates; `.concurrentRequests` retries locally; `.unsupportedGuide` fails loudly; `.refusal` and `.guardrailViolation` surface and never escalate.

An escalated turn runs on `.reasoning`, whichever model that currently maps to.

**The risk this accepts:** a roughly 3B model driving writes is less reliable at argument construction than a frontier model. Three things bound it. Edits and deletes cannot execute without confirmation (Section 10). Ids are validated against the store, so a hallucinated id fails rather than hitting the wrong event. `.decodingFailure` escalates after one retry, which is precisely the failure mode a small model exhibits when it loses a schema.

If measurement shows on-device tool calling is not good enough, the fix is a one-line floor change to `.cloud(.reasoning)`, not a redesign. This is recorded as a risk in Section 18 rather than assumed away.

### 9.2 The loop

`ToolLoop` in `Insights` runs at most **6 rounds** per user message, down from DayGuide's 10. With events cached locally most turns resolve in one. Exhausting the cap returns a plain message saying the request could not be completed, not a silent stop.

One round:

1. Ask the engine for the next step, given instructions, conversation, and tools.
2. If the engine returns content and no tool calls, append it and finish.
3. Otherwise execute each returned tool call, or hold it if it requires confirmation (Section 10).
4. When every call in the round has a result, append them all and loop.

A failing tool returns its error as the result rather than being dropped, so the model can recover or explain.

The loop is written against `Engine`, not against a provider, so it runs identically on-device and escalated.

### 9.3 Budget interaction

Only escalated rounds cost anything. Each escalated round is a separate reserve-and-settle against the coach's allowance, exactly like any other remote call, so a runaway loop cannot outrun the ceiling: the round that does not fit is refused with `budget_exceeded`.

`ToolLoop` treats `budget_exceeded` as terminal for the turn, not as a tool error. The conversation ends with the coach's existing exhaustion sentence. Retrying inside the loop would spend the reservation attempt repeatedly for no possible progress.

---

## 10. The confirmation gate

The gate is structural. `update_event` and `delete_event` set `requiresConfirmation`, and `ToolLoop` is not wired to execute a tool with that flag.

When such a call arrives, the loop returns `.awaitingConfirmation(PendingWrite)` and suspends. `PendingWrite` carries the call plus the current `CalendarEventSnapshot` read from the store, so the card shows the before state beside the proposed after state.

- **Confirm.** Execute, append the result, resume.
- **Cancel.** Append a result reading "User declined this change", resume so the model can acknowledge it.

The model cannot route around this, because nothing it emits causes a gated write to execute. This is the substantive improvement over DayGuide, which asked Gemini in the system prompt to confirm first and therefore depended on the model choosing to. It matters more here than it did there, because the floor is a small on-device model.

**Batch interaction.** One round may return several calls, some gated. Ungated ones execute immediately, gated ones queue, and the round does not complete until every call has a result. Several gated calls are confirmed one at a time in arrival order.

Creates are not gated, per the brainstorming decision. A created event is announced in the reply with an undo affordance on the message.

---

## 11. Instructions and context

`AssistantTask.instructions` carries the behavioural rules: resolve relative dates against the stated current time, never invent an event id, state times in the user's timezone, keep replies to a sentence or two, ask before assuming a duration.

The prompt carries current date, time, IANA timezone, which calendar sources are authorized, and today's and tomorrow's events inline. Inlining two days means "what's on today?" is answered with no tool call at all, which matters twice over: it is the cheapest possible path, and it is the most reliable one on a small model.

Conversation history is capped at the last **20 messages**, down from DayGuide's 50. The cap is enforced in `ToolLoop`, so it holds on both tiers.

There is no `MetricsDigest` here. The assistant's context is calendar, and the coach's is metrics; neither task sees the other's.

---

## 12. Cost model

Almost every turn runs on-device and costs **nothing**.

An escalated turn, at the current demo-tier model `google/gemini-2.5-flash-lite` at $0.10 per million input and $0.40 per million output:

| Component | Tokens |
|---|---|
| Tool declarations | ~1,000 |
| Instructions plus inlined events | ~600 |
| History, capped at 20 messages | ~2,000 |
| Input per round | ~3,600 |
| Input per escalated turn, two rounds | ~7,200 |
| Output per turn | ~300 |

That is **$0.00072 input plus $0.00012 output, about $0.0008 per escalated turn**. At 100 assistant messages a month with a generous 20% escalation rate, the assistant costs roughly **$0.02 per user per month**, against a $2.00 allowance the coach spec projects at ~$0.04 on the same tier.

Two consequences worth stating:

1. **No separate cap is needed.** The earlier revision proposed a 100-message monthly limit because it priced every turn against a frontier model on a second budget. On-device floor plus demo-tier escalation makes the assistant a rounding error, and the coach's existing ceiling is the only control required.
2. **The number moves with the role map, and that is fine.** If `.reasoning` is upgraded to Claude Sonnet 5 at $3.00/$15.00, an escalated turn costs about $0.026 and 20 escalated turns about $0.52 a month. Still inside $2, alongside the coach's ~$0.87 at frontier tier, but no longer negligible. The reserve-and-settle ceiling makes this safe without anyone recomputing this table, which is the point of the coach's design.

These figures are modelled, not measured. The escalation rate is the sensitive input and is the first thing to check against real data.

---

## 13. UI

### 13.1 Today

`TodaySnapshot` gains `agenda: [CalendarEventSnapshot]` and `calendarAccess: CalendarAccessState`. `TodayViewModel.load()` gains one `CalendarStore` read for today's window. No other view model changes.

`AgendaCard` sits between the streak line and the stat tile grid:

- Header "TODAY" with an event count.
- Up to four rows of time, title, and duration. Beyond four, "+N more" opens the day.
- "+ Add event" opens `EventSheet` in create mode; a row tap opens it in view/edit mode.
- With access not granted, the body is an empty state with a request button. **The EventKit prompt is triggered from here, never at launch.**
- With access granted and no events, the card says so rather than disappearing, so the affordance stays discoverable.

Styling follows Project 1. The card is built in Phase C, after the restyle, so it is styled once.

### 13.2 The assistant sheet

A sparkle button joins the gear in Today's toolbar and presents `AssistantSheet` full-screen.

- Message list with user and assistant bubbles.
- A compact activity chip per executed tool ("Checked your calendar", "Found 3 free slots"), so tool use is visible rather than implied.
- Confirmation cards for gated writes, inline in the conversation, with Confirm and Cancel.
- Composer with a send button, disabled while a turn is in flight.
- History loads from the most recent conversation on open.

There is no remaining-messages indicator. The allowance is internal per the coach spec, and surfaces only as its one exhaustion sentence.

`AssistantViewModel` owns the loop and publishes an `AssistantSnapshot`. The sheet stays a pure function of that snapshot, consistent with every other screen.

---

## 14. Permissions and privacy

- EventKit full access is requested from the agenda card's empty state, with `NSCalendarsFullAccessUsageDescription` explaining that LifeOS shows the day's schedule and lets the assistant change it.
- Denied access is a first-class state: the card explains it, links to Settings, and calendar tools are withheld.
- Calendar events and chat history are stored only on the device.
- **On an on-device turn, nothing leaves the device at all.** This is a genuine improvement over the earlier revision, where every turn went to a cloud provider.
- **On an escalated turn, calendar content does leave.** The inlined two days and any `get_events` results travel to OpenRouter and the configured model. This is a weaker guarantee than the coach's aggregates-only `MetricsDigest` boundary, because an event title is content, not a derived number, and it cannot be aggregated without destroying its usefulness. It must be stated in the app's privacy copy and surfaced once before first use of the assistant.
- No calendar data reaches Supabase. The function forwards the request and stores only budget accounting.

---

## 15. Phasing

**Phase A: calendar core.** `CalendarEvent`, `CalendarStore`, `CalendarSource`, `EventKitSource`, `CalendarMerge`, `CalendarSync`, schema registration, tests. Touches no view file and does not depend on the coach. Safe to start immediately, in parallel with both Project 1 and the coach.

**Phase B: assistant.** Requires the `Insights` skeleton from the coach plan. `CoachTool`, `ToolLoop`, the `Engine` tool-calling entry point, the `coach` function's second request shape, the `Assistant` target, `AssistantSheet`, tests. Delivers the interaction the user asked for, and does not depend on Phase C.

**Phase C: agenda card.** After Project 1 merges: `AgendaCard`, `EventSheet`, and the `TodaySnapshot` and `TodayViewModel` changes. Built once, in the new visual language.

**Phase D: Google Calendar source.** Optional and last. `GoogleCalendarSource` behind `CalendarSource`, plus the Supabase Google OAuth provider, a token store and refresh, modelled on `WhoopOAuth`. Deferrable indefinitely for any user whose Google account is in iOS Settings.

Phase B before Phase C is deliberate: the assistant works against the Phase A store and needs no agenda card to be useful.

---

## 16. Testing

**`PersistenceTests`**

- Upsert matches on `(source, sourceID)` and does not duplicate across syncs.
- In-window rows absent from a fetch are deleted; out-of-window rows are untouched.
- Window queries respect day boundaries and all-day events.
- Free-slot computation over a day of known events, including empty and fully booked.

**`IntegrationsTests`**

- `CalendarMerge` dedupes on case-insensitive title plus equal start, EventKit winning.
- A source that throws does not prevent the other source's events from merging.

**`InsightsTests`** (extending the coach's suite)

- `ToolLoop` stops at 6 rounds and returns the exhaustion message.
- A `requiresConfirmation` tool suspends the loop and executes nothing.
- Confirm resumes with a result; cancel resumes with the declined result.
- Every call in a multi-call round is resolved before the round completes.
- A throwing tool yields an error result rather than a dropped one.
- History truncates to 20 messages.
- `budget_exceeded` ends the turn and is not retried.
- A `CoachTool`'s `parameters` round-trips through `JSONEncoder` and back, pinning the schema-sharing assumption the same way the coach's output-schema pin test does.

**`AssistantTests`**, against a fake `CalendarSource` and a fake `CalendarWriting`

- Each of the six tools maps arguments to the right store or write call.
- An unknown event id is rejected rather than dispatched.
- A recurring event is refused by `update_event` and `delete_event` with an explaining message.

All of it runs under `swift test` with no simulator and no network, which is why `EventKitSource` sits behind a protocol, writes behind `CalendarWriting`, and the loop behind `Engine`.

---

## 17. Out of scope

- **Gmail.** DayGuide's `draft_email` and `send_email` are not ported.
- **LifeOS data in the assistant.** No metrics, habit, plan, money, or Whoop access. That is the coach's boundary, not this one's.
- **Calendar data in the coach.** The reverse also holds until someone specs it.
- **Event mirroring to Supabase**, and any web view of the calendar.
- **Voice input.** DayGuide used `expo-speech-recognition`; not carried over.
- **Streaming.** Deferred by the coach spec; the assistant inherits that and shows a thinking indicator.
- **Notifications and reminders** for events. Project 3 owns the notification pipeline; revisit after it lands.
- **Attendees and invitations.** Events are read and written as the user's own.
- **Recurring event editing.** Occurrences are read and cached as expanded rows carrying `isRecurring`. Editing "this occurrence" versus "the series" is not modelled, and gated writes refuse such rows with an error the model explains. Full recurrence handling is a follow-up.

---

## 18. Risks

| Risk | Mitigation |
|---|---|
| On-device model is unreliable at constructing tool arguments | Confirmation gate on destructive writes; ids validated against the store; `.decodingFailure` escalates after one retry. If measurement disproves the floor, it is a one-line change to `.cloud(.reasoning)`. |
| Escalation rate far exceeds the assumed 20% | Escalation reason is already recorded per request by the coach. If `.exceededContextWindowSize` dominates, shrink the inlined context before raising anything. |
| Extending the `coach` contract destabilises the coach | The additions are a second request shape and a new response field. The single-shot path is untouched, and the coach's existing tests pin it. |
| Duplicate events once Phase D lands | `CalendarMerge` is pure with direct unit tests, and Phase D is optional. |
| Model targets the wrong event | Ids come only from `get_events`; unknown ids rejected; gated writes show the resolved current event before executing. |
| Recurring events surprise the user | Refused explicitly rather than silently mangling a series. |
| Phase C collides with Project 1 | Phase C is scheduled after Project 1 merges; Phases A and B touch no restyled file. |
| Calendar content leaves the device on escalation | Stated in Section 14, disclosed once before first use. Cannot be aggregated away the way `MetricsDigest` is. |
| Phase B blocked on the coach landing | Phase A is independent and carries the calendar layer to completion regardless. |
