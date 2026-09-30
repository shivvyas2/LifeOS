# Watch activity HUD verification

September 30, 2026. Branch: `codex/watch-activity-hud`.

## Delivered

The Watch now opens with colored activity tiles and a complete activity picker.
Badminton/racket sports have a court motif; distance workouts, strength and
mind/body activities adapt their metrics. Overview, recent heart-rate readings
and controls are separate swipeable, scrollable pages. Orange native glass
buttons keep the app's action color. The small-screen overview keeps active time,
BPM and calories visible together.

Watch-owned workouts run without the phone and save to Apple Health. A linked
account gets a durable final-summary outbox, background WatchConnectivity delivery,
receipt after database save and idempotent import. An unlinked standalone Watch
can still record, but its workouts remain in Health; it does not silently assign
old workouts to the next account that links.

The phone can start the Watch workout, pause/resume, edit reps/sets, and finish or
discard it. It now waits for the primary session's state instead of pretending a
failed remote command worked. Watch starts and state changes appear on the phone
through the existing HealthKit mirroring path. Disconnected paused time is
reconciled against the primary clock on reconnection.

Account binding is separate from expiring widget snapshots. Account switches
clear old-account queued summaries; final imports validate the owner before
reading or writing the account database. Stable IDs also reconcile a phone save
that happens before the first identity packet arrives.

## Evidence

- Xcode 26.3; iOS/watchOS deployment target 26.0.
- iPhone app and embedded Watch app: simulator build succeeded, arm64.
- Focused Swift package tests: **18 passed** in five suites. Covers account
  ownership, sign-out ordering, durable round trip, invalid summaries, repeated
  delivery, early phone-save reconciliation, primary-clock pauses and packet
  compatibility.
- Native recorder harness: **45 PASS, 0 FAIL** on the isolated
  Almanac-Surfaces-iPhone simulator (iOS 26.2). Full output: `recorder-checks.txt`.
  Added stale-packet and disconnected pause/finish checks. Existing workout,
  library-video attribution, rep counting, draft recovery and account-transition
  checks remain passing.
- WatchOS 26.2 simulator screenshots, 416 × 496 pixels:
  `badminton.png`, `launcher.png`, `strength-controls.png`, `run-metrics.png`.
  These use explicitly selected DEBUG fixtures, not measured health data.
- Initial capture exposed an oversized hero tile. Reduced the icon, timer,
  court and tile padding so both numeric metric tiles fit the initial viewport.
- `git diff --check` passed.

The Watch previews were launched by the simulator fixture route and visually
inspected. Native interaction automation could not obtain a screen capture from
the desktop computer-use service, so this is not a claim of end-to-end physical
button or sensor testing.

## Remaining hardware checks

Physical Watch validation is still required for live BPM/distance, wrist rep
accuracy, locked/background recording, permission prompts, and two-way commands
through a real Bluetooth disconnection/reconnection. Verify an offline finish
appears once after reconnecting, and an account switch does not import the prior
account's pending workout. A simulator cannot establish those hardware behaviors.

No claim of watchOS 27 runtime testing; no App Store release or remote deployment.
The repository's existing YouTube library remains in place and was not redesigned
in this change. The current main checkout's unrelated DI refactor was preserved.

## Platform references

- [Apple: Building a multidevice workout app](https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app)
- [Apple: Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)

## Activity glass gradients (September 30 follow-up)

Replaced the flat tint-to-black tiles with a dark translucent base, two colored
reflections, a soft upper highlight and a directional glass rim. Workout pages
now sit above a black-to-color ambient gradient with a pale reflected lower edge,
inspired by the new blue gradient reference. The launcher uses the same glass
surfaces with each activity's own palette.

Running uses cobalt/ice blue; badminton and racket sports use jade/lime;
walking uses teal/seafoam; cycling uses amber; strength uses violet/orchid;
mind/body uses mint; water activities use blue/aqua; outdoor activities use
slate/ice; dance uses rose. Orange action accents and existing typography remain.

These are static SwiftUI gradients. Always On removes the bright reflections and
ambient glow; Reduce Transparency uses an opaque card base and black screen
backdrop; Increase Contrast strengthens the card edge. Workout/sync logic is
unchanged. Watch simulator build passes, and `git diff --check` passes.
New sample-data captures: `run-glass.png`, `badminton-glass.png`,
`strength-glass.png`.
