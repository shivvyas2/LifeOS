# Voice reach: LIFO on HomePod and on Alexa

Decided 2026-10-06 with the owner: both surfaces, with a small daily digest
published by the phone so an Echo can answer about the day. Rejected: Siri
only; an Alexa skill that answers from no personal data.

One correction to the conversation that led here: the server already holds
each person's daily health metrics (`daily_metrics`, `sleep_records`,
`workout_records`), because the proactive nudges read them. What it does not
hold is the calendar, which lives in EventKit and the on-device store, or the
Life sector scores. The digest adds those two and nothing else.

## 1. Siri, HomePod and the rest of Apple's surfaces

No server work. App Intents run on the iPhone; HomePod, Apple Watch, CarPlay
and AirPods hand the request to the phone and speak what comes back. On
HomePod this needs Personal Requests on for that speaker and the phone on the
same network, which is Apple's rule for every third-party app.

### The headless turn

`CoachViewModel.send` is split. The part that builds the `ContextBundle`,
renders the two tiers' instructions and runs `AssistantTurn.run` moves into
`CoachTurnRunner` (app target, `@MainActor`), with one method:

```swift
func answer(_ question: String, spoken: Bool) async throws -> CoachAnswer
// CoachAnswer { shown: String; spoken: String?; tier: AssistantTurn.Tier }
```

The view model calls it and keeps everything about phases, holding, the
voice and the transcript. The intents call it with `spoken: true` and read
`spoken`, which is the opening passage of the spoken track (the LIFO spoken
track spec) or, when the model wrote none, the first plain paragraph. Both
callers append the exchange to the same LIFO conversation in `ChatStore`, so
a question asked of a HomePod is on the LIFO screen when the phone is next
opened.

### The intents

`LifeOSShortcuts: AppShortcutsProvider` in the app target. App Shortcut
phrases may carry only `AppEnum` or `AppEntity` parameters, never free text,
so the open question is asked for in a second step.

| Intent | Phrases | What it does | Dialog |
|---|---|---|---|
| `AskLifoIntent` | `Ask \(.applicationName)`, `Talk to LIFO in \(.applicationName)` | `@Parameter(title: "Question", requestValueDialog: "What would you like to ask LIFO?") var question: String`; Siri asks, the person answers, `CoachTurnRunner.answer` runs | `spoken`; `shown` as the full version for screens |
| `TodayScheduleIntent` | `What's on today in \(.applicationName)`, `My schedule in \(.applicationName)` | Reads today's events from `CalendarStore` | `SpokenAgenda.line(events:now:)` |
| `NextEventIntent` | `What's next in \(.applicationName)` | `[CalendarEventSnapshot].nextUp(now:)` | `SpokenAgenda.next(event:now:)` |
| `ReadingsIntent` | `How did I sleep in \(.applicationName)`, `My readings in \(.applicationName)` | Today's row from `MetricsStore` | `SpokenReadings.line(sleepMinutes:recoveryPct:steps:)` |

- Every intent sets `openAppWhenRun = false` and returns
  `.result(dialog:)`, so a speaker answers without opening anything.
- Wording lives in `SpokenAgenda` and `SpokenReadings` in `Persistence`,
  tested: `Three things today. Standup at 9, lunch with Sam at 12, design
  review at 4.`; `Nothing on today.`; `Next is lunch with Sam at 12, in 40
  minutes.`; `You slept 7 hours 12 minutes and recovery is 82 percent.`;
  a missing reading is left out of the sentence, never read as zero.
- When the calendar is not connected or no model is available, the dialog
  says so in one sentence and nothing else.
- Signed-out or no Apple Intelligence: `AskLifoIntent` uses the remote tier
  when the project is configured for one and the person is signed in,
  exactly as the screen does; otherwise it says `LIFO needs Apple
  Intelligence or a signed-in account to answer that.`
- Nothing leaves the device beyond what the coach already sends.

## 2. Alexa

### Shape

A custom skill, **Alexa-hosted** (Node.js), so the endpoint is a Lambda that
Amazon runs at no charge within the hosted limits (unlimited Lambda requests
per developer account). Requests reaching a Lambda are authenticated by AWS,
so the skill writes no signature verification. The handler is a relay that
owns no data: it reads the linked access token from
`context.System.user.accessToken`, calls the Supabase function
`functions/v1/lifo-agent` with `task: "voice"`, the utterance and the
person's locale, and returns the reply as plain `outputSpeech`. It sends a
progressive response, `Let me look.`, as soon as a question arrives, because
Alexa waits eight seconds in total and a progressive response fills the
first of them without extending the limit.

Invocation name `life o s`. Intents: `AskLifoIntent` with an
`AMAZON.SearchQuery` slot `question`; `TodayScheduleIntent`;
`NextEventIntent`; `ReadingsIntent`; the built-in Help, Stop, Cancel and
Fallback. Without a linked account, every intent but Help answers `Link your
LifeOS account in the Alexa app to get started.` with a `LinkAccount` card.
Version one reads only; it creates, moves and deletes nothing.

### Account linking

Supabase Auth's OAuth 2.1 server (in beta, on all plans, no separate
charge) is the authorization server, so no token code is written:

- Enable it under `Authentication > OAuth Server`. Register a confidential
  client `Alexa` under `Authentication > OAuth Apps` with the three regional
  redirect URLs the Alexa console shows for the skill.
- Authorization endpoint `/auth/v1/oauth/authorize`, token endpoint
  `/auth/v1/oauth/token`, authorization code with PKCE, refresh tokens with
  rotation, access tokens as one-hour Supabase JWTs. Alexa requires an
  access token of at least one hour and refresh tokens that live at least
  180 days or never expire; the plan verifies the project's refresh token
  settings meet that before the skill is submitted.
- The `Authorization Path` is `/oauth/consent`, combined with the Site URL,
  and the consent page is a static page in `web/` beside `plaid-oauth.html`:
  it signs the person in with the existing email code flow, shows what
  Alexa will be able to read, and calls
  `supabase.auth.oauth.approveAuthorization(id)` or
  `denyAuthorization(id)`. Mobile-friendly, no popups, as Alexa requires.
- The access token is a Supabase JWT with `user_id`, so `resolveUser` in
  `supabase/functions/_shared/supabase.ts` accepts it unchanged. The plan
  confirms `auth.getUser()` accepts a token carrying the `client_id` claim
  before anything else is built on it.

### The daily digest

- New table `voice_digest`: `user_id uuid primary key references auth.users
  on delete cascade`, `day date`, `agenda jsonb`, `sectors jsonb`,
  `updated_at timestamptz`. Row-level security: the owner reads and writes
  their own row; the service role reads. `agenda` is today's and tomorrow's
  events as `{ title, start, end, allDay }`, no location, no notes, no ids.
  `sectors` is the nine latest sector scores as `{ title, score }`.
- The phone publishes it from `SurfaceCoordinator.publish()`, which already
  runs after every save, through a new `publishVoiceDigest()`: an upsert
  over PostgREST with the session token, coalesced to at most one write per
  fifteen minutes unless the content changed, skipped entirely when sharing
  is off or the person is signed out. Sign-out and sharing-off delete the
  row, the way the widget tombstones work.
- The function ignores a row older than 36 hours, so an Echo never reads a
  stale day as today.
- Health context comes from `daily_metrics`, `sleep_records` and
  `workout_records`, which the nudges already read: a new
  `_shared/digest.ts` renders the last fourteen days into the same prompt
  lines the phone's `MetricsDigest` writes, with a Deno test beside it.

### The `voice` task

In `supabase/functions/_shared/lifo.ts`: `TASKS.voice` uses `gpt-5-mini`
with `SCOPE`, `CONVERSATION`, and one more paragraph: `You are speaking
through a smart speaker. Answer in at most two sentences and under sixty
words. Say times the way a person says them. If the question needs the
screen, say what you can and suggest opening LifeOS.` No streaming; a
120-token ceiling; the daily token cap is shared with the chat task. The
prompt carries the digest row and the health lines; nothing from the
request is written to any table, as today.

### Publishing

Prerequisites the owner provides: an Amazon developer account, a privacy
policy URL and terms URL hosted in `web/`, an icon at 108 and 512 points,
and a test account whose email code the certification team can reach.
Certification takes about five business days; the skill can be certified
and published later.

## 3. Cost

Alexa-hosted is free within its limits. A voice turn is about 1,500 tokens
on `gpt-5-mini`, well under a cent, and shares the existing daily cap. The
digest is one small row per person. Siri costs nothing. The ceiling in the
cost memory holds.

## 4. Verification

- Tests: `SpokenAgendaTests`, `SpokenReadingsTests` (Persistence); a
  `CoachTurnRunnerTests` smoke test over a fake engine (Insights has
  `ChatEngine` fakes already); Deno tests for `digest.ts` rendering and the
  `voice` task body.
- Simulator: each App Shortcut run from the Shortcuts app with the dialog
  read back; the LIFO screen shows the asked question afterwards.
- Alexa: the developer console simulator against a staging project, then a
  real Echo with a linked account: Help without a link, the link card, the
  four intents, the progressive response, and the Fallback.

## 5. Delivery

After the editorial PRs and the spoken track:

1. `feat/siri-app-intents`: `CoachTurnRunner`, the four intents, the
   wording values.
2. `feat/voice-digest`: the table and policy, `publishVoiceDigest()`,
   `_shared/digest.ts`, the `voice` task.
3. `feat/alexa-skill`: the skill package under `alexa/` (interaction model,
   handler), the consent page and policy pages in `web/`, the Supabase OAuth
   client, and the submission checklist.

## Out of scope

- Writes from Alexa or Siri (creating or moving events).
- Google Assistant; Alexa+ conversational experiences beyond the custom
  skill.
- Any change to what the phone's own coach sends.
