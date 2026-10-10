# LifeOS Focus: a companion app for focus sessions

Date: 2026-10-10
Status: approved in conversation, awaiting written-spec review

## Intent

LifeOS does everything, and opening it to start a focus session means walking
past money, notes and projects to reach a timer. Shiv wants LifeOS to become the
place where life is **tracked**, while the things you **do** live in companion
apps. Focus is the first companion. Sports (activity, badminton, the watch
workout path, workout videos) follows as a separate app with its own spec.

What Shiv decided:

- **Companion app with one shared account.** Anyone can sign up in the Focus
  app without owning LifeOS. The same account then signs in to LifeOS, and the
  reverse works too.
- **Two companion apps**: Focus first, then Sports.
- **LifeOS tracks.** Its focus screens move out. It shows what happened and
  links into the Focus app.
- **One repository.** The new app is new targets in `LIfeOS.xcodeproj` on the
  shared `LifeOSKit` package.
- **Sync through Supabase.** Sessions upload to a `focus_sessions` table, with a
  local store kept for offline use.
- **First-version scope**: the Pomodoro timer, the soundscape, Apple Music, the
  account, the project task picker, the weather and recovery mood inputs, an
  Apple Watch app, the Shortcut, and a Live Activity.
- **Identity**: named "LifeOS Focus", in the same editorial look as LifeOS.

Success means three things:

1. A new user can install LifeOS Focus alone, sign up and run a session.
2. A LifeOS user opens Focus already signed in, and their history is already
   there.
3. Sessions recorded in Focus show up in LifeOS's Today on any device.

## Out of scope

- The Sports app, and moving Activity, Workouts, badminton or the watch workout
  path. These get their own spec.
- Any change to the soundscape synthesis or the timer rules.
- Social or shared focus sessions.
- Android or web clients.

## 1. Architecture

### Targets (in `LIfeOS.xcodeproj`)

| Target | Kind | Bundle ID |
|---|---|---|
| `LifeOSFocus` | iOS app | `com.shivvyas.lifeos.focus` |
| `LifeOSFocusWatch` | watchOS app | `com.shivvyas.lifeos.focus.watchkitapp` |
| `LifeOSFocusWidgets` | widget extension (Live Activity) | `com.shivvyas.lifeos.focus.widgets` |

A watch app pairs with exactly one iPhone app. That is why the watch focus
screen leaves `AlmanacWatch` for `LifeOSFocusWatch`.

### What moves where

| From | To | Notes |
|---|---|---|
| `LIfeOS/Features/Onboarding` sign-up and sign-in screens, `OnboardingViewModel` auth parts | new `LifeOSKit` module **`AccountUI`** | LifeOS and Focus both use it. `SupabaseAuth` stays in `Integrations`. The LifeOS-only onboarding (intro, tour, connections) stays in the app. |
| `LIfeOS/Features/Focus/**` (session model, setup, session and summary screens, `SoundscapeEngine`, `MusicSource`, notifications, now playing, heart rate, inputs, `StartFocusSessionIntent`) | `LifeOSFocus` target | Moved, not rewritten. `FocusLauncher` becomes the Focus app's own router. |
| `AlmanacWatch/WatchFocusScreen.swift` | `LifeOSFocusWatch` | Keeps its UI. Gets its own WatchConnectivity bridge. |
| (new) | new `LifeOSKit` module **`FocusSync`** | The uploader and the server reader. Depends on `Persistence` and `Integrations`. |

These stay where they are: `Soundscape` (timer, composer, DSP),
`Persistence/FocusSessionRecord` with `FocusStore`, and `DesignSystem`.

### Shared sign-in on one device

Both apps leave a **sign-in beacon** in the shared Keychain access group
(`$(AppIdentifierPrefix)com.shivvyas.lifeos.shared`). The beacon holds the
user id, a label and the current **access token only**. A sibling app that
finds a beacon with more than two minutes left offers **"Continue as
<label>"**. On a tap, it trades the token at the `session-handoff` Edge
Function for a new session of its own, with its own refresh token. Refresh
tokens are never shared: Supabase rotates them, and a reused one revokes the
whole family, which would sign both apps out. Signing out of one app
withdraws its beacon but leaves the other app signed in.

### LifeOS after the move

- The Focus screens, the Focus intent and the Focus entries in Today and the
  task sheet are removed.
- Today shows the last focus session and this week's focus time, read through
  `FocusSync`.
- "Start focus" (Today's mood buttons and the project task sheet) opens the
  Focus app. If the app is not installed, LifeOS shows its App Store page in an
  `SKOverlay` or a store sheet.

## 2. Data and sync

### Migration `supabase/migrations/20261010120000_focus_sessions.sql`

```sql
create table public.focus_sessions (
  id uuid primary key,                       -- the local FocusSessionRecord.id
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mood text not null check (mood in ('focus','brainstorm','relax','sleep')),
  source text not null check (source in ('soundscape','appleMusic','silence')),
  started_at timestamptz not null,
  ended_at timestamptz,
  focused_seconds integer not null check (focused_seconds >= 0),
  blocks_completed integer not null default 0 check (blocks_completed >= 0),
  project_task_id uuid references public.project_tasks (id) on delete set null,
  created_at timestamptz not null default now()
);
create index focus_sessions_user_started on public.focus_sessions (user_id, started_at desc);
alter table public.focus_sessions enable row level security;
-- select, insert and delete where user_id = auth.uid(); no update policy (sessions are final).
```

The check lists are the raw values of `Mood` and `SoundSource` in
`Soundscape`. A new case there needs a migration that widens the check.
The table joins the account controls: Clear data gets a "Focus sessions"
choice, and Delete account cascades through `user_id`.

### Local record

`FocusSessionRecord` gains `syncedAt: Date?`. It is optional, per the
SwiftData rule, so existing stores still open.

### `FocusSync`

- `FocusUploader.uploadPending()` fetches local records where `syncedAt == nil`
  and `endedAt != nil`. It sends them in batches to PostgREST with
  `Prefer: resolution=ignore-duplicates`, so a re-send is a no-op, then sets
  `syncedAt`.
- It is triggered after a session is saved, when the app becomes active, and
  when the network path becomes satisfied (`NWPathMonitor`).
- When it is signed out, or the token is expired and cannot be refreshed, it
  does nothing, and records stay pending. There are no tight retry loops: at
  most one run is in flight, and a failed run waits for the next trigger.
- `FocusReader.week(containing:)` returns the server rows for the week, cached
  locally for offline reads. It leaves out `mood == 'sleep'` from focus time,
  as `FocusStore` does today.

### Project tasks in the Focus app

The Focus app reads the user's open tasks (`status in ('todo','doing')`,
`deleted_at is null`) through the existing `project_tasks` rules. Reading
reuses `ProjectsViewModel`'s REST pattern, moved into `FocusSync` or a small
`ProjectsRead` helper. Tasks are cached for the picker, and the Focus app never
writes tasks.

### Mood inputs

- **Weather**: WeatherKit plus the location the user grants. The Focus app
  needs its own WeatherKit capability.
- **Recovery**: read from HealthKit (HRV SDNN and resting heart rate over the
  last night, compared with a 7-day baseline), mapped to the existing
  `RecoveryLevel`. The read is read-only. When no data is available, recovery
  is nil and the composer ignores it, as it does today.

### Cost

One row of about 200 bytes per session. Reads are one weekly query per
LifeOS Today load, cached. This is far below the $2 per user per month ceiling.

## 3. The Focus app experience

All of it uses the editorial look: `LifeOSTokens`, `Editorial`, and the
LifeOS type. There is one focus accent. The icon is Shiv's choice.

1. **First run**: one intro page, then `AccountUI` sign-in ("Continue as" when
   a shared session exists, else the email or phone code), then a
   notifications prompt. Apple Music and Health are asked for only when the
   user first picks them.
2. **Home**, the only root screen, with no tab bar:
   - the masthead is this week's focus time
   - four mood buttons (Focus, Brainstorm, Relax, Sleep) start a session in one
     tap with the last settings
   - "Resume last"
   - recent sessions as ruled rows
   - a settings button
3. **Setup sheet**: today's `FocusSetupSheet` plus the project task picker.
4. **Session and summary**: moved unchanged.
5. **Settings**:
   - account and sign out
   - the default timer preset
   - "N sessions waiting to sync", shown only when N > 0
   - "Open LifeOS"

### Live Activity (`LifeOSFocusWidgets`)

- `FocusActivityAttributes`:
  - static: mood, task title
  - dynamic: phase, phase end date, paused, blocks done
- The Lock Screen and the Dynamic Island (compact, minimal and expanded) show
  a countdown with `Text(timerInterval:)`.
- Pause, resume and skip are `LiveActivityIntent`s handled by the running app.
  The app keeps running because of the background-audio session; silence-mode
  sessions play a silent track for this.
- The activity is started and ended by the session model. A stale activity is
  ended when the app launches.

### Watch (`LifeOSFocusWatch`)

- `WatchFocusScreen` is moved over.
- The watch mirrors the phone's active session through WatchConnectivity
  application context.
- A quick start on the watch sends a start message to the phone. If the phone
  is unreachable, the watch runs the timer alone and sends the finished record
  to the phone later through `transferUserInfo`.

### Shortcuts and URLs

- `StartFocusSessionIntent` and its `AppShortcutsProvider` move to the Focus
  app with the same parameters. The release notes say that existing shortcuts
  need re-adding once.
- The URL scheme is `lifeosfocus://start?mood=<mood>&task=<uuid>`, plus
  `lifeosfocus://` with no parameters, which opens Home.
- LifeOS adds `lifeosfocus` to `LSApplicationQueriesSchemes` and checks with
  `canOpenURL` before choosing between opening the app and showing the store.

## 4. Moving existing data, errors, testing and build order

### Existing history

On the first launch of the LifeOS release that includes `FocusSync`, LifeOS
runs `uploadPending()` over its existing local records. Because the row ID is
the local ID, the upload is safe to repeat. LifeOS removes its focus screens
only in the release that also ships the link-outs.

### Errors

| Situation | Behaviour |
|---|---|
| Signed out or the token cannot be refreshed | Sessions save locally and upload after the next sign-in |
| No Apple Music subscription or permission | Falls back to the soundscape with a one-line note (today's behaviour) |
| Task fetch fails | The picker shows the cached list, or "No tasks" with Retry |
| Upload fails | No alert. The record stays pending and the count appears in Settings |
| HealthKit or WeatherKit unavailable | That input is nil and the composer ignores it |

### Testing

- **`FocusSyncTests`** cover:
  - choosing what to upload (pending versus synced versus unfinished)
  - re-sends that create no duplicates (a stubbed `URLProtocol`)
  - doing nothing while signed out
  - setting `syncedAt` only after a 2xx response
- **The migration's security rules**: a SQL check that a second user cannot
  select, insert or delete another user's rows, run against local Supabase.
- **`AccountUITests`**:
  - mode toggling
  - the code flow, with a stubbed `SupabaseAuth`
  - "Continue as" when a shared session exists
- **UI tests**: a `--design-preview --page=focus-home` fixture in the Focus app
  covers the one-tap mood start, the task picker and the summary. The four
  pbxproj entries per UI test file apply.
- **On real hardware**: the Live Activity controls on the Lock Screen and in
  the Dynamic Island, and the watch quick start with the phone in airplane
  mode.

### Build order (one PR per slice, each shippable)

1. **`AccountUI`**: pull the sign-in screens and auth logic into the module
   and use them from LifeOS. There is no visible change. Add the shared
   Keychain group.
2. **`focus_sessions` + `FocusSync`**:
   - the migration
   - the uploader
   - LifeOS uploads its history
   - Today reads the week from the server, with a local fallback
3. **The Focus app targets**:
   - `LifeOSFocus`, `LifeOSFocusWatch` and `LifeOSFocusWidgets`, without the
     Live Activity yet
   - the moved Focus code
   - Home, the task picker, the HealthKit recovery reading and Settings
4. **The Live Activity and Shortcuts** in the Focus app.
5. **The LifeOS link-outs**: remove the Focus screens, the URL scheme check
   and the store fallback.

### Owner steps (Shiv)

- In App Store Connect, create the "LifeOS Focus" app record and register
  three App IDs, enabling:
  - MusicKit, WeatherKit, HealthKit
  - the App Group `group.com.shivvyas.lifeos.focus`
  - Keychain Sharing
- Enable Keychain Sharing on the LifeOS App ID with the same shared group.
- Push the migration (`supabase db push`).
- Choose the app icon.

Slices 1 and 2 need none of these steps except the migration push.
