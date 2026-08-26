# LIFO Agent: remote brain, full voice loop, daily brief

**Date:** 2026-08-26
**Status:** Approved direction; awaiting implementation plan

## What this is

LIFO today is an on-device coach: ElevenLabs Scribe transcribes speech, an
Apple Intelligence engine answers over a 14-day metrics digest, and
`CoachRouter(onDevice:remote:)` carries a remote slot that has been `nil`
since it was written. This spec fills that slot and completes the loop:

1. A **remote agent** on OpenAI, streamed from a Supabase Edge Function.
2. **Full user-data context**, assembled on the device per question.
3. **Voice out** through ElevenLabs, so LIFO talks back.
4. A **daily brief** that notifies only when something deserves attention.

Decisions made with the app's owner:

| Decision | Choice |
|---|---|
| Model | `gpt-5-mini` by default, escalate to `gpt-5` on hard tasks |
| Voice reply | Full loop: voice question gets a spoken answer, typed stays silent |
| Proactivity | Daily brief push notification, silent when nothing matters |

## Architecture

Three new Edge Functions, one new app-side engine, one background task.

### `lifo-agent` (Edge Function)

The only place the OpenAI key lives (`OPENAI_API_KEY` project secret).

- **Auth:** verifies the caller's Supabase JWT, same as `plaid-*`.
- **Input:** `{ task, question, bundle, transcriptHints }` where `bundle`
  is the device-built context (below).
- **Output:** SSE stream of tokens, so the first word is on screen in
  well under a second.
- **Escalation:** runs `gpt-5-mini`; retries once on `gpt-5` when the
  task declares a cloud floor with `depth: deep`, or when the mini reply
  self-reports low confidence. Mirrors the router's on-device-to-cloud
  philosophy one level up.
- **Budget:** per-user daily token ledger in a `lifo_usage` table
  (user_id, day, tokens). Hard stop at the daily cap returns the router's
  `exhausted` shape. Cap chosen to keep spend inside the $2/user/month
  ceiling: 150k tokens/day on mini pricing leaves ample headroom, and
  escalated calls debit at the gpt-5 rate multiplier so heavy days
  self-limit.
- **Retention:** the bundle is used for the completion and discarded.
  Never written to a table, never logged. Log lines carry user id, task
  name, token counts, latency; never content.

### `lifo-speak` (Edge Function)

ElevenLabs TTS proxy. Holds `ELEVENLABS_API_KEY` as a project secret.
Streams `eleven_flash_v2_5` audio for reply text. Also gains a
`/transcribe` twin so Scribe STT moves server-side and the key ships out
of the app binary entirely (today it is compiled in via Secrets.xcconfig,
which is extractable from any ipa). The app-side
`ElevenLabsSpeechClient` becomes a client of this function; its interface
does not change, so `SpeechListener` is untouched.

### `RemoteEngine` (LifeOSKit, Insights)

Implements the existing `Engine` protocol. Wires into
`CoachRouter(onDevice: OnDeviceEngine(), remote: RemoteEngine())` in
`CoachViewModel`. The router's existing result vocabulary (`answered`,
`degraded`, `refused`, `exhausted`, `unavailable`, `tooLarge`) maps
1:1 onto the function's responses, so every failure already has UI.

### ContextBundle (LifeOSKit)

The "all the user's data" piece, honoring the standing rule that the
server never holds a ledger (see the plaid_items migration): data goes
up per-request, never lives there.

Extends the existing `MetricsDigest` pattern into one encodable bundle:

- Health: the current 14-day MetricsDigest (sleep, recovery, workouts).
- Money: MoneySnapshot summary plus the last 30 days of transactions
  (merchant, amount, category; capped and truncated by recency).
- Life board: nine sector scores with six-month history and deltas.
- Habits, goals, plans: current streaks, targets, upcoming items.
- Profile: first name, country, local time of day.

Budgeted to a few thousand tokens; a `tooLarge` guard trims transaction
detail first, history second.

### Daily brief (app target)

A `BGAppRefreshTask` scheduled each morning. It builds the bundle
on-device (the server cannot, by design), calls `lifo-agent` with
`task: brief`, and posts a local notification only when the reply's
`worthNotifying` flag is true. The prompt instructs: one insight,
concrete, from the data (recovery tanked, spending spiked, streak at
risk); answer `worthNotifying: false` on an ordinary day. iOS schedules
BG tasks opportunistically; a missed morning is acceptable and the
in-app coach screen shows the same brief as a card when opened.

## Voice loop

- In: unchanged. SpeechListener records, Scribe transcribes (now via
  `lifo-speak/transcribe`).
- Out: when the question arrived by voice, CoachViewModel requests TTS
  for the streamed reply and plays it as text renders. Typed questions
  render silently. A speaker toggle on the coach screen mutes the loop.

## Guardrails

- **Scope:** system prompt pins LIFO to coaching this user over their
  own LifeOS data. It declines general-assistant work (essays, code,
  world facts beyond what grounds an insight) and redirects to the data.
- **Advice limits:** observations and nudges, never medical diagnoses,
  never specific security or investment picks. Money talk stays at
  budgeting and pattern level.
- **Access:** JWT-gated functions; no anonymous path. The bundle is the
  only data channel; functions never query user tables for content.
- **Spend:** server-enforced daily token ledger (above). The app shows
  the router's `exhausted` message when hit.
- **Privacy:** no bundle retention or content logging; ElevenLabs and
  OpenAI keys live only in Edge Function secrets after this ships.
- **Fallback:** on-device engine still answers when offline or when the
  remote refuses; the router already degrades gracefully.

## Cost check (against the ~$2/user/month ceiling)

Assumptions: 20 questions/day at ~3k tokens in / 500 out on mini, one
brief/day, 10% escalation to gpt-5, TTS on half the replies at ~400
characters. Mini traffic lands around $0.60/month, escalations around
$0.40, ElevenLabs Flash TTS around $0.50 at consumer rates. Inside the
ceiling with room; the ledger hard-caps the tail.

## Testing

- LifeOSKit: ContextBundle assembly (deterministic fixtures for each
  data source, truncation order under budget), RemoteEngine response
  decoding onto router outcomes, brief `worthNotifying` decode.
- Edge Functions: Deno tests like `otp_*_test.ts` for auth rejection,
  budget ledger arithmetic and cutoff, SSE framing, escalation trigger,
  and the OpenAI/ElevenLabs clients behind injected fetch fakes.
- Manual: simulator run of the full voice loop; forced `exhausted` and
  offline paths.

## Slices

1. `lifo-agent` chat + RemoteEngine + ContextBundle (text only, mini
   model, budget ledger). LIFO gets smart.
2. `lifo-speak` TTS + full voice loop + STT proxy migration (key leaves
   the app).
3. Escalation to gpt-5.
4. Daily brief + notification.

Each slice ships behind the router: if a slice is absent the coach
behaves exactly as today.
