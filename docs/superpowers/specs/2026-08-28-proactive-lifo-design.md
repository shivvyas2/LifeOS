# Proactive LIFO Design

**Date:** 2026-08-28
**Status:** approved, ready for planning

**Goal:** Turn LIFO from a question-answering box into something that
remembers the conversation, uses tools through OpenAI rather than only
Apple's on-device model, speaks first when it has something worth saying,
and closes the loops it opens.

---

## 1. The problem, precisely

LIFO reads as one-sided today for three separate reasons. They are worth
separating because they have three different fixes.

**It has no memory.** `CoachViewModel.send` builds an
`AnswerTask(question:)` carrying the current question and a data digest,
and nothing else. `CoachViewModel.history` is a display array that never
reaches a prompt. LIFO does not know what it said thirty seconds ago, so a
follow-up is impossible in principle rather than merely unimplemented.

**It is instructed to be terse.** `ResponseStyle.instruction` is appended
to every task on both tiers by `CoachTask.styledInstructions`, and it says
"Do not open with a greeting, a restatement of the question, or a preamble
about what you are about to do. Answer, then stop." That was the right
instruction for a one-shot brief rendered into a card. It is the wrong one
for a conversation, and the flatness people feel is this sentence working
exactly as designed.

**It never speaks first.** There is no `UNUserNotificationCenter` call
anywhere in the repository, no `aps-environment` entitlement, and no
background mode. Every sentence LIFO has ever produced was a reply.

Separately, the request to "make OpenAI primary" is narrower than it
sounds. `lifo-agent/index.ts` already calls OpenAI with `gpt-5-mini`, and
`CoachRouter.run` already prefers the cloud. The gap is that the two AI
surfaces each hold half of what a conversation needs:

| Surface | Engine | Memory | Tools |
| --- | --- | --- | --- |
| LIFO coach (`CoachViewModel`) | OpenAI cloud, on-device fallback | none | none |
| Calendar assistant (`AssistantViewModel`) | FoundationModels only | `ChatStore` | yes |

`AssistantTurn`, the only tool-calling loop in the project, is hard-wired
to `LanguageModelSession`. Making OpenAI primary means moving that loop to
a provider-neutral shape, not changing a model string.

Both seams were built for this. `CoachTool.parameters` is a
`GenerationSchema` whose doc comment says it "will serialize into a remote
tools[] payload when a remote engine exists", and `AssistantTurn`'s says
it "grows a provider-neutral loop against Engine" when one does.

---

## 2. Decisions

Settled during design. Each one closes off alternatives, so a plan that
contradicts one of these is wrong rather than merely different.

1. **Real push, thought server-side.** A scheduled job reads synced data
   and sends through APNs. LIFO can open a conversation with the app
   closed. Local-only notifications were rejected because they can only
   ever speak about what the app knew last time it was opened, which is
   precisely when the person did not need reminding.
2. **Rules decide, the model writes.** A deterministic trigger layer fires
   on named conditions. Only a fired trigger costs a model call, and only
   to phrase it. Letting the model read a nightly digest and decide for
   itself was rejected on two grounds: it bills for every user every night
   whether or not anything happened, and models calibrate "is this worth
   interrupting someone" poorly, usually toward yes.
3. **The server remembers only the open commitment.** The conversation
   stays on the device in `ChatStore`. The server keeps small structured
   rows saying what LIFO asked about, which metric closes it, and when it
   expires. No message text is ever written to a table, so the promise in
   `lifo-agent/index.ts` that the prompt "is never written to a table and
   never logged" survives essentially intact.
4. **A narrow sector snapshot syncs upward.** One derived row per user per
   day carrying per-sector floor, ceiling, decided flag, and top lever
   name. This is what lets the most Dry Run thing LIFO could say, that a
   ceiling is slipping out of reach, arrive as a push rather than only when
   the app happens to be open.
5. **The tool loop is client-driven against a stateless server.** A
   server-driven loop is not merely worse, it is infeasible: every tool
   reads device-local state through EventKit, HealthKit, or SwiftData, so
   the Edge Function would have to call back into the phone.

---

## 3. Constraint: where the data actually lives

The server has `daily_metrics`, `sleep_records`, `workout_records`, and
`whoop_raw`. It does not have sector scores, `GoalTargets`, habits,
journal entries, or check-in answers, all of which live only in SwiftData.

Plaid transactions are absent deliberately and stay absent. The
`plaid_items` migration states the reason: transactions are handed straight
back to the device so that "a compromise of this database exposes the
credential but not a ledger of where someone shops." Nothing in this design
changes that, which means money triggers can only ever run on the device.

This constraint, not preference, is what splits the trigger layer in two.

---

## 4. The conversational core

Both surfaces collapse onto one engine. That single move is what makes
OpenAI primary, and it is also what gives the coach a memory.

### 4.1 The `ChatEngine` seam

A second protocol beside the existing `Engine`, which stays untouched and
keeps serving one-shot tasks:

```swift
public protocol ChatEngine: Sendable {
    func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply
}
```

Two conformers:

- `OnDeviceChatEngine` is today's `AssistantTurn.run` body, moved with no
  behaviour change. It remains the offline fallback.
- `RemoteChatEngine` runs the OpenAI function-calling loop through
  `lifo-agent`.

`AssistantTurn.run` becomes the router across the two, remote first. This
mirrors `CoachRouter`'s existing reasoning: quality picks the tier, and the
device is what still works when the cloud will not.

`ToolInvoker`, `ToolGate`, and `ConfirmationBroker` are reused with no
changes. `SessionTool` is the only FoundationModels-specific piece and
gains a sibling rather than a rewrite. Both engines drive the same
`invoker.invoke(name:arguments:)`, so the per-turn cap, the confirmation
gate, and the error shaping are identical whichever model is answering.

Note for the implementer: OpenAI returns tool arguments as a JSON string
while `ToolInvoker.invoke` takes `GeneratedContent`. The adapter converts
at that boundary. Verify `GeneratedContent`'s JSON initialiser against the
SDK before assuming the shape.

### 4.2 Wire format

`lifo-agent` accepts a superset of what it takes today:

```json
{ "task": "chat", "messages": [ ... ], "tools": [ ... ] }
```

and returns either a final `{"output": ...}` or `{"tool_calls": [ ... ]}`
for the device to execute and resend. The existing `{task, prompt}` shape
keeps working, so `AnswerTask` and any future one-shot task need no
change on either side.

`openAIBody` in `_shared/lifo.ts` grows a branch that builds a messages
array and a tools array instead of a fixed system-and-user pair.

Rounds are capped by the existing `ToolInvoker.invocationLimit` of 6, so
one turn cannot spiral into a bill.

### 4.3 Memory

`ChatStore.recent(conversationID:limit:20)` already exists and already
persists. The coach gains a conversation id of its own and renders recent
turns into `messages[]`. The server writes nothing.

### 4.4 `ResponseStyle` splits in two

`ResponseStyle.instruction` stays exactly as it is, and stays applied to
one-shot artifacts: `BriefTask`, `SectorNoteTask`, and anything else whose
output lands in a card where preamble is noise.

A new `ResponseStyle.conversation` serves chat. It keeps every typography
prohibition verbatim, so no markdown, no em dashes or en dashes, no
decorative quotation marks. It drops "answer, then stop" and permits
exactly three things the current instruction forbids:

1. Referring back to what was said earlier in the thread.
2. Acknowledging what the person told it before answering.
3. Asking one question back, when it genuinely needs to know something to
   answer well. One, not a list, and not as a conversational tic.

`ResponseStyle.clean(_:)` is shared and unchanged. It is the net that
catches drift regardless of which instruction produced the text.

---

## 5. The trigger layer

A trigger is a pure function from rows to an optional fired result. No
model, no network, no container. This is the same shape as
`EscalationPolicy.disposition(for:)` and `SectorEvidenceFactory.evidence`,
and it is what makes the interesting logic testable.

A fired trigger carries: a stable name, the numbers that made it fire, and
a deterministic fallback sentence. The fallback is what gets sent when the
model is unreachable, so a trigger is never silently lost to an outage.

### 5.1 Server-side triggers

Evaluated nightly from rows the server already has. These are the ones
worth waking a closed app for, and they are morning-relevant anyway.

- Three short nights against the person's own sleep target.
- A workout streak about to break.
- Steps collapsing against the trailing 14-day baseline.
- At least one positive: a genuinely strong week, or a personal best.

The positive is not decoration. A notification channel that only ever
carries bad news gets switched off, and then none of the rest of this
matters.

### 5.2 Device-side triggers

Evaluated on app open or background refresh, using SwiftData and the
existing Dry Run types.

- `SectorBand` ceiling slipping out of reach.
- `Leverage.ranked` changing which lever matters most.
- A spend spike, which can only ever be evaluated here.
- A habit or journal gap.

Same trigger protocol, different host. Sector triggers also reach the
server through the snapshot in section 6.3, so the ceiling nudge can push.

### 5.3 Volume rules

- **At most one push per day per user.** Silence is the common outcome and
  a valid one.
- **Send hour is 8am local, and nothing ever sends outside 7am to 9pm
  local.** The device token row carries the timezone; the job runs hourly
  and selects users whose local hour matches the send hour.
- **Seven-day cooldown per trigger**, so the same observation cannot arrive
  on Tuesday and again on Thursday.
- **Closing a loop beats opening one.** Open commitments are checked before
  triggers are evaluated.

---

## 6. Delivery

### 6.1 `device_tokens`

```
device_tokens (user_id, token, platform, timezone, updated_at)
```

RLS scoped to `auth.uid()` like every other table, with the service role
reading for the send.

**Account switching is a correctness requirement here, not a nicety.**
Commit `df18113` let several accounts share one device. A token registered
under account A and left behind when the device switches to account B would
push A's sleep data to a phone showing B's name. Registration is therefore
keyed to the active account, and signing out or switching deletes the row
rather than orphaning it.

### 6.2 `lifo-nudge`

An Edge Function run hourly by `pg_cron`. For each user whose local hour is
the send hour:

1. Resolve open commitments. If one closes or expires, that is the message.
2. Otherwise evaluate triggers over the user's rows.
3. If nothing fired, stop. This is the common path and it costs nothing.
4. Insert into `nudge_log` first. If the insert conflicts, another run
   already claimed today and this one stops.
5. Phrase the fired trigger with one small model call, debited through the
   existing `lifo_debit`.
6. Send through APNs.

Decisions live in `_shared/nudge.ts` as pure functions, with
`nudge_test.ts` beside them. `index.ts` owns the door only. This is the
division `lifo.ts`/`index.ts` and `plaid.ts`/`plaid-sync` already use.

APNs auth is an ES256 JWT signed from a `.p8` held in function environment
(`APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, bundle id), cached for under an
hour.

`aps-environment` and the `remote-notification` background mode are added
to `LIfeOS.entitlements` as part of the slice that uses them. The file's
existing comment explains why entitlements are not claimed ahead of the
code that needs them, and that norm is followed here.

### 6.3 `sector_snapshots`

```
sector_snapshots (user_id, day, sector, floor, ceiling, decided, top_lever)
```

Written by the device once a day. Derived state only, always recomputable
from the phone, which is the same justification `daily_metrics` gives for
its own existence. No answers, no journal text, no transactions.

### 6.4 `nudge_log`

```
nudge_log (user_id, trigger, sent_at)  -- unique (user_id, day)
```

Enforces one-per-day at the database rather than in logic, which is what
makes two overlapping cron runs safe. Also powers the seven-day cooldown
and serves as the audit trail for "why did it say that".

### 6.5 The tap-through

Tapping a notification opens LIFO with the nudge seeded as the first
assistant turn of a conversation.

This is the point of the whole design. The notification is not something
to dismiss, it is an opening line that can be answered, and it is only
answerable because section 4 gave the coach a thread. A nudge that opens a
dead end is a reminder, and the app does not need another reminder.

The tap-through re-evaluates locally rather than trusting the
notification's numbers, which may be two days stale if the phone was
offline.

---

## 7. Follow-ups

```
open_commitments (
  user_id, trigger, asked_at, metric, closes_when, expires_at, resolved_at
)
```

Structured columns only, never text.

Two ways one opens:

- A nudge that asked a question opens one automatically.
- LIFO calls a `noteCommitment` tool during chat when the person says they
  will try something. It is an ordinary `CoachTool`, so it inherits
  `ToolInvoker`'s cap and confirmation gate with no special handling.

Resolution: the nightly job checks commitments before triggers. If the
metric moved over the window, LIFO says so. If it did not, LIFO asks once
and then lets the row expire in silence. Nothing is nagged twice, and no
commitment lives past fourteen days.

---

## 8. Cost

`DAILY_TOKEN_CAP` is 150,000 tokens per day, which is 4.5M per month. At
gpt-5-mini's rates that is roughly 1.90 dollars if a user spends all of it,
so the existing cap already is the 2 dollar ceiling. Current pricing should
be re-checked before this ships, but the shape holds.

Proactive spend does not raise that ceiling, because it shares the ledger.
It raises the average instead, and that is the real effect to plan for.
Chat costs money only for engaged users; a morning nudge costs money for
every user on every eventful day whether they engage or not.

The phrasing call itself is small. The trigger already carries its numbers,
so the prompt is on the order of 300 tokens in and 60 out, roughly a cent a
month even firing daily. The actual driver is the conversation the
notification invites, and that is the trade being made deliberately:
proactivity exists to raise engagement, and engagement is what costs.

**`lifo_usage` gains `kind` in its primary key**, with a small separate
nudge allowance. Without it, a heavy chat evening silently eats the next
morning's nudge, and someone who spent their budget at 11pm wakes up to
nothing.

---

## 9. Failure modes

- **APNs 410 Unregistered** deletes the `device_tokens` row. Without this
  the job pushes at dead tokens indefinitely.
- **Model unavailable** sends the trigger's deterministic fallback
  sentence. **Model refuses** sends nothing and logs. This is the same
  distinction `EscalationPolicy` draws between a transient fault and a
  safety decision, and for the same reason: a refusal must never be routed
  around.
- **Overlapping cron runs** are handled by inserting into `nudge_log`
  before sending, under the unique constraint.
- **A phone offline for days** receives a push carrying stale numbers. The
  tap-through re-evaluates rather than trusting the text.
- **No timezone on the token row** means no send. A nudge at the wrong hour
  is worse than no nudge.
- **A tool loop that will not converge** is bounded by
  `ToolInvoker.invocationLimit`, which already exists and already returns a
  recoverable string to the model rather than throwing.

---

## 10. Testing

- Server triggers: pure functions in `_shared/nudge.ts`, table-driven Deno
  tests in `nudge_test.ts`.
- Device triggers: table-driven swift-testing suites, no model, no network.
- `RemoteChatEngine`: stubbed transport, in the shape
  `RemoteEngineTests` already uses.
- `ResponseStyle.conversation`: the `clean(_:)` guarantees are already
  covered and stay covered. The new instruction gets tests that the shared
  cleaner still strips markdown and dashes from conversational output.
- Wire compatibility: an explicit test that the old `{task, prompt}` shape
  still round-trips, so `AnswerTask` cannot regress while chat is built.

**What testing cannot cover:** whether a given sentence was worth
interrupting someone for. That needs a week of real days on a real device
with real data, and this spec says so rather than pretending otherwise.
The volume rules in 5.3 exist because that judgment is unreliable and the
cost of getting it wrong is a permanently disabled notification channel.

---

## 11. Slices

Each ships on its own and is worth shipping on its own.

**Slice 1: conversational core.** Section 4. Memory, tools, OpenAI
primary. No notifications, no new tables, no entitlements. LIFO gets
immediately better and the riskiest architectural change lands first,
where it can be judged on its own.

**Slice 2: push and health triggers.** Sections 5.1, 5.3, 6.1, 6.2, 6.4,
6.5, 8, 9. LIFO speaks first, using data the server already has. No new
data leaves the device. `lifo-nudge` ships without step 1 of section 6.2,
since commitments do not exist until slice 3, and gains it there.

**Slice 3: sector snapshot and follow-ups.** Sections 5.2, 6.3, 7. The
Dry Run ceiling nudge, and loop-closing.

---

## 12. Not covered

- Android or web delivery. APNs only.
- Any change to what Plaid stores server-side. Transactions stay off the
  server permanently.
- Notification preferences beyond on and off. Per-trigger opt-out is a
  reasonable later addition and is not designed here.
- Streaming responses. The current request-and-wait shape is kept.
