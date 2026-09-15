# Workout library design QA

Final result: passed

## Source and scope

- This slice adds a curated catalog of YouTube workout videos, a planner
  that picks today's split and length from recovery and rotation, a library
  screen to browse and filter the catalog, and a player screen that plays
  the video behind the existing live HUD. There is no external visual
  reference; the spec (`docs/superpowers/specs/2026-09-14-workout-library-design.md`)
  is the source of truth for layout, copy and the catalog table.
- Native SwiftUI implementation built from the app's existing vocabulary:
  `GradientCanvas`, `SoftCard`, chip rails, `SessionHUD` and
  `ActivityControls` (the last two moved out of Begin Activity so the
  player can reuse them, not duplicated). No illustrations or invented
  iconography were introduced.
- State: the design-preview fixture (`HealthActivityDesignPreview.swift`)
  drives every capture, using six real rows lifted from the shipped seed
  migration (not invented ids, which resolve to YouTube's grey placeholder
  image) and a seeded WHOOP recovery/live sensor reading for the player's
  in-session state. No account data was loaded.

## Evidence and normalization

- iPhone: 1206 x 2622 pixels, native 402 x 874 points, 3x.
  `library-iphone.png`, `library-iphone-dark.png`, `library-empty.png`,
  `player-portrait.png`, `player-portrait-live.png` in
  `docs/design/workout-library/`.
- iPad: 1668 x 2420 pixels, native 834 x 1210 points, 2x. `library-ipad.png`.
- `library-iphone.png`: Today card reads "Pull day", "You did push on
  Saturday, so today is pull.", "Battery 83% · up to zone 5"; the Pull chip
  is selected among the split/duration/equipment chip rail; four visible
  rows show real thumbnails, title, channel, minutes, intensity dots and
  split/equipment chips.
- `library-iphone-dark.png`: the same Today card, chip rail and rows render
  in dark mode with the cards and chips staying visually separate from the
  canvas.
- `library-ipad.png`: the wider layout shows the equipment chips
  ("Dumbbells", "Bands") that scroll off the phone width, and long titles
  fit on one line.
- `library-empty.png`: the Today card still stands; the empty state shows a
  `wifi.slash` glyph and "The library needs a connection the first time."
  with the message not repeated above the list.
- `player-portrait.png`: before Start, showing the video's real poster,
  title bar and YouTube's own play button, an "Open in YouTube" link under
  the player, then the title, channel, duration, and the split/intensity/
  equipment chips above a "Start this workout" button.
- `player-portrait-live.png` (**recaptured after the final-review fixes**):
  the same poster, then `12:13` on its own monospaced line under "Elapsed
  time", then the HUD capsule reading a green heart at 152 bpm, effort 3.5
  `est`, battery `67%` and `1 reps`, over Pause, Finish & save and Discard.
  Nothing truncates: moving the timer out of the capsule (the Begin Activity
  hero's precedent) gives the five readings the width they need, and the
  battery percentage, the one reading that must never be half a number, now
  reads in full.
- **`player-landscape-live.png`: pending, not captured.** The app is
  portrait-only (`INFOPLIST_KEY_UISupportedInterfaceOrientations` in
  `project.pbxproj` is `UIInterfaceOrientationPortrait` only), so rotating
  the simulator device leaves the app rendering portrait; two attempts both
  came back 1206x2622 and the bogus file was discarded rather than
  committed as a landscape capture. Spec section 5.3 already records this:
  "The app is portrait-only on iPhone today; this layout is reachable only
  once the iPhone app allows rotation, which is a separate product
  decision." The
  landscape capsule's 16-point inset and 44-point height cap are therefore
  unverified in a real landscape render; they are exercised only by the
  `landscapeOverlay` flag's code path and the phone's existing
  `verticalSizeClass` plumbing.

## Embed spot-check

Spec section 8 requires spot-checking the seed videos on a device before
merge, since the verify script's oEmbed check cannot see an owner's
"disable embedding" flag. Six ids were checked with
`--design-preview --page=player --video=<id>` on the simulator, network up:

| id | first pass | after the origin fix |
| --- | --- | --- |
| `ifVk1E5My7M` | error 152 | poster and play button |
| `aFnUKszjprs` | error 152 | poster and play button |
| `3pHz96dv8dE` | error 152 | poster and play button |
| `KqZG-vlcYhg` | error 152 | poster and play button |
| `BoTAfri7Bec` | error 152 | poster and play button |
| `1fahiYJIYgI` | error 152 | poster and play button |

Zero of six rendered on the first pass; every id gave YouTube's "This video
is unavailable, Error code: 152 - 4" card. Root cause, found by
elimination: loading the embed URL directly gave the harder error 153 on
every id (mobile Safari on the same simulator did too, ruling out app code);
wrapping the embed in an iframe on a page of our own moved every id from 153
to 152; the fix was matching the query's `origin` parameter to the page's
own `baseURL` and pointing both at `youtube-nocookie.com` instead of
`youtube.com`. After that fix, all six ids render YouTube's poster, title
bar and play button: six of six, up from zero of six. `player-portrait.png`
and `player-portrait-live.png` above were recaptured after this fix and show
the working state.

## Required fidelity surfaces

- **Typography:** one system sans family throughout; the Today card,
  chip rail, row titles, player title/channel/duration and the HUD's
  numeric readouts all use the app's existing type roles. No separate
  face was introduced for the library or player.
- **Spacing/layout:** existing card and pill padding and corner radii;
  the chip rail keeps intensity dots and chips on separate lines after an
  early capture showed a chip truncate to "Dum…" when sharing a line with
  the dots; the row thumbnail is 16:9 at 128 points wide in a 22-point
  rounded rectangle. The player keeps the existing `SessionHUD` and
  `ActivityControls` layout unchanged from Begin Activity.
- **Colors/tokens:** activity hue on the canvas and Today card; chip
  capsules were fixed from an invisible white-on-white to the canvas tone
  after an early capture showed them disappear on the card. The HUD keeps
  its existing green "on track" tint and orange action buttons.
- **Images/icons:** real YouTube thumbnails load through `AsyncImage`; the
  placeholder tile (activity pastel plus `play.rectangle.fill`) is only
  exercised when the network is down, since the fixture uses real seed
  ids rather than invented ones. Native SF Symbols (`wifi.slash`,
  `play.rectangle.fill`) provide the interface icons used.
- **Copy:** "Pull day", "You did push on Saturday, so today is pull.",
  "Battery 83% · up to zone 5", "The library needs a connection the first
  time.", "Open in YouTube" and "Start this workout" are the real strings
  the fixture and the live catalog render. No placeholder or lorem-ipsum
  text appears in any capture.

## Per-task deviations

- **Task 1** (catalog table, verify script, seed): the handed-off 119-row
  catalog did not actually meet its own coverage claim once verified
  against live oEmbed; 76 rows had a channel-name typo, 30 rows had a
  paraphrased title, and 11 rows claimed a shorter length in the title
  than their real duration. Fixed the 76 and 30 mechanically, trimmed 2
  titles to a true prefix, and removed 9 rows with no fixable prefix,
  landing at 110 of 119 with `lower` and `core` under their coverage
  floors. A follow-up commit (`a0a8dbd`, twelve more verified videos for
  core, lower, arms and full) closed that gap; the catalog now ships at
  122 rows with every split at or above its floor.
- **Tasks 2-4** (persistence, catalog client, planner): no deviations in
  persistence or the client. The planner needed one fix not in the brief's
  snippet: `Calendar.weekdaySymbols` resolves through the calendar's
  locale, and this sandbox's default calendar has a fixed empty locale
  that returns abbreviated weekday names. Pinned a copy of the calendar to
  `en_US_POSIX` only for the weekday-symbol lookup so the planner's reason
  string is deterministic regardless of the host's default locale.
- **Task 5** (shared capacity inputs): `CapacityInputs.todayCapacity`
  needed an explicit `@MainActor` not shown in the brief, because
  `MetricsStore.metrics(from:to:)` is main-actor isolated in this
  codebase; a strict superset of the brief, no behavior change.
- **Task 6** (library screens): several interface members
  (`equipmentFilter`, `equipmentOptions`, `capacity`, `isRefreshing`,
  `load()`, and others) exist beyond the brief's named list because
  section 5.1's equipment chips and preferences sheet need them; `onOpen`
  is optional rather than required so the one in-screen navigation
  destination stays the single line Task 7 swapped for the real player.
  Two layout bugs found in captures were fixed before commit: invisible
  white-on-white chip capsules, and intensity dots truncating a chip on
  a shared line.
- **Task 7** (player and HUD): the brief's direct embed-URL load fails
  with error 153 on every video; ships wrapping the embed in an iframe on
  a page of the app's own, with an `origin` parameter matching the page's
  `baseURL`, both pointed at `youtube-nocookie.com` (see "Embed
  spot-check" above). The landscape capsule adds `.clipShape(Capsule())`
  alongside `.frame(maxHeight:)` because `SessionHUD` sets its own
  `.frame(minHeight: 52)`, which would overflow a 44-point slot without
  clipping; unverified in a real landscape render per the pending capture
  above. A compact Start capsule was added for landscape-before-Start,
  which the spec does not mention, so rotating before Start is not a dead
  end.

## Interaction and test evidence

- `swift test` total (this run, `LifeOSKit`): **1258 tests in 166 suites
  passed**, 0 failures. Task 1's package baseline (before this feature's
  own code landed) was 1242 tests at the end of Tasks 2-4; the difference
  reflects this feature's own tests plus the watch companion branch's
  tests, folded in by the rebase onto `feat/watch-companion` ahead of this
  task.
- Deno test total (`scripts/catalog`): **4 tests passed, 0 failed**
  (`parseCatalog`, `titleMatches`, `durationPlausible`, `rowToSQL`, each
  exercised once).
- Native app build (`xcodebuild ... -destination 'platform=iOS
  Simulator,name=iPhone 17 Pro,OS=26.0' build`): `** BUILD SUCCEEDED **`,
  no errors.
- Checks harness output (`--design-preview --page=checks`, iPhone 17 Pro
  simulator `384ADA00-A63C-48AF-9249-98E367DC8B05`, pasted verbatim, 30 of
  30 PASS, no FAILs; the rebase onto the watch companion branch added the
  watch-packet and watch-draft checks to this same page):

```
PASS: Timer starts without Health access
PASS: Capacity comes from today's recovery at start
PASS: Readings yield zone and effort
PASS: A phone strength session starts at set 1 with zero reps
PASS: Manual reps and sets count on the phone
PASS: A watch packet never reaches a phone session
PASS: Finishing writes the sets, current set included
PASS: The wait for the watch says so
PASS: A watch that does not answer falls back to the phone
PASS: A watch draft restores as a watch session
PASS: A watch draft leaves Health saving on
PASS: A packet with an unknown version changes nothing
PASS: A current-version packet carries reps and heart rate through
PASS: Finishing a watch session writes the local record and its sets
PASS: Health saving off keeps the session on the phone
PASS: Paused readings accrue nothing
PASS: Paused time stays fixed
PASS: Resume keeps the activity
PASS: First reading after resume credits nothing, the second accrues
PASS: Timer-only draft restores without Health recovery
PASS: Draft restores capacity and effort
PASS: Other account cannot see the draft
PASS: Finish saves locally without claiming a Health save
PASS: Repeated save creates one workout
PASS: Saved draft is cleared
PASS: Remembered sensor survives relaunch
PASS: Other account has no remembered sensor
PASS: Forget clears the remembered sensor
PASS: Finishing stamps the video and split
PASS: Account transition stops recording and rejects late starts
```

- Catalog split counts (`scripts/catalog/catalog.json`, 122 rows total):
  push 8, pull 8, legs 15, upper 16, lower 7, full 8, core 5, arms 5,
  chest 4, back 4, shoulders 4, mobility 16, cardio 22. Every split is at
  or above spec 3.2's floor (push/pull/legs/upper/lower/full >= 6;
  core/arms/chest/back/shoulders >= 3; mobility/cardio >= 5).

## Residual test gaps

- **`player-landscape-live.png` is not captured** because the app is
  portrait-only; the landscape capsule's inset and 44-point cap are
  unverified in a real landscape render (see "Evidence and normalization").
- **In-player errors are invisible to the app.** `onLoadFailure` only
  fires when the page itself fails to load; a YouTube error card loads
  with HTTP 200, so the app's own "Open in YouTube" fallback link is
  always shown as a precaution rather than triggered by a detected
  failure. The person is not stranded (YouTube's own card carries its own
  "Watch on YouTube" link), but this needs the JavaScript bridge the spec
  defers before the app can detect an in-player failure itself.
- Real-device embed playback (as opposed to the simulator) has not been
  exercised; spec section 8's device spot-check requirement is satisfied
  by the six simulator checks above, not a physical device.
- iOS 27 and unannounced device configurations have not been
  runtime-tested; only iOS 26.0 simulators were used.
- The migrations (`20260915090000_workout_videos.sql`,
  `20260915090100_workout_videos_seed.sql`) were generated by
  `scripts/catalog/verify.ts` and verified against live oEmbed for all 122
  rows, but **`supabase db push` has not been run**; the controller applies
  them at the finishing step.

## Final review fixes

The read-only final review (`.superpowers/sdd/2026-09-14-workout-library/
final-review.md`) raised seven Important and eleven Minor items. The wave
below landed before merge; the per-item detail is in
`final-fix-report.md` beside the review.

- **Empty response keeps the cache** (Important 1). A successful fetch that
  returns zero rows no longer replaces a full cache; the screen says "The
  catalog came back empty. Showing the last one we downloaded." The rule is
  `Sectors.CatalogRefresh.shouldReplace(cacheCount:incoming:)`, with three
  tests including the empty-cache case, which still returns true.
- **Default grants revoked** (Important 2). `20260915090000_workout_videos.sql`
  now does `revoke all ... from anon, authenticated;` before the `grant
  select`, matching `20260914090000_social_groups.sql`; spec 3.1 says why.
- **The seed is a full sync** (Important 3). `verify.ts` takes `--out`, so a
  curation pass after the first `supabase db push` writes a new timestamped
  migration instead of rewriting one Supabase has already recorded, and every
  generated seed ends with one `delete ... where youtube_id not in (...)`
  naming all 122 verified ids. The seed was regenerated against live oEmbed:
  122 of 122 rows confirmed, the file identical apart from fresh
  `verified_at` timestamps and the new trailing delete.
- **Stale pending video cleared** (Important 4, Minor 15).
  `ActivityRecorder.start(backdatedTo:following:)` owns the video for the
  start that sets it, and clears it when there is none; the three fields are
  in `Draft`, so a session restored after a relaunch mid-video still stamps
  the record.
- **Preferences sheet asked once** (Important 5), decided in `attach` rather
  than in every `load`, so a Health sync no longer re-raises it after Cancel.
- **Split chip on the Fitness rows** (Important 6, spec 6 step 4).
  `WorkoutSummary` carries `split`; `WorkoutRow` shows it capitalised.
- **HUD no longer clips** (Important 7). The player renders the elapsed time
  as its own `TimelineView` line above the capsule and passes
  `showsTimer: false` and `countsAutomatically: model.source == .watch` at
  both `SessionHUD` call sites. Recaptured: see `player-portrait-live.png`
  above.
- **Video ids validated** (Minor 8) against `^[A-Za-z0-9_-]{11}$` before
  interpolation; a row that fails shows "This video will not play here."
- **Dead landscape rail deleted** (Minor 9); the overlay stays behind
  `VideoWorkoutLayout.landscapeOverlay`, whose off branch is now the portrait
  stack, a layout this report actually captured.
- **Filtering is pure and tested** (review recommendation 3). The widening
  rule moved to `Sectors.WorkoutLibraryFilter.apply`, with four named tests
  including "an explicit split chip is not widened away" (Minor 13). Minor 12
  and 14: the refresh notice is shown alongside a widening note rather than
  hidden by it, and a signed-out person is told "Sign in to download the
  library." Minor 16: `CatalogStore.upsert` can no longer trap on a duplicate
  id. Minor 18: spec 5.3 now says "portrait-only on iPhone".

New counts after the wave:

- LifeOSKit: **1266 tests in 168 suites, all passing** (was 1258 in 166; the
  new suites are `CatalogRefreshTests` with 3 and `WorkoutLibraryFilterTests`
  with 5).
- `scripts/catalog`: **6 Deno tests, all passing** (was 4; `channelMatches`
  and `seedSQL` each gained one).
- Recorder checks page on the iPhone 17 Pro simulator: **32 of 32 PASS** (was
  30), the two new ones being "A failed start does not stamp the next
  session" and "A restored draft keeps its video".
- App build: `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone
  17 Pro,OS=26.0'` **BUILD SUCCEEDED**.

New capture: `player-portrait-live.png`, retaken on the iPhone 17 Pro
simulator (1206 x 2622, 402 x 874 points at 3x) after the HUD change, read
back and confirmed clip-free.

Final result: passed
