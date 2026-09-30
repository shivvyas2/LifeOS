# Activity-specific Watch app

The Watch owns its workout and writes it to Apple Health. An iPhone is optional
for recording. Linking the phone account enables Almanac history sync; a first
standalone installation records to Health without silently claiming an account.

## Interface

- Dark, colored metric tiles with restrained glass borders and native watchOS 26
  glass controls. Shared system typography, orange action accents.
- Badminton and other racket sports use a court motif, active timer, BPM,
  calories and estimated HR zones. No fabricated strokes, scores or HR samples.
- Distance activities use actual builder distance and average pace/speed.
- Strength uses existing on-device wrist estimates and editable reps/sets.
- Mind/body activities use a calmer mint duration view, without exertion zones.
- Swipe between overview, recent heart-rate readings and controls. Each page
  scrolls for small displays and larger text. An end confirmation avoids a
  stray tap finishing a session.
- Missing/stale readings use a dash. Reduced luminance dims surfaces; reduced
  transparency uses an opaque base. Native glass remains on interactive controls.

## Recording and transport

- Preserve HealthKit workout mirroring for live control in both directions.
  Phone pause/resume/finish awaits primary state, rather than inventing success.
- Retry failed initial mirroring while the primary session continues. Send
  primary elapsed time to reconcile pauses during phone disconnection.
- Persist a lightweight session checkpoint for identity and rep recovery; use
  builder.elapsedTime on recovery. Never store raw motion samples.
- Write final results to a Watch outbox before handing them to WatchConnectivity.
  Transfer user info supports background delivery. Phone saves by stable UUID,
  validates account ownership, and acknowledges only after the database saves.
- Keep account binding separate from the six-hour widget snapshot. Widget data
  expiry cannot terminate a workout or accidentally unbind an offline user.
- Binding changes discard an old account's active recording and queued app
  summaries. Old queued packets cannot restore a newer signed-out binding.
- A workout started with no linked account remains Health-only. Linking an
  account does not retroactively assign personal history to that account.

## Validation boundaries

Build against the installed Xcode 26.3 SDK and watchOS 26 deployment target.
Use Watch simulators for layout, package tests for clocks/import/ownership.
Physical Watch tests remain necessary for sensors, motion accuracy, mirroring,
background collection and Bluetooth reconnection. No iOS/watchOS 27 runtime
compatibility claim is made without that SDK and hardware.
