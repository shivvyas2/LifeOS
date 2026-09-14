# Live session core: effort, battery, and a glass Live Activity

**Date:** 2026-09-14
**Status:** implemented on feat/live-session-core, see docs/design/live-session/report.md
**Builds on:** `docs/design/health-activity/implementation.md` (the native
recorder, the Bluetooth sensor, the timer-only Live Activity),
`2026-08-12-whoop-full-ingestion-design.md` (recovery, strain and sleep in
`DailyMetrics`), `2026-08-25-health-restructure-restyle-design.md` (tokens and
module hues).

**Followed by:** slice 2, the Apple Watch companion (watch workout session,
mirroring, wrist-motion reps); slice 3, the workout library (curated YouTube
catalog, planner, player with HUD). Each gets its own spec.

## 1. The problem

A person starting a workout in Almanac today sees a timer, and if they scan and
tap for a sensor, a heart rate. They cannot see how hard they are working, how
much they have left in them, or whether they should push. The lock screen
shows the same timer on a dark tint and nothing else.

Everything needed to answer those questions already reaches the app: WHOOP
recovery and sleep performance sit in `DailyMetrics`, the profile carries a
birth date, the recorder collects energy from the workout builder, and the
sensor delivers beats every second. Nothing joins them into a live readout.

Three concrete gaps:

1. `WorkoutActivityAttributes.ContentState` carries elapsed time and nothing
   else, so the Live Activity cannot show a reading.
2. There is no notion of zones, effort or capacity anywhere in the app; every
   strain number is WHOOP's and arrives hours later.
3. The sensor forgets the paired device between sessions, so WHOOP Heart Rate
   Broadcast needs a scan and a tap every time.

## 2. What this slice delivers

| Area | Change |
|---|---|
| Effort model | Zones from age, an estimated effort on a 0 to 21 scale, a capacity ("battery") for today, a safe ceiling, and a push state. Pure Swift in `Integrations`, fully tested. |
| Live Activity | Blue to white gradient, translucent tiles for BPM and zone, effort, calories and battery on the lock screen and in the Dynamic Island. Throttled updates. |
| In-app HUD | One small Liquid Glass capsule that expands on tap and adapts to the activity. The in-session state of Begin Activity is restyled around a gradient hero. |
| Auto-connect | The last sensor reconnects silently at session start; a WHOOP-connected account with no paired sensor auto-pairs the first WHOOP it sees. |

Out of scope for this slice: Apple Watch heart rate (slice 2), rep counting
(slice 2), any video or catalog (slice 3), server changes (none needed).

## 3. Effort model

All of this lives in `LifeOSKit/Sources/Integrations/LiveEffort.swift` as
value types and pure functions. Nothing here touches HealthKit, Bluetooth,
SwiftData or the clock; callers pass values in.

### 3.1 Zones

```swift
public struct HeartRateZones: Equatable, Sendable {
    public let maxHeartRate: Int
    public init?(birthDate: Date?, on date: Date = .now)   // nil without a birth date
    public func zone(for bpm: Int) -> Int                  // 0...5
}
```

Max heart rate is Tanaka: `208 - 0.7 * age`, rounded. Zone boundaries follow
WHOOP's bands so numbers agree with the app the person already trusts: zone 1
starts at 50 percent, then 60, 70, 80, 90. Below 50 percent is zone 0.

Without a birth date there are no zones. The recorder then reports raw BPM and
calories only, and the HUD shows a one-line hint, "Add your birth date in
Profile for zones and effort." A guessed max heart rate would be a false
reading and this app refuses those.

### 3.2 Effort

```swift
public struct EffortAccumulator: Equatable, Sendable {
    public private(set) var load: Double
    public mutating func add(zone: Int, seconds: TimeInterval)
    public var effort: Double        // 0...21
}
```

Each second in a zone adds a weight to `load`. Weights rise steeply with zone
because that is what the body feels and what WHOOP's curve rewards:

| Zone | Weight per second |
|---|---|
| 0 | 0 |
| 1 | 0.15 |
| 2 | 0.28 |
| 3 | 0.35 |
| 4 | 0.45 |
| 5 | 0.63 |

`effort = 21 * (1 - exp(-load / 1500))`. The weights and the 1500 are the
values that make all three calibration points in section 8 hold at once. The mapping saturates, so a very long session
approaches 21 without ever reaching it, which matches how WHOOP's scale
behaves.

Effort is always shown with the word "estimated" or the eyebrow "EST" next to
it. WHOOP's real strain for the workout still arrives later on its own
`WorkoutRecord` through the existing sync, and nothing here overwrites it.

### 3.3 Capacity

```swift
public struct Capacity: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case whoop(Date), health(Date) }
    public let percent: Int          // 0...100
    public let source: Source
    public let ceiling: EffortCeiling
}
public struct EffortCeiling: Equatable, Sendable {
    public let maxZone: Int          // 3, 4 or 5
    public let targetEffort: ClosedRange<Double>
}
public struct RecoveryDay: Equatable, Sendable {   // one DailyMetrics row, lifted off SwiftData
    public let date: Date
    public var whoopRecoveryPct: Double?
    public var whoopIsCalibrating: Bool?
    public var sleepPerformancePct: Double?
    public var hrvMs: Double?
    public var sleepMinutes: Int?
}
public enum CapacityMath {
    public static func capacity(days: [RecoveryDay], now: Date, calendar: Calendar) -> Capacity?
}
```

The candidate rows are today's and yesterday's: yesterday stands in while
today has not synced, anything older is stale. Resolution order:

1. **WHOOP.** Recovery percent is present and `isCalibrating` is not true.
   `percent = recovery`, nudged by sleep performance: `percent = round(0.8 *
   recovery + 0.2 * sleepPerformance)` when sleep performance is present,
   plain recovery otherwise.
2. **Apple Health.** HRV is present and at least three of the previous seven
   days carry HRV for a baseline. The ratio `hrv / baseline` maps piecewise:
   0.7 to 1.0 onto 20 to 65 percent and 1.0 to 1.2 onto 65 to 90, clamped.
   Sleep minutes, when present, then adjust by up to plus or minus 10 points
   against a 7.5 hour reference.
3. **Nothing.** Return nil. The UI says "Battery unknown" and the recorder
   uses `EffortCeiling.conservative`, the yellow band, so guidance stays
   cautious without claiming a capacity it does not have.

The ceiling follows the WHOOP recovery bands:

| Capacity | Band | Max zone | Target effort |
|---|---|---|---|
| 67 to 100 | green | 5 | 14 to 18 |
| 34 to 66 | yellow | 4 | 10 to 14 |
| 0 to 33 | red | 3 | 4 to 10 |

### 3.4 Battery left and push state

```swift
public enum PushState: String, Codable, Sendable { case easy, onTrack, nearLimit, overLimit }
public enum EffortMath {
    public static func batteryRemaining(capacity: Int, effort: Double, ceiling: EffortCeiling) -> Int
    public static func pushState(zone: Int?, effort: Double, ceiling: EffortCeiling) -> PushState
}
```

- `batteryRemaining = max(0, round(capacity * (1 - effort / ceiling.targetEffort.upperBound)))`.
  Reaching 0 is a real event, "you have spent today's budget", not a missing
  value, and the UI says so with the amber "Over your target" line.
- Push state: `overLimit` when zone exceeds `maxZone` or effort exceeds the
  target's upper bound; `nearLimit` when zone equals `maxZone` or effort is
  within 1.5 of the upper bound; `easy` when effort is below the target's
  lower bound and zone is at most 2; `onTrack` otherwise. A nil zone yields
  `onTrack` unless effort alone decides.

### 3.5 Readout

The single struct every surface renders:

```swift
public struct LiveSessionReadout: Codable, Hashable, Sendable {
    public var elapsed: TimeInterval
    public var runningSince: Date?
    public var heartRate: Int?
    public var zone: Int?
    public var effort: Double?          // rounded to 0.1 before publishing
    public var calories: Int?
    public var distanceMeters: Int?
    public var batteryPercent: Int?
    public var capacitySource: String?  // "whoop" or "health", for the eyebrow
    public var ceilingMaxZone: Int?
    public var ceilingTarget: ClosedRange<Double>?
    public var push: PushState
}
```

`WorkoutActivityAttributes.ContentState` becomes exactly this struct (kept as
a nested typealias so the widget code stays readable). `LiveSessionReadout`
and `PushState` live in `AppSurfaces` so the widget target can decode them.
`Integrations` adds `AppSurfaces` as a dependency in `Package.swift` (it has
none of its own, so nothing cycles) and the rest of the effort model stays in
`Integrations`.

## 4. Recorder changes

`ActivityRecorder` gains:

- `capacity: Capacity?` computed once in `start()` from the last nine days of
  `DailyMetrics` rows via `MetricsStore`: today's row, yesterday's as the
  fallback, and the week behind them as the HRV baseline. Stored in the
  draft so a relaunch keeps it.
- `zones: HeartRateZones?` from the profile birth date at start.
- `effort: EffortAccumulator` advanced on every heart-rate reading with the
  seconds since the previous reading, capped at 5 seconds per reading so a
  gap in the stream does not credit effort that was not measured. Paused time
  never accrues. Persisted in the draft.
- `readout: LiveSessionReadout` recomputed after any change and handed to the
  Live Activity controller and the HUD.

Energy and distance keep coming from the workout builder exactly as today.

## 5. Live Activity

### 5.1 Publishing

`WorkoutLiveActivityController.sync(_ readout:)` replaces `sync(_:icon:)`.
The decision to publish is a pure function in `AppSurfaces`, so it is tested:

```swift
public enum LiveActivityThrottle {
    public static func shouldPublish(previous: LiveSessionReadout?, next: LiveSessionReadout,
                                     lastPublishedAt: Date?, now: Date) -> Bool
}
```

Publish when there is no previous state, when the timer phase changed
(pause, resume, finish), when heart rate moved by 3 bpm or more, when push
state changed, or when 10 seconds passed since the last publish and anything
differs. Otherwise skip. This keeps the activity within ActivityKit's update
budget while the sensor streams every second.

`staleDate` stays at 8 hours. `pushType` stays nil.

### 5.2 Lock screen

- Background: a linear gradient from `ModuleHue.recovery.top` at the top
  leading corner to `Color(white: 0.97)` at the bottom trailing corner, with a
  soft radial highlight of white at 20 percent opacity near the top. The
  widget target links `DesignSystem` for the hue; the hardcoded orange goes.
- Row one: the activity icon in a 44 point circle filled white at 22 percent,
  the activity name in `.headline`, and a status line under it. The status
  line is the push state in words: "Easy going", "On track", "Near your
  limit", "Over your target". When paused it says "Paused". On the trailing
  side, the timer in rounded bold `.title`, using `Text(timerInterval:)`
  while running as today.
- Row two: four tiles in an `HStack`, each a rounded rectangle (16 point
  continuous) filled white at 18 percent with a 0.5 point white stroke at 35
  percent. Widget extensions cannot render materials, so this translucent
  fill over the gradient is the glass. Tiles, left to right:
  1. Heart: BPM in bold rounded `.title3`, "Z4" eyebrow when zones exist.
  2. Effort: value to one decimal, eyebrow "EST" and the target as "of 14".
  3. Calories: integer, eyebrow "KCAL".
  4. Battery: percent, eyebrow "LEFT", with a 3 point ring around a battery
     symbol showing the percent.
  A tile with no value shows an en dash in the same weight, never a zero.
- Text is white over the blue field. The bottom row sits over the paler part
  of the gradient, so tile text there is `Color(white: 0.12)`. Both are fixed
  by position, not by scheme, since the gradient is the same in light and
  dark.
- Tint: `activityBackgroundTint(nil)` so the gradient shows, and
  `activitySystemActionForegroundColor(.white)`.
- Deep link unchanged: `SurfaceRoute.activity.url`.

### 5.3 Dynamic Island

- Compact leading: heart symbol and BPM, tinted by push state (green for easy
  and on track, amber for near limit, red for over limit). Without a reading,
  the activity icon.
- Compact trailing: the timer.
- Minimal: the zone number in a small circle tinted by push state, or the
  activity icon without zones.
- Expanded: leading is the activity name with icon; trailing is the timer;
  bottom is the four readings as compact label pairs in one row, and the
  status line beneath with the existing "Open activity" link.
- Keyline tint follows push state.

## 6. In-app HUD and the in-session screen

### 6.1 `SessionHUD`

`LIfeOS/Features/Activity/View/SessionHUD.swift`, a SwiftUI view that takes a
`LiveSessionReadout`, a `RecordedActivity` and an `isExpanded` binding. It has
no dependency on the recorder, so it previews from fixture readouts at both
pinned viewports.

- **Collapsed:** one capsule, 52 points tall, `.glassEffect(.regular.tint(pushTint).interactive())`
  in a `Capsule`. Inside, left to right with 14 point spacing: timer in
  monospaced rounded `.headline`; a heart with BPM and a small zone chip;
  effort to one decimal with a tiny "est" eyebrow; a battery symbol with the
  percent. Each reading is a `Label`-like pair with a fixed minimum width so
  the capsule does not jitter as digits change.
- **Expanded:** the capsule grows into a 24 point rounded rectangle with a
  second line: "Up to zone 4 today · target 10 to 14 · WHOOP recovery" (or
  "Apple Health" or "Battery unknown"), then a third row with calories and,
  for run and cycle, distance. Tap anywhere toggles; the transition is a
  `GlassEffectContainer` morph.
- **Adaptation by activity:**
  - Walk, run, cycle: distance appears in the expanded row.
  - Strength: the capsule reserves a trailing slot labeled "reps" that reads
    an en dash until slice 2 fills it. The slot exists now so slice 2 adds a
    value, not a layout.
  - Yoga: effort and battery hide; the capsule shows timer, BPM and zone only,
    and the expanded line reads "Recovery session".
  - Other: the default set.
- **Colour:** the tint follows push state with the same green, amber and red
  as the Dynamic Island, at 18 percent so the glass stays glass. Text is
  `LifeOSTokens.primaryText` resolved for the scheme.
- Accessibility: the collapsed capsule is one element whose label reads every
  value in words, for example "Elapsed 12 minutes 4 seconds, heart rate 142,
  zone 4, effort 9.3 estimated, battery 62 percent". Expanded, each row is
  its own element.

### 6.2 Begin Activity while a session runs

The pre-session state (heading, picker, Save to Apple Health, Begin) does not
change. Once a session exists, the screen becomes:

- A gradient hero replacing the pastel timer card: `ModuleHue.recovery.top`
  at the top fading to the canvas colour by 320 points, full bleed under the
  navigation bar, matching the reference where the big numeral sits in the
  blue field. The timer is the numeral at 72 points rounded, white, with the
  activity name and status line above it and "Elapsed time" below, both white
  at 85 percent.
- The `SessionHUD` sits at the bottom edge of the hero, overlapping the
  gradient's fade, so the glass has colour behind it.
- Below the hero, the existing reading cards become three glass tiles on the
  canvas: heart rate with zone, effort with the target and source, calories.
  The tile grid uses the same `SoftCard` radii. Distance appears as a fourth
  tile for walk, run and cycle.
- Controls stay as they are: pause or resume, finish and save, discard.
- The connections panel stays, and its status line now reflects auto-connect
  ("Reconnecting to WHOOP…", "Live · WHOOP").

Dark mode: the hero uses `ModuleHue.recovery.darkTop` and the canvas dark
value; tiles resolve tokens as they do elsewhere.

## 7. Auto-connect

`LiveHeartRateSensor` gains a `rememberedPeripheralID: UUID?` in the
per-account defaults under `lastHeartRateSensorID`, written on every successful
connection and cleared on an explicit disconnect. It gains:

```swift
func reconnectIfRemembered()      // called by ActivityRecorder.start()
func autoPairWhoop()              // called instead when nothing is remembered and WHOOP is connected
```

- `reconnectIfRemembered`: `retrievePeripherals(withIdentifiers:)`, connect,
  status "Reconnecting to WHOOP…" (or the remembered name). If no connection
  within 20 seconds, fall back to a scan and connect the first discovered
  peripheral whose identifier or name matches the remembered one, then stop.
- `autoPairWhoop`: scan for 30 seconds; when exactly one discovered
  peripheral has "WHOOP" in its name, connect and remember it. If several
  appear, stop and set status "More than one WHOOP nearby. Choose one under
  Manage." Nothing auto-pairs a device that is not a WHOOP, since another
  person's chest strap in a gym is not a reading this person owns.
- Account changes and logout clear the remembered identifier along with the
  rest of the per-account defaults; the recorder's `deactivate()` already
  runs then.
- Bluetooth off, unauthorised, or unsupported states keep today's messages
  and never loop.

## 8. Testing

Swift Testing in `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`
and `LifeOSKit/Tests/AppSurfacesTests/LiveActivityThrottleTests.swift`:

- Zones: a 30 year old has max 187; 94 bpm is zone 1, 131 is zone 3, 169 is
  zone 5, 90 is zone 0. No birth date yields nil.
- Effort calibration, asserted within 1.0: 60 minutes in zone 3 gives about
  12; 30 minutes in zone 2 gives about 6; 90 minutes alternating zones 4 and 5
  gives about 18; zero seconds gives 0; effort never exceeds 21 and never
  decreases.
- Capacity: WHOOP 80 percent with sleep 90 gives 82 and the green ceiling;
  yesterday's recovery stands in and two days ago does not; calibrating WHOOP
  falls through to Health; Health with HRV at baseline and 7.5 hours gives 65
  and yellow, needs three baseline days, and moves with sleep; nothing gives
  nil.
- Battery and push: capacity 60 at effort 7 against a 14 target gives 30 left;
  effort 15 gives 0 and `overLimit`; zone 5 under a max zone of 4 gives
  `overLimit`; zone 4 under a max of 4 gives `nearLimit`; zone 2 at effort 3
  under a 10 to 14 target gives `easy`.
- Throttle: first publish always; a 1 bpm change 2 seconds later skips; a 3
  bpm change publishes; a readout that differs only by 0.1 effort skips at 4
  seconds and publishes at 10; an identical readout never publishes; a pause
  publishes regardless.
- Effort accrual caps a 40 second gap at 5 seconds of credit and accrues
  nothing while paused.

The in-simulator `ActivityRecorderChecks` harness gains: capacity is stored in
the draft and restored; a remembered sensor identifier survives relaunch; an
account switch clears it.

Design QA, in `docs/design/live-session/`: the in-session screen at iPhone
402 by 874 and iPad 834 by 1210 in light and dark, the HUD collapsed and
expanded, and a lock screen capture of the Live Activity from the simulator.
The report follows the format in `design-qa.md`.

## 9. Risks and open checks

- **Background execution.** The recorder runs `HKWorkoutSession` on the
  phone. Confirm against WWDC25 session 322 whether iOS 26 keeps the app
  running during a phone workout session or whether
  `workout-processing` must join `UIBackgroundModes`. Add it if required.
  The Bluetooth central background mode is already present.
- **Effort calibration** is a model, not WHOOP's algorithm. The constants are
  pinned by tests so a future retune is a deliberate change with a diff.
- **ActivityKit budget.** The throttle is designed to sit well under the
  system's limits; if updates still get deferred on hardware, widen the
  10 second floor before touching anything else.
- **Uncommitted foundation.** The recorder, sensor, Live Activity and watch
  target exist only as uncommitted files in the main checkout. The plan must
  start by committing that foundation on its own branch so this slice has
  something to build on and to diff against.
