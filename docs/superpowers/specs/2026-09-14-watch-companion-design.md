# Apple Watch companion: the watch runs the workout, the phone shows it

**Date:** 2026-09-14
**Status:** implemented on feat/watch-companion, see docs/design/watch-companion/report.md
**Builds on:** `2026-09-14-live-session-core-design.md` (the readout, the
effort model, the HUD, the Live Activity, the recorder's draft),
`docs/design/widgets-watch/` (the watch dashboard and its WatchConnectivity
bridge).

**Followed by:** slice 3, the workout library, which reuses everything here.

## 1. The problem

Almanac records a workout on the phone. Heart rate arrives only from a
Bluetooth strap, so a person wearing an Apple Watch and no strap sees a
timer and no beats. Strength sessions show a "reps" slot that never fills.
The watch app is a read-only dashboard: it cannot start, see, or end a
workout.

Three concrete gaps:

1. No workout session runs on the watch, so the watch's heart rate and energy
   never reach the live readout.
2. Nothing counts reps. The HUD reserved the slot in slice 1.
3. The phone-to-watch channel carries one message shape, the dashboard
   snapshot, and cannot express a session.

## 2. What this slice delivers

| Area | Change |
|---|---|
| Ownership | When a watch is paired, installed and reachable, the watch owns the HealthKit workout session and mirrors it to the phone. Otherwise the phone path from slice 1 runs unchanged. |
| Readings | Heart rate, energy, reps and set index travel from watch to phone over the mirrored session's data channel once a second and instantly on a rep. Pause, resume, end and next set travel back. |
| Reps | A pure, tested rep counter on wrist motion, strength sessions only, labelled "auto", with manual +1 and Next set on both devices. Sets are saved on the workout record. |
| Watch screen | A minimal workout screen: timer, heart rate, reps and set for strength, pause and end. |
| Surfaces | Reps and set reach the readout, the HUD, the in-session tiles and the Dynamic Island. |

Out of scope: rep counting for anything but strength, exercise recognition
(which movement), watch complications for the workout, the workout library
(slice 3), camera-based counting.

## 3. Session ownership

### 3.1 Choosing the source

The hand-off is offered only when this workout is meant for Health
(`saveToHealth`): the watch writes the workout to Health itself, so a person
who turned that off keeps the phone path. Given that, `ActivityRecorder.start()`
asks `WatchSessionBridge.watchAvailable` (built from `WCSession.default`):
`activationState == .activated && isPaired && isWatchAppInstalled`. Not
`isReachable`: on iOS that is true only while the watch app is already in the
foreground, which is never so for a person tapping Begin on the phone.
`startWatchApp(toHandle:)` exists to launch it, and the ten second timeout
below already covers a session that never starts.

Before the watch is asked, the phone requests its own Health authorization for
the workout types (the same set the phone session requests). Authorization is
shared with the paired watch, so this keeps the very first permission prompt on
the phone rather than on the wrist while the phone counts down. If it is
refused, the hand-off is skipped and the phone path runs.

- **Watch available:** the phone calls
  `HKHealthStore.startWatchApp(toHandle: configuration)` with the activity
  type and waits up to 10 seconds for the mirrored session to arrive through
  `HKHealthStore.workoutSessionMirroringStartHandler`. The phone creates no
  session of its own, and shows "Asking your Apple Watch…" while it waits. If
  nothing arrives in 10 seconds, the recorder falls back to the phone path and
  says "Apple Watch did not answer. Recording on iPhone."
- **Watch not available:** the slice 1 phone path, unchanged.
- **Started on the watch:** the watch app's own Start button runs the same
  session and mirrors it; the phone's mirroring handler creates the recorder
  session on arrival, so the phone HUD and Live Activity appear without any
  tap on the phone. The phone app is launched in the background by HealthKit
  for this, with no scene and so no recorder: the bridge's mirroring handler
  therefore requests the Live Activity itself when no recorder is listening,
  keeping its session id in `placeholderSessionID`. The recorder's timer takes
  that id when it adopts the session, so the activity already on screen is
  updated rather than duplicated.

The recorder records its choice as `source: SessionSource` (`.phone`,
`.watch`) in the draft. A restored draft with `.watch` asks
`HKHealthStore.recoverActiveWorkoutSession` first; whether that returns a
mirrored session on the phone is an open check (section 9). If it returns
nothing, the recorder keeps the timer and waits for the next
`WatchPacket`, which the watch keeps sending while its session runs; the
mirroring handler re-attaches the session when HealthKit relaunches the
phone app.

### 3.2 What each side does

**Watch (`WatchWorkoutController`, new, in the watch target):**
- Creates `HKWorkoutSession` and `HKLiveWorkoutBuilder` with
  `HKLiveWorkoutDataSource`, starts the activity, begins collection, then
  calls `startMirroringToCompanionDevice`.
- On builder statistics, keeps the latest heart rate and the energy sum.
- For strength, runs the rep counter (section 4) on device motion.
- Sends a `WatchPacket` (section 3.3) at most once a second, and immediately
  when reps change.
- Receives `PhoneCommand`s: pause, resume, end, discard, next set, manual rep.
  Applies them to the session and the counter.
- On end, ends collection and `finishWorkout()`; the watch saves to Health.
  The phone does not save to Health for a watch-owned session, so nothing is
  saved twice.
- On discard, stops motion, detaches the delegates, `discardWorkout()` and
  ends the session without finishing it, so nothing reaches Health. The phone
  sends `discard` when it refuses a mirrored session (it is already recording)
  and when the person discards the activity there; `end` means save, and
  sending it in those cases would leave a stub workout on the wrist.

**Phone (`WatchSessionBridge`, new, in the app target):**
- Installs `workoutSessionMirroringStartHandler` at app launch (in the app
  delegate, alongside push setup), stores the mirrored session, sets itself
  as its delegate, and hands the session to the recorder.
- Decodes `WatchPacket`s from `workoutSession(_:didReceiveDataFromRemoteWorkoutSession:)`
  and forwards them to `ActivityRecorder.receiveWatchPacket(_:)`.
- Sends `PhoneCommand`s with `sendToRemoteWorkoutSession(data:)`.
- Mirrors session state changes from the delegate into the recorder's timer,
  as the phone session delegate does today.

### 3.3 Wire format

Both types live in `AppSurfaces` (Foundation only, so the watch target links
nothing new) and are `Codable`, versioned by a leading `v: Int`:

```swift
public struct WatchPacket: Codable, Equatable, Sendable {
    public var kind: String = "packet"   // names the shape for the decoder
    public var v: Int = 1
    public var sentAt: Date
    public var heartRate: Int?
    public var heartRateAt: Date?
    public var energyKcal: Double?
    public var reps: Int?          // reps in the current set, nil when not strength
    public var setIndex: Int?      // 1-based
    public var completedSets: [Int]? // reps per finished set
}
public enum PhoneCommand: String, Codable, Sendable { case configure, pause, resume, end, nextSet, addRep, discard }
public struct PhoneCommandEnvelope: Codable, Sendable {
    public var kind: String = "command"
    public var v: Int = 1
    public var command: PhoneCommand
    public var sentAt: Date
    /// Sent once with `.configure` so the watch can show a zone chip.
    public var maxHeartRate: Int?
}
```

A packet with an unknown `v` is ignored, never guessed at. `kind` is required
too: the two shapes otherwise share every required key, so a command would
decode as an empty packet.

## 4. Rep counting

### 4.1 Where

A new package target `Motion` (Foundation only; `AppSurfaces` depends on
nothing, `Motion` depends on nothing) with `RepCounter`, tested on macOS.
The watch target links `Motion`. CoreMotion stays in the watch target: the
controller feeds `CMDeviceMotion.userAcceleration` samples at 50 Hz into the
pure counter.

### 4.2 Algorithm

```swift
public struct RepCounter: Sendable {
    public struct Sample: Sendable { public var t: TimeInterval; public var x, y, z: Double }
    public init(settleSeconds: Double = 1.0, minPeriod: Double = 0.6, maxPeriod: Double = 4.0,
                threshold: Double = 0.15)
    public mutating func add(_ sample: Sample) -> Bool   // true when a rep completed
    public private(set) var reps: Int
    public mutating func reset()
}
```

1. Each axis is smoothed separately; the difference between the fast and slow
   averages is a vector, projected onto the direction of the first lift above
   the threshold, which is locked for the set and cleared by `reset()`. The
   axis locks only on a swing that is still growing (the difference magnitude
   larger than the previous sample's), so a swing already fading when settling
   ends does not pin the axis to its tail.
2. Fast smoothing: exponential moving average with a 0.15 second time
   constant. Slow baseline: exponential moving average with a 2 second time
   constant. The signal `s` is that projection, which removes gravity drift
   and slow posture changes and keeps the sign of the swing rather than
   rectifying it.
3. Hysteresis: a rep is a rise of `s` above `+threshold` followed by a fall
   below `-threshold` (the lift and the return). The counter records the time
   of the rise; when the fall arrives, the rise-to-fall half cycle must be
   between half of `minPeriod` and half of `maxPeriod` or it is discarded.
4. Nothing counts during the first `settleSeconds` after `reset()` (the
   person picking up the weight), and a completed rep starts a refractory
   window of half of `minPeriod`.

Calibration is pinned by tests on synthetic signals: 10 cycles of a 1 Hz
sine at 0.4 g amplitude with 0.05 g white noise count 10; the same at 0.08 g
amplitude count 0; 3 Hz jitter counts 0; a single slow 10 second push counts
0; nine cycles whose first second is swallowed by settling count 8, not 9.

Real-world accuracy is unknown until hardware: the label "auto" and the +1
button are the honesty. Section 9 lists the hardware check.

### 4.3 Sets

The watch keeps `completedSets: [Int]` and the current `reps`. Next set
appends the current count and resets the counter. On finish, the phone
writes the sets onto the workout record as a JSON `setsData: Data?` column
(the codebase's pattern for an array on a shipped model), and the recorder's
draft keeps `completedSets` and `reps` for restore.

## 5. Recorder changes

`ActivityRecorder` gains:

- `source: SessionSource` and the 10 second watch hand-off described in 3.1.
- `receiveWatchPacket(_:)`: heart rate goes through the existing
  `receiveHeartRate(_:at:)` so effort accrual, throttling and the Live
  Activity stay one path; energy sets `energy`; reps and sets update
  `reps`, `setIndex`, `completedSets`.
- `nextSet()` and `addRep()`: for `.watch`, send the command and update
  locally when the echo packet arrives; for `.phone` strength sessions,
  update locally (manual counting on the phone alone).
- Pause, resume and finish send commands for `.watch` and let the mirrored
  session's state change drive the timer, as the phone session already does.
- The Health path of `start()` and `saveFinished()` are skipped for `.watch`;
  the local `WorkoutRecord` is still written, with `setsData`.

`LiveSessionReadout` gains `reps: Int?`, `setIndex: Int?` and
`LiveSessionReadout+Text` gains `repsText` ("12") and `setText` ("Set 2").
`LiveReadoutBuilder` copies them through. The throttle publishes on any reps
change (immediately, like push state): a rep is what the person is watching.

## 6. Surfaces

- **HUD:** the strength slot shows `repsText` with the chip "reps"; expanded,
  a fourth row shows "Set 2 · 12, 10 so far" and two glass buttons, "+1" and
  "Next set". Yoga, walk, run, cycle and other are unchanged.
- **In-session tiles:** strength gets a "Reps" tile with the set line as its
  caption; the "Live sensor reading" caption reads "From Apple Watch" when
  the source is the watch.
- **Dynamic Island:** for strength the compact trailing side shows reps
  instead of the timer; expanded bottom adds "Set 2 · 12 reps". Lock screen
  tile two (effort) is unchanged; tile three shows reps for strength instead
  of calories, since calories are the less watched number in a lift.
- **Watch screen (`WatchWorkoutScreen`):** timer at the top, heart rate with
  the zone chip when the phone has sent `.configure` with `maxHeartRate`
  (3.3), reps and set for strength
  with +1 and Next set, pause and end at the bottom. Uses the system font
  and the app's orange accent; no design system dependency on the watch.
- **Begin Activity:** the connections panel gains an "Apple Watch" line
  ("Ready", "Not paired", "Open Almanac on your watch") and the "How syncing
  works" copy is rewritten: the watch records when it is nearby, the phone
  records otherwise.

## 7. Watch target changes

- Entitlement `com.apple.developer.healthkit` on `AlmanacWatch`.
- `WKBackgroundModes = [workout-processing]` in the watch Info.plist.
- `INFOPLIST_KEY_NSHealthShareUsageDescription`,
  `INFOPLIST_KEY_NSHealthUpdateUsageDescription` and
  `INFOPLIST_KEY_NSMotionUsageDescription` on the watch target, worded like
  the phone's.
- `@WKApplicationDelegateAdaptor` with `handle(_ workoutConfiguration:)` so a
  phone-started workout launches into the workout screen.
- The watch target links `Motion`; it keeps `AppSurfaces` and adds nothing
  else. New files (`WatchWorkoutController.swift`, `WatchWorkoutScreen.swift`,
  `WatchAppDelegate.swift`) are added to the pbxproj by hand, since the watch
  target is not filesystem-synchronised.

## 8. Testing

Swift Testing:
- `MotionTests/RepCounterTests`: the five calibration cases in 4.2 plus
  reset and refractory behaviour.
- `AppSurfacesTests`: `WatchPacket` and `PhoneCommandEnvelope` round trip;
  unknown version ignored by the decoder helper; readout carries reps and
  set; throttle publishes on a reps change.
- `IntegrationsTests`: `LiveReadoutBuilder` passes reps through; a session
  source enum round-trips in the draft.

In-simulator checks (`ActivityRecorderChecks`): a `.phone` strength session
counts manual reps and sets and writes `setsData`; a packet with an unknown
version changes nothing; a watch hand-off that times out falls back to
`.phone` with the notice.

Hardware (Shiv's watch and phone): start from the phone and see the watch
launch and the phone HUD show watch heart rate within 10 seconds; start from
the watch and see the phone Live Activity appear; do 10 slow bicep curls and
compare the auto count; pause on the watch and see the phone pause; finish
and find one workout in Health. Record all five in
`docs/design/watch-companion/report.md`.

## 9. Risks and open checks

- **Mirroring needs the phone app launchable in the background** and the
  Live Activity requested within 10 seconds of that launch. If the recorder's
  first `persist()` is too slow on a cold launch, request the Live Activity
  first in the mirroring handler.
- **Rep accuracy** on real movement is unmeasured. Ship with "auto" and +1;
  tune `threshold` and the time constants from the hardware session before
  widening beyond strength.
- **watchOS package linking** of `Motion` is the first non-`AppSurfaces`
  package product on the watch. It is Foundation only; if the link fails,
  move the file into the watch target and keep the tests in the package.
- **Recovering a mirrored session after a phone relaunch** is unverified:
  confirm on hardware whether `recoverActiveWorkoutSession` returns it, and
  keep the packet-driven re-attach either way.
- **Two sessions at once.** If the phone path is already running when a
  mirrored session arrives (the person started on both), the recorder keeps
  the phone session and *discards* the mirrored one with a notice; it never
  merges, and it never ends it, since ending means saving on the wrist.
- **Recovery behaviour is still unverified.** No hardware run has confirmed
  whether `recoverActiveWorkoutSession` returns a mirrored session after a
  phone relaunch; see `docs/design/watch-companion/report.md`.
- **The five section 8 hardware checks are pending**, to be run by Shiv on
  the iPhone and watch; see `docs/design/watch-companion/report.md`.
