# Watch companion design QA

Final result: passed, with five hardware checks and one recovery-behaviour
check still pending on Shiv's iPhone and watch.

## Source and scope

- This slice adapts the existing native recorder, Live Activity and HUD onto
  a session the Apple Watch can own and run: a rep counter built from wrist
  acceleration, a `WatchConnectivity`/`HKWorkoutSession` mirroring bridge, and
  a new watch workout screen. There is no external visual reference; the spec
  (`docs/superpowers/specs/2026-09-14-watch-companion-design.md`) is the
  source of truth for wire format, ownership rules and layout.
- Native SwiftUI on both targets (`LIfeOS` and `AlmanacWatch`). Shared
  typography, module colors, SF Symbols and the app's existing card/pill/HUD
  vocabulary are reused; no new illustrations or iconography were introduced.
- State: captures were taken from the design-preview fixture
  (`HealthActivityDesignPreview.swift`), which drives a fixed WHOOP recovery
  and a live sensor reading and, for these captures, appends two manual
  `addRep()` calls, a `nextSet()`, and one more `addRep()` so the strength
  fixture ends at set 2, 1 rep. No account data was loaded.

## Evidence and normalization

- iPhone: 1206 x 2622 pixels, native 402 x 874 points, 3x, simulator
  `FC3C3AD5-CD98-4C7C-83AA-5E02587E6E68` (iPhone 17, iOS 26.0), in
  `docs/design/watch-companion/`:
  - `session-strength-iphone.png` -- launched with
    `--design-preview --page=activity --live --strength`. The HUD capsule
    reads "1 reps", the Reps tile reads "Set 2" with value "1 reps" and
    caption "Sets so far: 2".
  - `session-strength-lock-screen.png` -- same fixture relaunched with
    `--live-activity` added, then locked. The lock-screen card shows
    "Strength - Easy going" and tile three reading "SET 2 / 1".
- No watch-side screenshot exists: the watch simulator cannot run a real
  `HKWorkoutSession`, so `WatchWorkoutScreen` is verified by compilation only
  (task 5's report), not by capture.

## Findings and comparison history

One deviation per task, from each task's own report:

1. **Task 1** (wire types, reps on the readout): no deviations from the
   brief.
2. **Task 2** (`Motion`/`RepCounter`): the brief's algorithm was wrong twice,
   not a transcription error. First pass rectified the signal
   (`sqrt(x^2+y^2+z^2)`) so a fall crossing could structurally never follow a
   rise; the controller's fix (projecting the fast/slow difference onto the
   first lift's axis) fixed that but still locked the axis onto a fading
   swing when settling ended mid-cycle, undercounting by exactly one rep in
   two of six tests. The shipped fix tracks the difference magnitude before
   the settle guard and only locks the axis on a still-rising swing; spec
   section 4.2 and the `oneSlowPushCountsNothing` test signal (now 0.1 Hz,
   12 s) were both rewritten to match.
3. **Task 3** (source/reps/sets in the recorder): the brief's checks snippet,
   inserted verbatim, regressed the pre-existing "Repeated save creates one
   workout" check because the new strength check's row was left in the
   shared context; fixed by deleting that row after asserting on it, per the
   "fix the cause, never the check" rule.
4. **Task 4** (`WatchSessionBridge` and the phone hand-off): `handoff:
   Task<Void, Never>?` was dropped as dead state (nothing reads it), the
   bridge teardown call landed in `AccountSession.swift` rather than
   `RootView.swift` per the task's own correction, and the packet-refresh
   guard added `&& isRunning` so a paused packet with a reading still
   refreshes once instead of zero times. The review's fix wave separately
   found the fallback check as literally worded would hang the page behind a
   live Health-access sheet, so the check grants `saveToHealth` only long
   enough to exercise the gate before removing it again.
5. **Task 5** (watch target, controller, screen): nine small deviations, the
   two most consequential being a wrong delegate selector
   (`didReceiveDataFromRemoteDevice` instead of the SDK's
   `didReceiveDataFromRemoteWorkoutSession`, silently uncalled because the
   requirement is `@optional`) and `Menu` being unavailable on watchOS
   (replaced with a sheet-presented `List`). The review's fix wave separately
   found a critical bug where an automatic rep overwrote a manual `+1` tap;
   fixed by tracking manual and automatic reps separately and summing them.
6. **Task 6** (reps and sets on phone surfaces): fixed the task 5 delegate
   selector typo on the phone side (so watch packets actually reach the
   recorder) and touched `WatchWorkoutScreen.swift`, outside the brief's file
   list, to render the "Not connected to iPhone" caption that task 5's
   `mirroringFailed` fix required but nothing rendered.

## Required fidelity surfaces

- **Rep counter constants in force**
  (`LifeOSKit/Sources/Motion/RepCounter.swift`):
  `settleSeconds: 1.0`, `minPeriod: 0.6`, `maxPeriod: 4.0`, `threshold: 0.15`,
  plus the two internal smoothing constants `fastTau: 0.15` and
  `slowTau: 2.0`. A rep is a signed swing along the locked lift axis: a rise
  above `threshold` followed by a fall below `-threshold`, the half cycle
  between them between `minPeriod / 2` and `maxPeriod / 2` seconds, with a
  `minPeriod / 2` refractory window after each counted rep.
- **Calibration cases the tests pin** (`RepCounterTests.swift`, 50 Hz
  synthetic samples, vertical axis only):
  - `tenSlowCurlsCountTen`: 2 s of quiet settling then ten cycles at 1 Hz,
    amplitude 0.4, noise 0.05 -> 10 reps.
  - `tinyMovementCountsNothing`: 1 Hz, amplitude 0.08, noise 0.02, 12 s -> 0
    reps (below threshold).
  - `fastJitterCountsNothing`: 3 Hz, amplitude 0.4, noise 0.05, 12 s -> 0 reps
    (half cycle shorter than `minPeriod / 2`).
  - `oneSlowPushCountsNothing`: one 10 s cycle, 0.1 Hz, amplitude 0.5, noise
    0.02, 12 s -> 0 reps (half cycle longer than `maxPeriod / 2`).
  - `settlingSwallowsTheFirstSecond`: 1 Hz, amplitude 0.4, noise 0.05, 9 s,
    cycles starting at t=0 -> 8 reps (the first second is swallowed by
    `settleSeconds`).
  - `resetStartsOver`: 2 s quiet then 5 s at 1 Hz -> 5 reps; `reset()`; then
    3 s at 1 Hz -> 2 reps.
- **Typography/spacing/color/copy**: unchanged from the live-session slice
  this builds on (`docs/design/live-session/report.md`); this slice adds a
  "reps" HUD slot, a Reps tile, a Set N / M reps row on the Dynamic Island
  and lock screen, and an Apple Watch connection line, all in the app's
  existing type roles, card/pill styling, and SF Symbols. No illustrations or
  invented copy were introduced; "auto" and "+1" are the only new interface
  strings, both from the spec.

## Interaction and test evidence

- `swift test` total (`LifeOSKit`, this run): **1245 tests in 163 suites
  passed**, 0 failures.
- Native app build (`xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,
  OS=26.0' build`): `** BUILD SUCCEEDED **`.
- Watch app build (`xcodebuild -project LIfeOS.xcodeproj -scheme
  AlmanacWatch -destination 'generic/platform=watchOS Simulator' build`):
  `** BUILD SUCCEEDED **`.
- Checks harness output (`--design-preview --page=checks`, clean install,
  iPhone 17 simulator `FC3C3AD5-CD98-4C7C-83AA-5E02587E6E68`, pasted
  verbatim, 23 of 23 PASS, no FAILs):

```
PASS: Timer starts without Health access
PASS: Capacity comes from today's recovery at start
PASS: Readings yield zone and effort
PASS: A phone strength session starts at set 1 with zero reps
PASS: Manual reps and sets count on the phone
PASS: A packet with an unknown version changes nothing
PASS: Finishing writes the sets, current set included
PASS: A watch that does not answer falls back to the phone
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
PASS: Account transition stops recording and rejects late starts
```

## Hardware checks: pending

No physical iPhone or Apple Watch is reachable from this environment. The
five checks spec section 8 requires are recorded here as pending, with the
exact steps to run them:

1. **Watch launch and heart rate hand-off, pending.** Start from the phone
   and see the watch launch and the phone HUD show watch heart rate within
   10 seconds.
2. **Watch-started session, pending.** Start from the watch and see the
   phone Live Activity appear.
3. **Rep accuracy, pending.** Do 10 slow bicep curls on the watch and
   compare the auto count against the actual count.
4. **Pause propagation, pending.** Pause on the watch and see the phone
   pause.
5. **Single save, pending.** Finish the workout and find exactly one workout
   in Health.

To be run by Shiv on the iPhone and watch when both are available.

## Residual test gaps

- **`recoverActiveWorkoutSession` behaviour for a mirrored session is
  unverified.** Spec section 9 flags this as open: whether a phone relaunch
  during a watch-owned session returns the mirrored session through
  `recoverActiveWorkoutSession` is unknown until run on hardware. The task 4
  recovery branch (`attach`'s `source == .watch` path) hands anything
  returned to `WatchSessionBridge.shared.adopt(_:)`; if nothing is returned,
  the documented fallback is that the recorder persists and waits for the
  mirroring handler to re-attach on the watch's next packet.
- The five hardware checks above are unverified in this environment; only
  the fall-back path (no paired watch) is exercised by the simulator checks.
- The watch's own screen (`WatchWorkoutScreen.swift`) is verified by
  compilation only; no watch-simulator or hardware capture exists.
- iOS 27 and unannounced device configurations have not been runtime-tested;
  only iOS 26.0 simulators were used.

Final result: passed
