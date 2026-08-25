# Calendar + AI Assistant Design Spec

**Date:** 2026-08-25
**Status:** Approved in brainstorming; awaiting spec review
**Scope of this document:** Project 4 of the August 2026 roadmap. Adds a calendar layer to LifeOS and a conversational assistant that reads and writes it.

---

## 1. What this is

LifeOS gains two coupled capabilities, ported in spirit (not in code) from the user's existing React Native app `shivvyas2/Calander-Assistant`, also known as DayGuide:

1. **A calendar layer.** Events from Apple EventKit and, later, the Google Calendar API, merged and deduped into a local SwiftData cache, surfaced as an agenda card on Today.
2. **An AI assistant.** A chat sheet driven by Claude Haiku 4.5 with function calling, able to answer questions about the schedule and to create, move, and delete events on the user's behalf.

The interaction being reproduced is DayGuide's: the user says "move my 6am workout to 8" and the model calls a tool rather than describing what the user should do. The architecture is reproduced, not the source. DayGuide is TypeScript on React Native; LifeOS is Swift on SwiftUI, so every line is new.

### 1.1 What carries over from DayGuide

| DayGuide element | Carried over? | Note |
|---|---|---|
| Function-calling loop with a round cap | Yes | Cap lowered from 10 to 6 |
| Server-side proxy holding the AI key | Yes | Gemini becomes Claude; JWT verification added |
| Two calendar sources merged with dedup | Yes | Dedup rule `title + startDate` kept verbatim |
| Sync window of 30 days back, 90 days forward | Yes | |
| Tools conditionally offered by connection state | Yes | |
| Gmail tools (`draft_email`, `send_email`) | No | Out of scope, see Section 17 |
| Confirmation requested via system prompt text | No | Replaced by a structural gate, see Section 10 |
| Events mirrored to Supabase with realtime | No | Local only, see Section 5 |
| Chat history in Supabase | No | Local only |

---

## 2. Roadmap context

The August 2026 roadmap, from the health restructure spec, is Project 1 (Health restructure + app-wide restyle), Project 0.5 (Cloud Run API backbone), Project 2 (Nutrition + AI meal logging), Project 3 (Wake-triggered morning check-in). This project is **Project 4**, and it **starts now, in parallel with Project 1**.

Parallelism is safe because the work is ordered so that nothing in the first two phases touches a file Project 1 rewrites. See Section 15.

Two roadmap couplings to hold in mind:

- **Project 0.5 (Cloud Run).** The assistant ships on a Supabase Edge Function because that path already works in this repo (`whoop-token`, `whoop-callback`). When the Cloud Run backbone lands, the function moves there. It is small enough that this is a port, not a rewrite.
- **Project 2 (Nutrition).** Project 2 already chose Claude for meal analysis. Using Claude here keeps LifeOS on one AI provider and one billing account.

---

## 3. Decisions taken in brainstorming

Recorded so the implementation plan does not relitigate them.

| Decision | Choice | Rejected alternatives |
|---|---|---|
| Assistant scope | Calendar only | Calendar + read-only LifeOS context; full LifeOS agent |
| Calendar source | Both EventKit and Google API, merged, staged | EventKit only; Google API only |
| AI backend | Supabase Edge Function now, Claude Haiku 4.5 | Gemini 3 Flash; blocking on Cloud Run |
| Event storage | SwiftData cache, no Supabase mirror | Read-through with no cache; SwiftData plus Supabase mirror |
| Write safety | Create freely, confirm edits and deletes | Confirm every write; write freely with undo |
| Sequencing | Start now, parallel with Project 1 | After Project 1; after Project 3 |

**Consequence of "calendar only":** the assistant is given no access to `DailyMetrics`, `PlanEntry`, `HabitTick`, `MoneyEntry`, or any Whoop record. It cannot read recovery to reason about workout timing. This is deliberate and is the smallest surface that delivers the interaction the user wants.

---

## 4. Module layout

No new calendar target. `Calendar` is unusable as a target name because it would shadow `Foundation.Calendar` at every use site, and the calendar pieces divide cleanly along the existing Persistence/Integrations seam anyway.

**`LifeOSKit/Sources/Persistence/`**

- `CalendarEvent.swift`: the `@Model` plus `CalendarEventSnapshot`, following the `PlanEntry` / `PlanItemSnapshot` split exactly.
- `CalendarStore.swift`: windowed queries, upsert, dedup, free-slot computation.

**`LifeOSKit/Sources/Integrations/`**

- `CalendarSource.swift`: the protocol both sources implement.
- `EventKitSource.swift`: `EKEventStore` reads and writes.
- `GoogleCalendarSource.swift`: Phase D only.
- `CalendarMerge.swift`: pure dedup, no I/O, fully unit testable.
- `CalendarSync.swift`: the actor that drives a sync pass.

**New target `Assistant`**, depending on `Persistence`

- `AssistantClient.swift`: one request to the edge function, one response.
- `ToolCatalog.swift`: tool definitions and the local executor.
- `ToolLoop.swift`: the round loop and the confirmation gate.
- `ChatMessage.swift`: the `@Model` plus its snapshot type.

A separate target rather than a folder inside `Integrations` so the loop can be tested against a stubbed transport without dragging in `WhoopClient`, and so `swift test` continues to run with no simulator and no network.

`Package.swift` gains:

```swift
.library(name: "Assistant", targets: ["Assistant"]),
...
.target(name: "Assistant", dependencies: ["Persistence"]),
.testTarget(name: "AssistantTests", dependencies: ["Assistant"]),
```

**App target**

- `LIfeOS/Features/Today/View/AgendaCard.swift`
- `LIfeOS/Features/Today/View/EventSheet.swift`
- `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift`
- `LIfeOS/Features/Assistant/Model/AssistantSnapshot.swift`
- `LIfeOS/Features/Assistant/View/AssistantSheet.swift`

**Server**

- `supabase/functions/assistant-chat/index.ts`

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
```

`CalendarEventSnapshot` is the detached `Equatable, Identifiable` value type handed to views and to the tool layer. Nothing above `CalendarStore` ever holds a `CalendarEvent`, for the same reason `TodaySnapshot` exists: a view that holds a SwiftData object can fault it mid-layout.

`LifeOSContainer.schema` gains `CalendarEvent.self` and `ChatMessage.self`.

```swift
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

**Persistence identity.** The natural key is `(sourceRaw, sourceID)`. `id` is a local UUID and is never sent anywhere. Upsert matches on the natural key.

**No Supabase mirror.** Calendar contents and chat history stay on the device. The assistant does send the relevant slice of the calendar to Anthropic as prompt context, which is stated plainly in Section 14.

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

Phase D adds `GoogleCalendarSource` behind this protocol and changes nothing else.

### 6.2 Sync

`CalendarSync` is an actor holding an ordered array of sources. A pass:

1. Window is 30 days back to 90 days forward from `startOfDay(for: .now)`, matching DayGuide.
2. Fetch from every authorized source. A source that throws is logged and skipped; the others still populate. Partial data beats an empty screen.
3. Merge, see 6.3.
4. Upsert into `CalendarStore` by natural key; delete cached rows in-window whose natural key is absent from the fetch, so deletions made in another app propagate.
5. Save. `ModelContext.didSave` fires and `RootView` reloads every view model through the path it already has.

Triggers: `scenePhase == .active`, and after any write the assistant or the UI performs. No polling and no timer.

### 6.3 Merge

DayGuide's rule, kept verbatim: two events collide when `title.lowercased()` is equal and `startDate` is equal. On collision **EventKit wins**, because that copy is writable offline and is what the OS shows the user elsewhere.

`CalendarMerge` is a pure function over two arrays. It performs no I/O and is the single unit test target for this behaviour.

**Why the merge matters more than it looks.** If the user's Google account is added under iOS Settings, EventKit already returns those events, so in the common configuration Phase D's Google source is fully redundant and the dedup rule is the only thing preventing every event from appearing twice. The Google source earns its keep only for accounts not added to iOS, and it is deliberately last and optional in the phasing for that reason.

### 6.4 Writes

`CalendarStore` never writes to a provider. Writes route through `CalendarSync.write(...)`, which dispatches to the source that owns the event by its `source` field, then re-syncs the affected window so the cache reflects whatever the provider actually stored. Providers normalise fields (all-day handling, timezone coercion), so trusting the local draft after a write would drift.

---

## 7. Assistant: the server

`supabase/functions/assistant-chat/index.ts`, modelled on the existing `gemini-chat` function but with three differences.

**Model:** `claude-haiku-4-5`. The exact string, with no date suffix appended. Haiku 4.5 has a 200K context window and does not accept the `output_config.effort` parameter, so requests must not send one.

**Request:** accepts `{ system, messages, tools }`, forwards to `POST https://api.anthropic.com/v1/messages` with `x-api-key: ANTHROPIC_API_KEY` and `anthropic-version: 2023-06-01`, and returns the response body unchanged. `max_tokens` is set to 2048 server-side; replies here are short and the cap is a cost backstop.

**Auth:** verifies the caller's Supabase JWT and rejects anonymous requests. The DayGuide function was reachable by anyone holding the URL. The assistant's Anthropic spend makes that unacceptable here.

**Usage cap:** a `assistant_usage` table keyed by `(user_id, month)` is incremented per request and the function returns HTTP 429 past the cap. Enforced server-side, so editing the client cannot bypass it. The client also tracks the count locally to show remaining messages, but that copy is advisory only.

Secrets: `ANTHROPIC_API_KEY` set via `supabase secrets set`. It never reaches the app.

---

## 8. Assistant: the tool catalog

Six tools. Four are answered entirely from the local cache and cost nothing beyond the tokens describing them.

| Tool | Input | Executes against | Gated |
|---|---|---|---|
| `get_events` | `start`, `end` (ISO 8601) | `CalendarStore` | no |
| `find_free_time` | `start`, `end`, `duration_minutes` | `CalendarStore` | no |
| `analyze_schedule` | `start`, `end` | `CalendarStore` | no |
| `create_event` | `title`, `start`, `end`, `is_all_day`, `location`, `notes` | `CalendarSync.write` | no |
| `update_event` | `id`, plus any of the create fields | `CalendarSync.write` | **yes** |
| `delete_event` | `id` | `CalendarSync.write` | **yes** |

`find_free_time` computed locally is why DayGuide's `get_free_busy` tool, which called Google's `freeBusy` endpoint, is not needed. This also means free-slot answers work offline.

Every tool is declared with `strict: true`, which requires `additionalProperties: false` and an explicit `required` array on each schema. This guarantees the `input` object validates before it reaches Swift decoding.

Tool availability follows DayGuide: if no calendar source is authorized, no calendar tools are sent, and the system prompt says so. The model then explains what to connect instead of calling a tool that would fail.

`id` in `update_event` and `delete_event` is the local `CalendarEvent.id` as a UUID string, never a provider id. The model only ever sees ids that `get_events` handed it.

`update_event` and `delete_event` return `is_error: true` with an explaining message when the target row has `isRecurring == true`, so the model tells the user to edit the series in their calendar app instead. See Section 17.

---

## 9. Assistant: the loop

`ToolLoop` runs at most **6 rounds** per user message, down from DayGuide's 10. With events cached locally most turns resolve in one round, and the cap is a cost backstop rather than a real limit. Exhausting it returns a plain message saying the request could not be completed, not a silent stop.

One round:

1. Send `system`, `messages`, `tools` through `AssistantClient`.
2. If `stop_reason` is not `tool_use`, append the text and finish.
3. Otherwise, for every `tool_use` block in the response: execute it if ungated, or hold it if gated (Section 10).
4. When all results exist, append them as `tool_result` blocks in a **single** user message and loop.

Step 4's single-message requirement is not stylistic. Splitting `tool_result` blocks across multiple user messages trains the model to stop making parallel calls.

Failed tools return `tool_result` with `is_error: true` and a short reason rather than being dropped, so the model can recover or explain.

---

## 10. The confirmation gate

The gate is structural. `update_event` and `delete_event` are described to the model normally, but `ToolLoop` is not wired to execute them.

When a gated `tool_use` arrives, the loop returns `.awaitingConfirmation(PendingWrite)` and suspends. `PendingWrite` carries the tool call plus the current `CalendarEventSnapshot` read from the store, so the card can show the before state beside the proposed after state.

- **Confirm.** Execute, append the `tool_result`, resume the loop.
- **Cancel.** Append `tool_result` with `is_error: true` and the text "User declined this change", resume the loop so the model can acknowledge it.

The model cannot skip the gate because nothing it emits can cause a gated write to execute. This is the substantive improvement over DayGuide, which asked Gemini in the system prompt to confirm first, and therefore relied on the model choosing to.

**Batch interaction.** A single response may contain several `tool_use` blocks, some gated and some not. Ungated ones execute immediately, gated ones queue, and the user message is not sent until every block has a result. If several gated calls arrive together they are confirmed one at a time in arrival order.

Creates are not gated, per the brainstorming decision. A newly created event is announced in the reply with an undo affordance on the message.

---

## 11. System prompt and context budget

Assembled per message:

- Current date, time, and IANA timezone identifier.
- Which calendar sources are authorized.
- Today's and tomorrow's events, inlined as a compact list.
- Behavioural instructions: resolve relative dates against the stated current time, never invent an event id, state times in the user's timezone, keep replies to a sentence or two.

Inlining the next two days means the common question ("what's on today?") is answered with zero tool calls, which is the single largest cost saving available.

History is capped at the last **20 messages**, down from DayGuide's 50.

**Prompt cache.** A `cache_control` breakpoint sits after the tool definitions. Render order is `tools`, then `system`, then `messages`, so the tool block is the stable prefix; the volatile date line and event list sit after it in `system` and are not cached. The tool definitions run about 1,500 tokens, comfortably over the roughly 1,024-token minimum cacheable prefix. `usage.cache_read_input_tokens` should be non-zero from the second message of any conversation; if it is zero, something upstream of the breakpoint is varying per request.

---

## 12. Cost model

Haiku 4.5 is $1.00 per million input tokens and $5.00 per million output tokens.

Per user message, assuming two API calls per turn (one tool round plus the reply), since each round resends the full request:

| Component | Tokens |
|---|---|
| Tool definitions | ~1,500 |
| System prompt with inlined events | ~600 |
| History, capped at 20 messages | ~2,000 |
| Input per call | ~4,100 |
| Input per turn, two calls | ~8,200 |
| Output per turn | ~300 |

Uncached: about **$0.0097 per message**. With the tool-definition prefix cached at the 0.1x read rate: about **$0.005 per message**.

At 100 messages per user per month that is roughly **$0.50 to $0.97**, inside the $2 per user per month ceiling while leaving room for Cloud Run, meal analysis, and APNs.

**The cap ships at 100 messages per user per month** and is raised only against observed usage. These figures are modelled, not measured; the first month of real `usage` data replaces them.

---

## 13. UI

### 13.1 Today

`TodaySnapshot` gains `agenda: [CalendarEventSnapshot]` and `calendarAccess: CalendarAccessState`. `TodayViewModel.load()` gains one `CalendarStore` read for today's window. No other view model changes.

`AgendaCard` sits between the streak line and the stat tile grid:

- Header "TODAY" with an event count.
- Up to four rows of time, title, and duration. More than four collapses to "+N more", which opens the day.
- "+ Add event" opens `EventSheet` in create mode.
- Row tap opens `EventSheet` in view/edit mode.
- When access has not been granted, the card body is an empty state with a request button. **The EventKit permission prompt is triggered from here, never at launch.**
- When access is granted and the day is empty, the card says so rather than disappearing, so the affordance stays discoverable.

Styling follows whatever Project 1 lands. This card is built in Phase C, after the restyle, so it is styled once.

### 13.2 The assistant sheet

A sparkle button joins the gear in Today's toolbar and presents `AssistantSheet` full-screen.

- Message list with user and assistant bubbles.
- A compact activity chip per executed tool ("Checked your calendar", "Found 3 free slots"), so tool use is visible rather than implied.
- Confirmation cards for gated writes, rendered inline in the conversation with Confirm and Cancel.
- Composer with a send button, disabled while a turn is in flight.
- Remaining-messages indicator when the monthly count runs low.
- History loads from the most recent conversation on open, matching DayGuide.

`AssistantViewModel` owns the loop and publishes an `AssistantSnapshot`. The sheet stays a pure function of that snapshot, consistent with every other screen in this app.

---

## 14. Permissions and privacy

- EventKit full access is requested from the agenda card's empty state, with `NSCalendarsFullAccessUsageDescription` explaining that LifeOS shows the day's schedule and lets the assistant change it.
- Denied access is a first-class state. The agenda card explains it and links to Settings; calendar tools are withheld from the model.
- Calendar events and chat history are stored only on the device.
- **The assistant sends calendar data to Anthropic.** The system prompt inlines today's and tomorrow's events, and `get_events` results enter the conversation. This must be stated in the app's privacy copy and surfaced once before first use of the assistant. It is the one place calendar contents leave the device.
- No calendar data reaches Supabase. The edge function forwards the request and stores only the usage counter.

---

## 15. Phasing

Ordered so nothing collides with Project 1 until Project 1 has landed.

**Phase A: calendar core.** `CalendarEvent`, `CalendarStore`, `CalendarSource`, `EventKitSource`, `CalendarMerge`, `CalendarSync`, schema registration, tests. Touches no view file. Safe to land while the restyle is in flight.

**Phase B: assistant.** `assistant-chat` function, `assistant_usage` table, `Assistant` target, `AssistantSheet`, the toolbar button, tests. The sheet is a new screen, so the restyle does not rework it. This phase delivers the interaction the user actually asked for, and it does not depend on Phase C.

**Phase C: agenda card.** After Project 1 merges: `AgendaCard`, `EventSheet`, `TodaySnapshot` and `TodayViewModel` changes. Built once, in the new visual language.

**Phase D: Google Calendar source.** Optional and last. `GoogleCalendarSource` behind `CalendarSource`, plus the Supabase Google OAuth provider, a token store, and refresh, modelled on `WhoopOAuth`. Deferrable indefinitely for any user whose Google account is in iOS Settings.

Phase B before Phase C is deliberate: the assistant works against the store from Phase A and needs no agenda card to be useful.

---

## 16. Testing

**`PersistenceTests`**

- Upsert matches on `(source, sourceID)` and does not duplicate across syncs.
- In-window rows absent from a fetch are deleted; out-of-window rows are untouched.
- `CalendarStore` window queries respect day boundaries and all-day events.
- `find_free_time` given a day of known events returns the expected gaps, including the empty-day and fully-booked cases.

**`IntegrationsTests`**

- `CalendarMerge` dedupes on case-insensitive title plus equal start, and EventKit wins collisions.
- A source that throws does not prevent the other source's events from being merged.

**`AssistantTests`**, against a stubbed transport and a fake `CalendarSource`

- The loop stops at 6 rounds and returns the exhaustion message.
- A gated `tool_use` suspends the loop and executes nothing.
- Confirm resumes with a `tool_result`; cancel resumes with `is_error: true`.
- Several `tool_result` blocks from one response are sent in exactly one user message.
- A throwing tool produces `is_error: true` rather than a dropped block.
- History is truncated to 20 messages.

Every test runs under `swift test` with no simulator and no network, which is why `EventKitSource` sits behind a protocol and `AssistantClient` behind a transport.

---

## 17. Out of scope

- **Gmail.** DayGuide's `draft_email` and `send_email` tools are not ported. The assistant scope decision was calendar only.
- **LifeOS data in the assistant.** No recovery, habit, plan, money, or Whoop access, read or write.
- **Event mirroring to Supabase**, and any web view of the calendar.
- **Voice input.** DayGuide used `expo-speech-recognition`; not carried over.
- **Notifications and reminders** for events. Project 3 owns the notification pipeline; revisit after it lands.
- **Attendees and invitations.** Events are read and written as the user's own. No invite semantics.
- **Recurring event editing.** A recurring event can be read and, in Phase A, is cached as its expanded occurrences. Editing "this occurrence" versus "the series" is not modelled; `update_event` and `delete_event` are rejected for events belonging to a recurrence rule, with the tool returning an error the model can explain. Full recurrence handling is a follow-up.

---

## 18. Risks

| Risk | Mitigation |
|---|---|
| Assistant cost overruns the $2 ceiling | Server-side monthly cap at 100, prompt caching, 20-message history, events inlined so most turns need no tool call. Figures in Section 12 are modelled and must be checked against real usage in month one. |
| Duplicate events once Phase D lands | `CalendarMerge` is a pure function with direct unit tests, and Phase D is optional. |
| Model invents an event id and a write targets the wrong event | Ids only ever come from `get_events` results; `CalendarStore` rejects unknown ids; gated writes show the resolved current event on the confirm card before anything executes. |
| Recurring events surprise the user | Rejected explicitly with an explaining error rather than silently mangling a series. See Section 17. |
| Phase C collides with Project 1 | Phase C is scheduled after Project 1 merges, and Phases A and B touch no restyled file. |
| Edge function is throwaway work | It is roughly 100 lines and moves to Cloud Run as a port during Project 0.5. |
