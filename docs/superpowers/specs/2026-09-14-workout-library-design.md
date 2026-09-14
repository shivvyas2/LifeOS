# Workout library: curated videos, a planner, and the HUD on the player

**Date:** 2026-09-14
**Status:** approved in conversation, spec under review
**Builds on:** `2026-09-14-live-session-core-design.md` (readout, HUD,
recorder), `2026-09-14-watch-companion-design.md` (reps and sets),
`2026-08-25-health-restructure-restyle-design.md` (Fitness segment, tokens).

## 1. The problem

A person who wants to train has to know what to do today. Almanac shows what
the body did and how recovered it is, but never suggests a session, and has
no way to follow one. The request: pull up workouts from YouTube that match
what the person wants to do (strength, then push, pull, legs, arms, chest),
coordinated with how much they can push today, with the live glass HUD on
the video.

Constraints that shape the design:

- The app ships free; running cost stays under about $2 per user per month.
  So: no runtime AI calls, no per-user YouTube API quota.
- YouTube's terms forbid playing videos outside their player or obscuring
  it. Shiv chose an overlaid capsule for landscape; section 5.3 keeps it as
  small and as far from the player's controls as the design allows and
  records the risk.
- A missing value is never a zero; a video the catalog cannot verify never
  ships.

## 2. What this slice delivers

| Area | Change |
|---|---|
| Catalog | A read-only Supabase table of about 60 curated videos tagged by goal, split, muscles, equipment, intensity and duration, every id verified through YouTube's keyless oEmbed endpoint at seed time. |
| Preferences | Goal, equipment and session length on the goals row, asked on first open. |
| Planner | A pure function from preferences, today's battery and recent splits to today's session and its reason. |
| Library screen | Today's plan, then the catalog filtered to it, reachable from the Fitness segment and from Begin Activity. |
| Player screen | YouTube's privacy-enhanced embed with the glass HUD; Start begins a recorder session stamped with the video. |

Out of scope: downloading or caching video, playlists, user-submitted
videos, AI-generated plans, exercise-by-exercise timers inside a video.

## 3. Catalog

### 3.1 Table

Migration `supabase/migrations/20260915090000_workout_videos.sql`:

```sql
create table public.workout_videos (
  youtube_id   text primary key,
  title        text not null,
  channel      text not null,
  duration_s   integer not null check (duration_s > 0),
  goal         text[] not null,        -- strength | hypertrophy | endurance | mobility
  split        text not null,          -- push | pull | legs | upper | lower | full | core | arms | chest | back | shoulders | mobility | cardio
  muscles      text[] not null default '{}',
  equipment    text[] not null default '{}', -- none | dumbbells | barbell | bands | machine | kettlebell
  intensity    smallint not null check (intensity between 1 and 3),
  verified_at  timestamptz not null,
  updated_at   timestamptz not null default now()
);
alter table public.workout_videos enable row level security;
grant select on public.workout_videos to authenticated;
create policy "catalog is readable when signed in" on public.workout_videos
  for select to authenticated using (true);
```

Enums are text, as the notes table does, so a new split lands as data. No
insert, update or delete grant for `authenticated`: writes are the service
role's, through migrations.

### 3.2 Seed and verification

The seed is a migration with about 60 rows chosen from established
channels with a broad catalogue of follow-along sessions: for example
Jeff Nippard, Jeremy Ethier, Caroline Girvan, Sydney Cummings, Heather
Robertson, MadFit, Yoga With Adriene (mobility), Athlean-X. Coverage target:
push, pull, legs, upper, lower and full at least six each across 20 to 60
minutes and the equipment set; core, arms, chest, back, shoulders at least
three each; mobility and cardio at least five each.

Before a row enters the seed, `scripts/catalog/verify.sh` calls
`https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<id>&format=json`
for each id and fails the seed if any returns an error or a title that does
not match the row's title prefix. oEmbed needs no key and returns title,
author and thumbnail. Durations are entered by hand from the video page and
checked to be within plus or minus 10 percent of the title's stated length
when the title states one ("30 Min…"). The script writes `verified_at`.

Thumbnails are not stored: the app derives
`https://i.ytimg.com/vi/<id>/hqdefault.jpg`.

### 3.3 Client and cache

`WorkoutCatalogClient` in `Integrations`, cloned from `GroupAPI`'s
`read(_:query:token:)`: `func videos(accessToken:) async throws -> [CatalogVideo]`
selecting all columns ordered by `updated_at`. Rows are cached in a new
SwiftData model `CatalogVideo` (upsert on `youtube_id`, array columns stored
as native `[String]` like `SpendBucket.claimedRaw`), refreshed at most once
a day and on pull to refresh. The library works offline from the cache. An
empty cache with no network shows "The library needs a connection the first
time." and never a fake list.

## 4. Preferences and planner

### 4.1 Preferences

`UserGoals` gains three optional columns so the existing row migrates:
`trainingGoal: String?` (the goal vocabulary), `equipmentRaw: [String]`
(default empty), `sessionMinutes: Int?`. The library's first open shows a
three-question sheet (goal, equipment, minutes) and writes them; they are
editable from the library's toolbar.

### 4.2 Planner

Pure Swift in `Sectors` (it already depends on `Persistence`, where the
goals live):

```swift
public struct TrainingPlan: Equatable, Sendable {
    public let split: String
    public let minutes: Int
    public let maxIntensity: Int
    public let reason: String
}
public enum WorkoutPlanner {
    public static func plan(goal: String?, sessionMinutes: Int?, batteryPercent: Int?,
                            recentSplits: [(date: Date, split: String)], now: Date,
                            calendar: Calendar = .current) -> TrainingPlan
}
```

Rules, in order:

1. Battery 0 to 33 (red) or unknown with a recent hard day: `mobility`, max
   intensity 1, reason "Recovery is low today, so this is a mobility day."
2. Goal `mobility`: `mobility`. Goal `endurance`: `cardio`, intensity capped
   by battery (green 3, yellow 2, red 1).
3. Goal `strength` or `hypertrophy`: rotate `push`, `pull`, `legs` by the
   most recent of those three in `recentSplits` within 7 days (none: `push`).
   Yellow caps intensity at 2. Reason "You did push on Monday, so today is
   pull." or "First session this week: push."
4. Goal unknown: `full`, intensity by battery, reason "Set a goal for a plan
   built around you."

`minutes` is the preference or 30. The library then filters the catalog to
`split == plan.split && intensity <= plan.maxIntensity && duration within
plan.minutes ± 15` and orders by closeness to the requested length; an empty
result widens to any duration, then to any split with the same goal, and
says so.

`recentSplits` come from `WorkoutRecord`: a new optional `split: String?`
column written by the player screen when a session starts from a video, and
left nil for freeform sessions.

## 5. Screens

### 5.1 Library

`WorkoutLibraryScreen`, pushed from the Fitness segment's training card
(which gains a "Plan today's workout" row) and presented from Begin Activity
through a "Follow a video" button above the picker.

- **Today card** (gradient, `ModuleHue.activity`): the plan's split as the
  title ("Pull day"), the reason, the battery and target line from the
  readout vocabulary ("Battery 67% · up to zone 4"), and the minutes.
- **Filter chips:** split (defaulting to the plan), duration bands (under
  20, 20 to 40, over 40), equipment from the preference.
- **Video rows:** thumbnail (AsyncImage from i.ytimg.com, 16:9, 22 point
  radius), title on two lines, channel, duration, intensity dots, split and
  equipment chips. Tap opens the player.
- Empty states as in 3.3.

### 5.2 Player, portrait

`VideoWorkoutScreen`:

- A `WKWebView` at the top, 16:9, loading
  `https://www.youtube-nocookie.com/embed/<id>?playsinline=1&rel=0&modestbranding=1`
  with `allowsInlineMediaPlayback`, `mediaTypesRequiringUserActionForPlayback
  = []` so the person's tap on the YouTube play button is the only gesture
  needed. No JavaScript bridge in this slice.
- Under it, the `SessionHUD` (with the timer) and, before Start, the video's
  title, channel and duration with a "Start this workout" primary button.
  Start calls `recorder.start()` with `selection` mapped from the split
  (strength splits and arms, chest, back, shoulders, core: `.strength`;
  cardio: `.other`; mobility: `.yoga`) and stamps `split` and `videoID` on
  the record when it finishes.
- After Start, the controls from Begin Activity (pause, finish, discard)
  appear under the HUD, and the reps and set controls from slice 2 for
  strength.
- `ActivityRecorder` gains `pendingVideoID: String?` and `pendingSplit:
  String?` that `saveFinished()` writes to the new `WorkoutRecord` columns
  `videoID: String?` and `split: String?`.

### 5.3 Player, landscape

Shiv chose the overlaid capsule. The player fills the screen; the collapsed
HUD capsule floats at the top leading edge with 16 points of inset,
`showsTimer: true`, at most 44 points tall, and never expands in landscape
(a tap shows the controls sheet instead). The top edge is the region
farthest from YouTube's control bar and its bottom-right branding, which is
what the terms name. Risk recorded: if YouTube flags the overlay, the
fallback is a side rail, which the layout keeps as a code path behind one
flag (`VideoWorkoutLayout.landscapeOverlay`).

### 5.4 Fitness segment and Begin Activity

- The training card gains a tappable row "Plan today's workout ›" with the
  planner's split and minutes.
- Begin Activity's pre-session state gains "Follow a video" above the
  activity picker, which pushes the library inside the same sheet.
- A workout started from a video shows its title under the hero on the
  in-session screen ("Following: 30 Min Pull Day · Caroline Girvan").

## 6. Data flow

1. Library appears: `WorkoutLibraryViewModel.attach(context)` reads
  `CatalogVideo` rows and `UserGoals`, computes the plan from the last 7 days
  of `WorkoutRecord.split`, and today's battery from the same
  `CapacityMath` inputs the recorder uses (via a small shared
  `CapacityInputs.today(from: MetricsStore)` helper extracted from the
  recorder's `loadCapacity()`).
2. If the cache is older than a day, `WorkoutCatalogClient.videos` runs and
  upserts; the list updates in place.
3. Player Start: the recorder runs exactly as from Begin Activity.
4. Finish: the record carries `videoID` and `split`; the Fitness segment's
  workout rows show the split chip when present.

## 7. Testing

Swift Testing:
- `SectorsTests/WorkoutPlannerTests`: every rule in 4.2, including the
  rotation with mixed dates, the 7 day window, red battery override, unknown
  goal, and the minute default.
- `IntegrationsTests`: `WorkoutCatalogClient` wire decoding from a fixture
  JSON, including array columns and a row with an unknown split (kept as
  text).
- `PersistenceTests`: `CatalogVideo` upsert idempotence; `WorkoutRecord`
  new columns decode as nil on an old store.

Backend: a Deno test for `scripts/catalog/verify.sh`'s parsing (title prefix
match and duration tolerance) against a fixture oEmbed response.

Design QA in `docs/design/workout-library/`: library light and dark on iPhone
and iPad, the player portrait before and during a session, the player
landscape with the capsule, and the empty and offline states.

## 8. Risks and open checks

- **Overlay and YouTube's terms** (5.3): recorded, with a side-rail fallback
  behind a flag.
- **Embed playback in a web view** may show "Video unavailable" for videos
  whose owners disable embedding. The verify script cannot see that flag
  through oEmbed; the seed list is spot-checked by playing five videos on a
  device before merge, and the player shows an "Open in YouTube" link when
  the embed fails to load.
- **Curation quality** is a human judgement. The seed is a starting set;
  adding a row is a migration and a verify run, nothing else.
- **Catalog freshness**: a deleted or privated video stays in the cache
  until the next daily refresh removes rows absent from the server.
