# Focus Sessions and the Soundscape Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Focus sessions with Pomodoro, countdown and sleep-fade timers, played over an on-device generative soundscape (Focus, Brainstorm, Relax, Sleep) that adapts to time of day, Watch heart rate, timer phase, weather and recovery, or over Apple Music.

**Architecture:** All sound and timer logic lives in a new pure-Swift `Soundscape` target in LifeOSKit (recipes, the conditions-to-parameters mapping, a seeded composer, DSP voices, a renderer usable live or offline, the timer state machine, setup preferences), tested with swift-testing and audible through a `soundscape-render` WAV tool. The app adds `Features/Focus`: an `AVAudioEngine` host, a MusicKit source, Watch heart rate through the existing bridge, notifications, Now Playing, the session model and screens, and three entry points (Today module, project task, App Intent). A `FocusSessionRecord` in Persistence keeps history.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation (`AVAudioEngine`, `AVAudioSourceNode`), Synchronization (`Mutex`, `Atomic`), MusicKit, HealthKit (`HKWorkoutSession` on the Watch), MediaPlayer, UserNotifications, AppIntents, swift-testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-08-focus-sessions-soundscape-design.md`

## Global Constraints

- Work only in the worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/focus-soundscape` on branch `feat/focus-soundscape`. `Config/Secrets.xcconfig` is already copied; never commit it.
- Commits: conventional commits (`feat(focus): ...`, `test(soundscape): ...`), no em dashes anywhere (code comments, copy, commit messages), and **no `Co-Authored-By` trailer**.
- Package: LifeOSKit `swift-tools-version: 6.0`, platforms iOS/macOS/watchOS `"26.0"`. `Soundscape` depends on nothing in the kit.
- Package tests: `cd LifeOSKit && swift test --filter <Suite>`; full run `cd LifeOSKit && swift test --parallel`.
- App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'id=D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB' build -quiet` (private simulator "Badminton iPhone 17", iOS 26.2; if `xcrun simctl list devices | grep D6CEC8FF` finds nothing, create one with `xcrun simctl create "Focus iPhone 17" "iPhone 17"` and use its id everywhere below).
- Watch build: `xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWatch -destination 'generic/platform=watchOS Simulator' build -quiet`.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Anything the audio thread calls must be `nonisolated` or live in the package.
- Nothing on the audio render path allocates, takes a blocking lock, or touches reference-counted objects other than the renderer itself.
- A new SwiftData field must be optional or defaulted (installed stores must open).
- Mood names and copy: Focus, Brainstorm, Relax, Sleep. Sources: Soundscape, Apple Music, Silence. Textures: Auto, None, Rain, Wind, Brown noise.
- Timer presets copied from the spec: Focus and Brainstorm 25/5 with a 15-minute long break after every 4th block (default), 50/10, 90/20, block count 4 by default or open-ended; Relax 10, 20, 30 minutes or open-ended; Sleep fade 15, 30, 60 minutes or all night.
- Parameter changes glide (renderer glide 3 s, mood crossfade 8 s). Mood swap never resets the timer.
- Cost: $0; no server calls.

## Deviations from the spec (recorded in the spec in Task 1)

1. **Watch focus kind**: no new `PhoneCommand`. The phone starts the Watch app with a mind-and-body `HKWorkoutConfiguration`; that activity type is the marker on both sides, and the phone ends it with the existing `.discard` command.
2. **Render overrun**: instead of emitting silence, the renderer drops into a light mode (no reverb, no bells, plucks or pulses) after sustained overruns or at the `serious` thermal state; this never glitches and keeps sound going.
3. **App tests**: the app has no unit-test target, so the session logic a test needs (conditions, source fallback, phase mapping, timer) is in the kit and tested there; `FocusSessionModel` stays thin glue covered by the UI test.
4. **Apple Music breaks**: `ApplicationMusicPlayer` exposes no volume control, so breaks **pause** the music and the next work block resumes it.
5. **LIFO**: the coach does not call App Intents today; LIFO starting a session is left out of this build (Siri and Shortcuts get the intent).

## Review Focus

1. **Locked phone, long session**: a 4-block Pomodoro started, phone locked for 2 hours, then unlocked: the screen must show the correct phase and `Session complete`, and the block-end notifications must have fired. (Task 7 test `aLongGapLandsInTheRightPhase`; Task 13 schedules notifications.)
2. **A Watch focus session must never become a workout**: with the Activity screen open (recorder attached) and a focus session running, the mind-and-body session must not be adopted as an "Other" workout or saved to Health. (Task 12 guards in the bridge and recorder.)
3. **Mood swap while paused or in a break** keeps the timer exactly where it was. (Task 7 test `skipAndPauseKeepTheClock`; Task 13 `changeMood` never touches the timer.)
4. **No Apple Music subscription / access denied**: the session must still start, on Soundscape, with the one-line notice. (Task 8 test `appleMusicFallsBackWithANotice`.)
5. **Extreme inputs**: heart rate 0, 250, missing resting rate, wind 200 km/h, midnight, all-night sleep: parameters stay in range and the output never exceeds 0 dBFS or goes NaN. (Task 2 test `extremeInputsStayInRange`; Task 4 test `voicesStayFiniteAndBounded`.)

---

## File Structure

**LifeOSKit (new target `Soundscape`, new test target `SoundscapeTests`, new executable `soundscape-render`):**

| File | Responsibility |
|---|---|
| `Sources/Soundscape/Mood.swift` | `Mood`, `Texture`, `Layer`, music search terms |
| `Sources/Soundscape/MoodRecipe.swift` | `MoodRecipe`, `Breathing`, the four recipes |
| `Sources/Soundscape/Conditions.swift` | `Conditions`, `SoundPhase`, `WeatherKind`, `WeatherInput`, `RecoveryLevel`, `TimeOfDay` |
| `Sources/Soundscape/SoundParameters.swift` | `SoundParameters`, `TextureKind`, `SoundParameters.make` |
| `Sources/Soundscape/Composer.swift` | `SeededGenerator`, `NoteEvent`, `Composer` |
| `Sources/Soundscape/DSP/Voice.swift` | `Voice` state and per-layer sample generation |
| `Sources/Soundscape/DSP/Noise.swift` | `NoiseBank`: white, pink, brown, rain, wind, hiss |
| `Sources/Soundscape/DSP/Reverb.swift` | `Comb`, `Allpass`, `Reverb` |
| `Sources/Soundscape/SoundscapeRenderer.swift` | voice pool, bar clock, glide, mixing, limiter, light mode, chime |
| `Sources/Soundscape/WAVWriter.swift` | 16-bit stereo WAV encoding |
| `Sources/Soundscape/FocusTimer.swift` | `TimerPlan`, `TimerPhase`, `TimerReading`, `PhaseEnd`, `FocusTimer`, `SoundPhase.init(_:)` |
| `Sources/Soundscape/FocusSetup.swift` | `SoundSource`, `TimerPreset`, `FocusSetup`, `FocusPreferences`, `MusicAvailability`, `resolveSource` |
| `Sources/soundscape-render/main.swift` | CLI that writes WAVs |
| `Tests/SoundscapeTests/*.swift` | one test file per source file |

**LifeOSKit (existing targets):**

| File | Change |
|---|---|
| `Package.swift` | add product, targets |
| `Sources/Persistence/FocusSessionRecord.swift` | new `@Model` and `FocusStore` |
| `Sources/Persistence/LifeOSContainer.swift` | add `FocusSessionRecord.self` to the schema |
| `Tests/PersistenceTests/FocusStoreTests.swift` | store tests |
| `Sources/DesignSystem/TodayLayout.swift` | `case focus`, title, standard layout |
| `Tests/DesignSystemTests/TodayLayoutTests.swift` | updated expectations |

**App:**

| File | Responsibility |
|---|---|
| `LIfeOS.xcodeproj/project.pbxproj` | link the `Soundscape` product to the LIfeOS target |
| `Config/App-Info.plist` | `audio` background mode, `NSAppleMusicUsageDescription` |
| `LIfeOS/Features/Focus/Model/SoundscapeEngine.swift` | `AVAudioEngine` host, crossfade |
| `LIfeOS/Features/Focus/Model/MusicSource.swift` | MusicKit availability, playlist pick, play/pause/stop |
| `LIfeOS/Features/Focus/Model/FocusHeartRate.swift` | Watch focus session and heart rate |
| `LIfeOS/Features/Focus/Model/FocusNotifications.swift` | block-end local notifications |
| `LIfeOS/Features/Focus/Model/FocusNowPlaying.swift` | Now Playing info and remote commands |
| `LIfeOS/Features/Focus/Model/FocusInputs.swift` | gathers weather, recovery, resting HR |
| `LIfeOS/Features/Focus/Model/FocusLauncher.swift` | app-wide "open the setup sheet" request |
| `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift` | the session: timer, sources, inputs, saving |
| `LIfeOS/Features/Focus/View/FocusSetupSheet.swift` | mood, sound, timer, texture |
| `LIfeOS/Features/Focus/View/FocusSessionScreen.swift` | full-screen session |
| `LIfeOS/Features/Focus/View/FocusVisual.swift` | breathing concentric shapes |
| `LIfeOS/Features/Focus/View/FocusSummaryView.swift` | end-of-session summary |
| `LIfeOS/Features/Focus/View/FocusDesignPreview.swift` | DEBUG preview page for UI tests |
| `LIfeOS/Features/Focus/Intents/StartFocusSessionIntent.swift` | App Intent and shortcuts |
| `LIfeOS/App/Surfaces/WatchSessionBridge.swift` | focus routing |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` | never adopt a focus session |
| `LIfeOS/Features/Today/View/TodayModules.swift` | `focusModule` |
| `LIfeOS/Features/Projects/View/TaskSheet.swift` | "Focus on this" |
| `LIfeOS/App/RootView.swift` | session model, sheet, full-screen cover |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | dispatch `focus` preview pages |
| `AlmanacWatch/WatchWorkoutController.swift` | `isFocus` |
| `AlmanacWatch/WatchFocusScreen.swift` | minimal focus screen |
| `AlmanacWatch/AlmanacWatchApp.swift` | route focus sessions to it |
| `LIfeOSUITests/FocusUITests.swift` | end-to-end UI test |

---

### Task 1: The `Soundscape` target, moods and recipes

**Files:**
- Modify: `LifeOSKit/Package.swift`
- Modify: `docs/superpowers/specs/2026-10-08-focus-sessions-soundscape-design.md` (append the deviations)
- Create: `LifeOSKit/Sources/Soundscape/Mood.swift`
- Create: `LifeOSKit/Sources/Soundscape/MoodRecipe.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/MoodRecipeTests.swift`

**Interfaces:**
- Produces: `Mood` (`focus, brainstorm, relax, sleep`, `title`, `musicSearchTerm`, `musicKeywords`), `Texture` (`auto, none, rain, wind, brown`, `title`), `Layer` (`pad, bell, pluck, pulse, drone, bed, texture`, `Int` raw values 0 to 6), `Breathing(inhale:exhale:)`, `MoodRecipe` fields `mood, scale, rootMidi, tempo, barsPerChord, chords, gains: SIMD8<Double>, breathing, density, brightness, reverb`, `MoodRecipe.for(_ mood:)`.

- [ ] **Step 1: Add the targets to `Package.swift`**

In `products:` add `.library(name: "Soundscape", targets: ["Soundscape"]),`. In `targets:` add:

```swift
        .target(name: "Soundscape"),
        .testTarget(name: "SoundscapeTests", dependencies: ["Soundscape"]),
        .executableTarget(name: "soundscape-render", dependencies: ["Soundscape"]),
```

Create `LifeOSKit/Sources/soundscape-render/main.swift` with a single line for now so the package resolves:

```swift
print("soundscape-render: see Task 6")
```

- [ ] **Step 2: Write the failing test**

`LifeOSKit/Tests/SoundscapeTests/MoodRecipeTests.swift`:

```swift
import Testing
@testable import Soundscape

@Suite struct MoodRecipeTests {
    @Test(arguments: Mood.allCases)
    func everyRecipeIsWellFormed(_ mood: Mood) {
        let recipe = MoodRecipe.for(mood)
        #expect(recipe.mood == mood)
        #expect(!recipe.scale.isEmpty && recipe.scale.first == 0)
        #expect(recipe.scale.allSatisfy { (0..<12).contains($0) })
        #expect(!recipe.chords.isEmpty)
        #expect(recipe.chords.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 >= 0 } })
        #expect(recipe.barsPerChord.lowerBound >= 1)
        #expect(recipe.tempo.lowerBound > 0)
        for layer in Layer.allCases { #expect((0...1).contains(recipe.gains[layer.rawValue])) }
    }

    @Test func pulsedMoodsHaveABeatAndUnpulsedOnesBreathe() {
        #expect(MoodRecipe.for(.focus).gains[Layer.pulse.rawValue] > 0)
        #expect(MoodRecipe.for(.brainstorm).gains[Layer.pluck.rawValue] > 0)
        #expect(MoodRecipe.for(.relax).breathing == Breathing(inhale: 4, exhale: 6))
        #expect(MoodRecipe.for(.relax).gains[Layer.pulse.rawValue] == 0)
        #expect(MoodRecipe.for(.sleep).breathing != nil)
        #expect(MoodRecipe.for(.sleep).gains[Layer.pulse.rawValue] == 0)
    }

    @Test func tempoRangesMatchTheSpec() {
        #expect(MoodRecipe.for(.focus).tempo == 60...72)
        #expect(MoodRecipe.for(.brainstorm).tempo == 76...92)
    }

    @Test func brainstormIsLydian() {
        #expect(MoodRecipe.for(.brainstorm).scale == [0, 2, 4, 6, 7, 9, 11])
        #expect(MoodRecipe.for(.focus).scale == [0, 2, 4, 7, 9])
    }
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter MoodRecipeTests`
Expected: compile failure, `cannot find 'MoodRecipe' in scope`.

- [ ] **Step 4: Implement**

`LifeOSKit/Sources/Soundscape/Mood.swift`:

```swift
/// The four soundscapes. Like Endel's modes, each holds attention without
/// asking for it: little melody, slow change.
public enum Mood: String, CaseIterable, Codable, Sendable {
    case focus, brainstorm, relax, sleep

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .brainstorm: "Brainstorm"
        case .relax: "Relax"
        case .sleep: "Sleep"
        }
    }

    /// What to search the Apple Music catalog for when nothing personal fits.
    public var musicSearchTerm: String {
        switch self {
        case .focus: "focus"
        case .brainstorm: "upbeat instrumental"
        case .relax: "calm ambient"
        case .sleep: "sleep"
        }
    }

    /// Words that mark a personal recommendation as right for this mood.
    public var musicKeywords: [String] {
        switch self {
        case .focus: ["focus", "study", "deep work", "concentration"]
        case .brainstorm: ["creative", "upbeat", "energy", "flow"]
        case .relax: ["calm", "chill", "relax", "ambient"]
        case .sleep: ["sleep"]
        }
    }
}

/// A steady sound under the music. Auto follows the weather.
public enum Texture: String, CaseIterable, Codable, Sendable {
    case auto, none, rain, wind, brown

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .none: "None"
        case .rain: "Rain"
        case .wind: "Wind"
        case .brown: "Brown noise"
        }
    }
}

/// The renderer's layers. The raw value indexes `SoundParameters.gains`.
public enum Layer: Int, CaseIterable, Sendable {
    case pad, bell, pluck, pulse, drone, bed, texture
}
```

`LifeOSKit/Sources/Soundscape/MoodRecipe.swift`:

```swift
/// A breathing cycle for the moods without a beat.
public struct Breathing: Equatable, Sendable {
    public var inhale: Double
    public var exhale: Double
    public init(inhale: Double, exhale: Double) { self.inhale = inhale; self.exhale = exhale }
    public var period: Double { inhale + exhale }
}

/// Everything that makes a mood sound like itself, as data.
public struct MoodRecipe: Equatable, Sendable {
    public var mood: Mood
    /// Semitones above the root, within one octave, starting at 0.
    public var scale: [Int]
    /// The key centre before the time of day moves it.
    public var rootMidi: Int
    /// Beats per minute. Unpulsed moods keep a nominal tempo for the clock.
    public var tempo: ClosedRange<Double>
    public var barsPerChord: ClosedRange<Int>
    /// Chords as scale-degree indexes; a degree past the scale's length is
    /// the same degree an octave up.
    public var chords: [[Int]]
    /// Base gain per `Layer`, 0 to 1.
    public var gains: SIMD8<Double>
    public var breathing: Breathing?
    public var density: Double
    public var brightness: Double
    public var reverb: Double

    public static func `for`(_ mood: Mood) -> MoodRecipe {
        switch mood {
        case .focus:
            MoodRecipe(mood: .focus, scale: [0, 2, 4, 7, 9], rootMidi: 55, tempo: 60...72, barsPerChord: 5...9,
                       chords: [[0, 2, 4], [1, 3, 5], [4, 6, 8], [3, 5, 7]],
                       gains: gains(pad: 0.55, bell: 0.25, pulse: 0.30, bed: 0.18),
                       breathing: nil, density: 0.25, brightness: 0.5, reverb: 0.55)
        case .brainstorm:
            MoodRecipe(mood: .brainstorm, scale: [0, 2, 4, 6, 7, 9, 11], rootMidi: 60, tempo: 76...92, barsPerChord: 8...8,
                       chords: [[0, 2, 4, 6], [1, 3, 5, 7], [4, 6, 8, 10], [5, 7, 9, 11]],
                       gains: gains(pad: 0.45, bell: 0.20, pluck: 0.45, pulse: 0.15, bed: 0.08),
                       breathing: nil, density: 0.6, brightness: 0.7, reverb: 0.5)
        case .relax:
            MoodRecipe(mood: .relax, scale: [0, 2, 5, 7, 9], rootMidi: 50, tempo: 50...50, barsPerChord: 3...5,
                       chords: [[0, 1, 3], [0, 2, 3], [1, 3, 4]],
                       gains: gains(pad: 0.55, bell: 0.12, drone: 0.40, bed: 0.20),
                       breathing: Breathing(inhale: 4, exhale: 6), density: 0.12, brightness: 0.4, reverb: 0.8)
        case .sleep:
            MoodRecipe(mood: .sleep, scale: [0, 3, 7, 10], rootMidi: 43, tempo: 40...40, barsPerChord: 8...8,
                       chords: [[0, 2]],
                       gains: gains(pad: 0.30, bell: 0.05, drone: 0.55, bed: 0.30),
                       breathing: Breathing(inhale: 5, exhale: 7), density: 0.05, brightness: 0.2, reverb: 0.85)
        }
    }

    static func gains(pad: Double = 0, bell: Double = 0, pluck: Double = 0, pulse: Double = 0,
                      drone: Double = 0, bed: Double = 0) -> SIMD8<Double> {
        var g = SIMD8<Double>(repeating: 0)
        g[Layer.pad.rawValue] = pad; g[Layer.bell.rawValue] = bell; g[Layer.pluck.rawValue] = pluck
        g[Layer.pulse.rawValue] = pulse; g[Layer.drone.rawValue] = drone; g[Layer.bed.rawValue] = bed
        return g
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `cd LifeOSKit && swift test --filter MoodRecipeTests`
Expected: all pass.

- [ ] **Step 6: Record the deviations in the spec**

Append to the spec a section `## Changes made while planning` listing the five items from this plan's "Deviations from the spec" section, worded as plain statements.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/Soundscape LifeOSKit/Sources/soundscape-render LifeOSKit/Tests/SoundscapeTests docs/superpowers/specs/2026-10-08-focus-sessions-soundscape-design.md
git commit -m "feat(soundscape): the four moods as recipes"
```

---

### Task 2: Conditions and `SoundParameters.make`

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/Conditions.swift`
- Create: `LifeOSKit/Sources/Soundscape/SoundParameters.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/SoundParametersTests.swift`

**Interfaces:**
- Consumes: `Mood`, `Texture`, `Layer`, `MoodRecipe` (Task 1).
- Produces:
  - `SoundPhase` (`work`, `closing(Double)`, `rest`, `fading(Double)`)
  - `WeatherKind` (`clear, rain, snow, other`; `init(symbol:)`)
  - `WeatherInput(kind:windKph:)` and `WeatherInput(symbol:windKph:rainChanceNow:)`
  - `RecoveryLevel` (`low, moderate, high`; `init(percentage:)`)
  - `TimeOfDay(hour:)`
  - `Conditions(date:timeZone:heartRate:restingHeartRate:phase:weather:recovery:texture:)`
  - `TextureKind` (`none, rain, wind, brown, hiss`)
  - `SoundParameters` fields `mood, keyOffset: Int, tempo, breathPeriod: Double?, density, brightness, reverb, gains: SIMD8<Double>, texture: TextureKind, master, bedColour`, computed `barSeconds`
  - `static func make(_ recipe: MoodRecipe, _ conditions: Conditions) -> SoundParameters`

- [ ] **Step 1: Write the failing tests**

`LifeOSKit/Tests/SoundscapeTests/SoundParametersTests.swift`:

```swift
import Testing
import Foundation
@testable import Soundscape

@Suite struct SoundParametersTests {
    let utc = TimeZone(identifier: "UTC")!

    func at(_ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 8; c.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.date(from: c)!
    }

    func conditions(_ hour: Int = 14, hr: Double? = nil, resting: Double? = 60, phase: SoundPhase = .work,
                    weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil, texture: Texture = .auto) -> Conditions {
        Conditions(date: at(hour), timeZone: utc, heartRate: hr, restingHeartRate: resting, phase: phase,
                   weather: weather, recovery: recovery, texture: texture)
    }

    func make(_ mood: Mood, _ c: Conditions) -> SoundParameters { SoundParameters.make(.for(mood), c) }

    @Test func middayIsTheRecipeAsWritten() {
        let p = make(.focus, conditions(14))
        #expect(p.keyOffset == 0)
        #expect(p.brightness == 0.5)
        #expect(p.density == 0.25)
        #expect(p.tempo == 66)
    }

    @Test func morningRaisesAndOpens() {
        let p = make(.focus, conditions(8))
        #expect(p.keyOffset == 2)
        #expect(abs(p.brightness - 0.65) < 1e-9)
        #expect(p.tempo > 66)
    }

    @Test func eveningLowersAndDarkens() {
        let p = make(.focus, conditions(19))
        #expect(p.keyOffset == -2)
        #expect(abs(p.brightness - 0.35) < 1e-9)
    }

    @Test func lateNightCapsBrightnessForFocusAndBrainstorm() {
        let rest = make(.brainstorm, conditions(23, phase: .rest))
        #expect(rest.brightness <= MoodRecipe.for(.brainstorm).brightness - 0.15 + 1e-9)
    }

    @Test func aRacingHeartThinsFocusButKeepsTempo() {
        let calm = make(.focus, conditions(hr: 60))
        let racing = make(.focus, conditions(hr: 100))
        #expect(racing.density < calm.density)
        #expect(racing.tempo == calm.tempo)
        #expect(racing.density >= calm.density * 0.4)
    }

    @Test func aHighPulseSlowsTheBreathingInRelaxAndSleep() {
        let calm = make(.relax, conditions(hr: 54))
        let high = make(.relax, conditions(hr: 80))
        #expect(calm.breathPeriod == 10)
        #expect(high.breathPeriod! > 10)
        #expect(high.breathPeriod! <= 13 + 1e-9)
    }

    @Test func missingRestingRateUsesSixty() {
        #expect(make(.focus, conditions(hr: 90, resting: nil)) == make(.focus, conditions(hr: 90, resting: 60)))
    }

    @Test func breaksLiftAndDropThePulse() {
        let p = make(.focus, conditions(phase: .rest))
        #expect(p.gains[Layer.pulse.rawValue] == 0)
        #expect(p.brightness > 0.5)
        #expect(p.density < 0.25)
    }

    @Test func theClosingMinuteEasesDown() {
        let start = make(.focus, conditions(phase: .closing(0)))
        let end = make(.focus, conditions(phase: .closing(1)))
        #expect(end.density < start.density)
        #expect(end.master < start.master)
    }

    @Test func sleepFadeDropsLayersInOrder() {
        let early = make(.sleep, conditions(23, phase: .fading(0.3)))
        #expect(early.gains[Layer.bell.rawValue] == 0)
        #expect(early.gains[Layer.pad.rawValue] > 0)
        let mid = make(.sleep, conditions(23, phase: .fading(0.6)))
        #expect(mid.gains[Layer.pad.rawValue] == 0)
        #expect(mid.gains[Layer.bed.rawValue] > 0)
        let late = make(.sleep, conditions(23, phase: .fading(0.8)))
        #expect(late.gains[Layer.bed.rawValue] == 0)
        #expect(late.gains[Layer.drone.rawValue] > 0)
        #expect(late.master < mid.master)
        #expect(make(.sleep, conditions(23, phase: .fading(1))).master < 1e-6)
    }

    @Test func sleepNoiseEasesFromPinkToBrown() {
        #expect(make(.sleep, conditions(23, phase: .fading(0))).bedColour == 0)
        #expect(make(.sleep, conditions(23, phase: .fading(0.5))).bedColour == 0.5)
        #expect(make(.focus, conditions()).bedColour == 1)
    }

    @Test func autoTextureFollowsTheWeather() {
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5))).texture == .rain)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .snow, windKph: 5))).texture == .hiss)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .clear, windKph: 40))).texture == .wind)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .clear, windKph: 5))).texture == .none)
        #expect(make(.focus, conditions(weather: nil)).texture == .none)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5))).gains[Layer.texture.rawValue] > 0)
    }

    @Test func aChosenTextureOverridesTheWeather() {
        let p = make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5), texture: .brown))
        #expect(p.texture == .brown)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5), texture: .none)).texture == .none)
    }

    @Test func aRedRecoveryDayIsSlowerAndSofter() {
        let normal = make(.focus, conditions())
        let low = make(.focus, conditions(recovery: .low))
        #expect(abs(low.tempo - normal.tempo * 0.92) < 1e-9)
        #expect(abs(low.brightness - (normal.brightness - 0.1)) < 1e-9)
    }

    @Test func weatherSymbolsMapToKinds() {
        #expect(WeatherKind(symbol: "cloud.rain") == .rain)
        #expect(WeatherKind(symbol: "cloud.drizzle.fill") == .rain)
        #expect(WeatherKind(symbol: "cloud.bolt.rain") == .rain)
        #expect(WeatherKind(symbol: "cloud.snow") == .snow)
        #expect(WeatherKind(symbol: "cloud.sleet") == .snow)
        #expect(WeatherKind(symbol: "sun.max") == .clear)
        #expect(WeatherKind(symbol: "cloud.fog") == .other)
        #expect(WeatherInput(symbol: "cloud", windKph: 3, rainChanceNow: 0.7).kind == .rain)
    }

    @Test func recoveryBandsMatchTheApp() {
        #expect(RecoveryLevel(percentage: 33) == .low)
        #expect(RecoveryLevel(percentage: 34) == .moderate)
        #expect(RecoveryLevel(percentage: 67) == .high)
    }

    @Test(arguments: Mood.allCases)
    func extremeInputsStayInRange(_ mood: Mood) {
        let cases: [Conditions] = [
            conditions(0, hr: 0, resting: nil), conditions(3, hr: 250, resting: 40),
            conditions(23, hr: 250, resting: 0, phase: .fading(1), weather: WeatherInput(kind: .snow, windKph: 200), recovery: .low),
            conditions(12, hr: -5, phase: .closing(2)), conditions(6, phase: .fading(-1)),
        ]
        for c in cases {
            let p = make(mood, c)
            for v in [p.density, p.brightness, p.reverb, p.master, p.bedColour] {
                #expect(v.isFinite && (0...1).contains(v))
            }
            #expect(p.tempo.isFinite && p.tempo > 0)
            #expect(p.barSeconds.isFinite && p.barSeconds > 0)
            for layer in Layer.allCases { #expect((0...1).contains(p.gains[layer.rawValue])) }
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter SoundParametersTests`
Expected: compile failure, `cannot find 'Conditions' in scope`.

- [ ] **Step 3: Implement `Conditions.swift`**

```swift
import Foundation

/// Where the session is, as the sound sees it.
public enum SoundPhase: Equatable, Sendable {
    case work
    /// The last minute of a work block; 0 at its start, 1 at the bell.
    case closing(Double)
    case rest
    /// A sleep fade; 0 at its start, 1 at silence.
    case fading(Double)
}

public enum WeatherKind: Equatable, Sendable {
    case clear, rain, snow, other

    /// From a WeatherKit SF Symbol name such as `cloud.drizzle.fill`.
    public init(symbol: String) {
        let s = symbol.lowercased()
        if s.contains("snow") || s.contains("sleet") { self = .snow }
        else if s.contains("rain") || s.contains("drizzle") || s.contains("bolt") { self = .rain }
        else if s.hasPrefix("sun") || s.hasPrefix("moon") { self = .clear }
        else { self = .other }
    }
}

public struct WeatherInput: Equatable, Sendable {
    public var kind: WeatherKind
    public var windKph: Double
    public init(kind: WeatherKind, windKph: Double) { self.kind = kind; self.windKph = windKph }

    /// A day forecast's symbol and wind, plus the chance of rain this hour:
    /// a likely shower counts as rain even under a cloud symbol.
    public init(symbol: String, windKph: Double, rainChanceNow: Double?) {
        var kind = WeatherKind(symbol: symbol)
        if kind != .snow, (rainChanceNow ?? 0) >= 0.6 { kind = .rain }
        self.init(kind: kind, windKph: windKph)
    }
}

/// The same thresholds as the app's `RecoveryBand`.
public enum RecoveryLevel: Equatable, Sendable {
    case low, moderate, high
    public init(percentage: Double) {
        self = percentage < 34 ? .low : percentage < 67 ? .moderate : .high
    }
}

public enum TimeOfDay: Equatable, Sendable {
    case morning, day, evening, night
    public init(hour: Int) {
        switch hour {
        case 5..<11: self = .morning
        case 11..<18: self = .day
        case 18..<22: self = .evening
        default: self = .night
        }
    }
    /// Where in a recipe's tempo range this time sits.
    var tempoPosition: Double {
        switch self { case .morning: 0.75; case .day: 0.5; case .evening: 0.25; case .night: 0 }
    }
}

/// Everything the sound responds to. Missing inputs are nil, never guessed.
public struct Conditions: Equatable, Sendable {
    public var date: Date
    public var timeZone: TimeZone
    public var heartRate: Double?
    public var restingHeartRate: Double?
    public var phase: SoundPhase
    public var weather: WeatherInput?
    public var recovery: RecoveryLevel?
    public var texture: Texture

    public init(date: Date, timeZone: TimeZone = .current, heartRate: Double? = nil, restingHeartRate: Double? = nil,
                phase: SoundPhase = .work, weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil,
                texture: Texture = .auto) {
        self.date = date; self.timeZone = timeZone; self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate; self.phase = phase; self.weather = weather
        self.recovery = recovery; self.texture = texture
    }
}
```

- [ ] **Step 4: Implement `SoundParameters.swift`**

```swift
import Foundation

public enum TextureKind: Int, Equatable, Sendable {
    case none, rain, wind, brown, hiss

    init(_ texture: Texture, weather: WeatherInput?) {
        switch texture {
        case .none: self = .none
        case .rain: self = .rain
        case .wind: self = .wind
        case .brown: self = .brown
        case .auto:
            guard let weather else { self = .none; return }
            if weather.kind == .rain { self = .rain }
            else if weather.kind == .snow { self = .hiss }
            else if weather.windKph > 30 { self = .wind }
            else { self = .none }
        }
    }
}

/// The knobs the renderer turns. A trivial value type, so the audio thread
/// can copy it without touching reference counts.
public struct SoundParameters: Equatable, Sendable {
    public var mood: Mood
    /// Semitones from the recipe's root.
    public var keyOffset: Int
    public var tempo: Double
    /// Seconds per breath for the moods without a beat.
    public var breathPeriod: Double?
    public var density: Double
    public var brightness: Double
    public var reverb: Double
    public var gains: SIMD8<Double>
    public var texture: TextureKind
    public var master: Double
    /// The noise bed's colour: 0 pink, 1 brown.
    public var bedColour: Double

    /// A 4/4 bar, or one breath.
    public var barSeconds: Double { breathPeriod ?? 4 * 60 / tempo }

    static let textureGain = 0.22

    public static func make(_ recipe: MoodRecipe, _ c: Conditions) -> SoundParameters {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = c.timeZone
        let time = TimeOfDay(hour: calendar.component(.hour, from: c.date))
        let pulsed = recipe.mood == .focus || recipe.mood == .brainstorm
        let span = recipe.tempo.upperBound - recipe.tempo.lowerBound
        var p = SoundParameters(mood: recipe.mood, keyOffset: 0,
                                tempo: recipe.tempo.lowerBound + span * time.tempoPosition,
                                breathPeriod: recipe.breathing?.period, density: recipe.density,
                                brightness: recipe.brightness, reverb: recipe.reverb, gains: recipe.gains,
                                texture: .none, master: 0.8, bedColour: recipe.mood == .sleep ? 0 : 1)

        switch time {
        case .morning: p.keyOffset = 2; p.brightness += 0.15
        case .day: break
        case .evening, .night: p.keyOffset = -2; p.brightness -= 0.15
        }

        if let hr = c.heartRate, hr > 0 {
            let resting = (c.restingHeartRate ?? 0) > 0 ? c.restingHeartRate! : 60
            if pulsed {
                let excess = max(0, (hr - resting) / resting)
                p.density *= max(0.4, 1 - excess * 1.5)
            } else if let period = p.breathPeriod {
                p.breathPeriod = period * min(1.3, max(1, hr / (0.9 * resting)))
            }
        }

        p.texture = TextureKind(c.texture, weather: c.weather)
        if p.texture != .none { p.gains[Layer.texture.rawValue] = textureGain }

        if c.recovery == .low { p.tempo *= 0.92; p.brightness -= 0.1 }

        switch c.phase {
        case .work: break
        case .closing(let raw):
            let t = min(1, max(0, raw))
            p.density *= 1 - 0.6 * t
            p.master *= 1 - 0.3 * t
        case .rest:
            p.brightness += 0.1
            p.density *= 0.7
            p.gains[Layer.pulse.rawValue] = 0
        case .fading(let raw):
            let t = min(1, max(0, raw))
            p.master *= cos(t * .pi / 2)
            if t > 0.25 { for layer in [Layer.bell, .pluck, .pulse] { p.gains[layer.rawValue] = 0 } }
            if t > 0.5 { p.gains[Layer.pad.rawValue] = 0 }
            if t > 0.75 { p.gains[Layer.bed.rawValue] = 0; p.gains[Layer.texture.rawValue] = 0 }
            if recipe.mood == .sleep { p.bedColour = t }
        }

        if time == .night, pulsed { p.brightness = min(p.brightness, recipe.brightness - 0.15) }

        func unit(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
        p.density = unit(p.density); p.brightness = unit(p.brightness); p.reverb = unit(p.reverb)
        p.master = unit(p.master); p.bedColour = unit(p.bedColour)
        p.gains = p.gains.clamped(lowerBound: .init(repeating: 0), upperBound: .init(repeating: 1))
        return p
    }
}
```

Note on `middayIsTheRecipeAsWritten`: at 14:00 `TimeOfDay.day.tempoPosition` is 0.5, so the tempo is the range's midpoint (66 for Focus).

- [ ] **Step 5: Run the tests**

Run: `cd LifeOSKit && swift test --filter SoundParametersTests`
Expected: all pass. If `sleepFadeDropsLayersInOrder`'s `master < 1e-6` fails, check that `cos(.pi / 2)` (about 6e-17) is being clamped, not negated.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Soundscape LifeOSKit/Tests/SoundscapeTests
git commit -m "feat(soundscape): turn time, heart rate, phase, weather and recovery into sound parameters"
```

---

### Task 3: The composer

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/Composer.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/ComposerTests.swift`

**Interfaces:**
- Consumes: `MoodRecipe`, `SoundParameters`, `Layer` (Tasks 1 and 2).
- Produces:
  - `SeededGenerator(seed:)`
  - `NoteEvent(layer:midi:velocity:offset:duration:)`; `offset` is seconds from the bar's start, and `duration` is seconds held (0 for percussive layers)
  - `Composer(recipe:seed:)`
  - `mutating func nextBar(_ p: SoundParameters, into events: inout [NoteEvent])`, which clears `events`, fills them sorted by offset, and does not allocate when `events` has capacity 128
  - `func midi(degree:keyOffset:) -> Int`
  - `chordIndex`, `barNumber`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Soundscape

@Suite struct ComposerTests {
    func params(_ mood: Mood, hour: Int = 14) -> SoundParameters {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour))!
        return .make(.for(mood), Conditions(date: date, timeZone: TimeZone(identifier: "UTC")!))
    }

    func bars(_ mood: Mood, seed: UInt64, count: Int, hour: Int = 14) -> [[NoteEvent]] {
        var composer = Composer(recipe: .for(mood), seed: seed)
        var events: [NoteEvent] = []; events.reserveCapacity(128)
        let p = params(mood, hour: hour)
        return (0..<count).map { _ in composer.nextBar(p, into: &events); return events }
    }

    @Test(arguments: Mood.allCases)
    func theSameSeedWritesTheSamePiece(_ mood: Mood) {
        #expect(bars(mood, seed: 7, count: 60) == bars(mood, seed: 7, count: 60))
        #expect(bars(mood, seed: 7, count: 60) != bars(mood, seed: 8, count: 60))
    }

    @Test(arguments: Mood.allCases)
    func everyNoteIsInTheScale(_ mood: Mood) {
        let recipe = MoodRecipe.for(mood)
        for hour in [8, 14, 20] {
            let key = params(mood, hour: hour).keyOffset
            for event in bars(mood, seed: 3, count: 80, hour: hour).flatMap({ $0 }) {
                let pitchClass = ((event.midi - recipe.rootMidi - key) % 12 + 12) % 12
                #expect(recipe.scale.contains(pitchClass), "\(mood) \(event)")
            }
        }
    }

    @Test(arguments: Mood.allCases)
    func eventsAreSortedAndInsideTheBar(_ mood: Mood) {
        let bar = params(mood).barSeconds
        for events in bars(mood, seed: 11, count: 40) {
            #expect(events.map(\.offset) == events.map(\.offset).sorted())
            #expect(events.allSatisfy { $0.offset >= 0 && $0.offset < bar })
            #expect(events.allSatisfy { (24...100).contains($0.midi) })
        }
    }

    @Test func focusChangesChordEveryFiveToNineBars() {
        var composer = Composer(recipe: .for(.focus), seed: 5)
        var events: [NoteEvent] = []; events.reserveCapacity(128)
        var changes: [Int] = []
        for bar in 0..<200 {
            composer.nextBar(params(.focus), into: &events)
            if events.contains(where: { $0.layer == .pad }) { changes.append(bar) }
        }
        let gaps = zip(changes.dropFirst(), changes).map { $0 - $1 }
        #expect(!gaps.isEmpty && gaps.allSatisfy { (5...9).contains($0) })
    }

    @Test func focusHasAFourBeatPulseAndNoPlucks() {
        let events = bars(.focus, seed: 1, count: 1)[0]
        #expect(events.filter { $0.layer == .pulse }.count == 4)
        #expect(!events.contains { $0.layer == .pluck })
    }

    @Test func brainstormPlucksAndRelaxDoesNot() {
        #expect(bars(.brainstorm, seed: 2, count: 20).flatMap { $0 }.contains { $0.layer == .pluck })
        #expect(!bars(.relax, seed: 2, count: 20).flatMap { $0 }.contains { $0.layer == .pluck || $0.layer == .pulse })
    }

    @Test func focusBellsAreSparse() {
        let bells = bars(.focus, seed: 9, count: 400).flatMap { $0 }.filter { $0.layer == .bell }.count
        // One bell every two to four bars on average.
        #expect((100...200).contains(bells))
    }
}
```

Bell density target: Focus density 0.25 gives a probability of `min(1, 0.25 * 1.5) = 0.375` per bar, which is about 150 bells in 400 bars.

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter ComposerTests`
Expected: compile failure, `cannot find 'Composer' in scope`.

- [ ] **Step 3: Implement**

```swift
/// SplitMix64: tiny, fast, and the same everywhere, so a seed always
/// writes the same piece.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct NoteEvent: Equatable, Sendable {
    public var layer: Layer
    public var midi: Int
    public var velocity: Double
    /// Seconds from the start of the bar.
    public var offset: Double
    /// Seconds held; 0 for the struck layers, which decay on their own.
    public var duration: Double
    public init(layer: Layer, midi: Int, velocity: Double, offset: Double, duration: Double) {
        self.layer = layer; self.midi = midi; self.velocity = velocity; self.offset = offset; self.duration = duration
    }
}

/// Writes one bar at a time from a recipe. Runs on the audio thread at bar
/// boundaries, so it only appends into the caller's reserved buffer.
public struct Composer: Sendable {
    public let recipe: MoodRecipe
    private var rng: SeededGenerator
    public private(set) var chordIndex = 0
    public private(set) var barNumber = 0
    private var barsLeftInChord = 0
    /// The key is latched at each chord change so a time-of-day shift never
    /// lands in the middle of a held chord.
    private var chordKey = 0
    private var pluckDegree = 0

    public init(recipe: MoodRecipe, seed: UInt64) {
        self.recipe = recipe
        self.rng = SeededGenerator(seed: seed)
    }

    public func midi(degree: Int, keyOffset: Int) -> Int {
        let n = recipe.scale.count
        let octave = degree >= 0 ? degree / n : (degree - n + 1) / n
        let step = degree - octave * n
        // Fold by octaves, never clamp, so a note always stays in the scale.
        var note = recipe.rootMidi + keyOffset + octave * 12 + recipe.scale[step]
        while note > 100 { note -= 12 }
        while note < 24 { note += 12 }
        return note
    }

    public mutating func nextBar(_ p: SoundParameters, into events: inout [NoteEvent]) {
        events.removeAll(keepingCapacity: true)
        let bar = p.barSeconds
        let beat = bar / 4
        let n = recipe.scale.count

        if barsLeftInChord == 0 {
            if barNumber > 0, recipe.chords.count > 1 {
                var next = Int.random(in: 0..<(recipe.chords.count - 1), using: &rng)
                if next >= chordIndex { next += 1 }
                chordIndex = next
            }
            chordKey = p.keyOffset
            barsLeftInChord = Int.random(in: recipe.barsPerChord, using: &rng)
            let held = Double(barsLeftInChord) * bar + 1.5
            if p.gains[Layer.pad.rawValue] > 0 {
                for degree in recipe.chords[chordIndex] {
                    events.append(NoteEvent(layer: .pad, midi: midi(degree: degree, keyOffset: chordKey),
                                            velocity: 0.6, offset: 0, duration: held))
                }
            }
            if p.gains[Layer.drone.rawValue] > 0 {
                events.append(NoteEvent(layer: .drone, midi: midi(degree: recipe.chords[chordIndex][0], keyOffset: chordKey) - 12,
                                        velocity: 0.7, offset: 0, duration: held))
            }
        }
        barsLeftInChord -= 1
        barNumber += 1

        if p.gains[Layer.pulse.rawValue] > 0, p.breathPeriod == nil {
            let root = midi(degree: 0, keyOffset: chordKey) - 12
            for b in 0..<4 {
                events.append(NoteEvent(layer: .pulse, midi: root, velocity: b == 0 ? 0.7 : 0.45,
                                        offset: Double(b) * beat, duration: 0))
            }
        }

        if p.gains[Layer.bell.rawValue] > 0, Double.random(in: 0..<1, using: &rng) < min(1, p.density * 1.5) {
            let chord = recipe.chords[chordIndex]
            let degree = chord[Int.random(in: 0..<chord.count, using: &rng)] + n
            events.append(NoteEvent(layer: .bell, midi: midi(degree: degree, keyOffset: chordKey), velocity: 0.5,
                                    offset: Double(Int.random(in: 0..<4, using: &rng)) * beat, duration: 0))
        }

        if p.gains[Layer.pluck.rawValue] > 0 {
            for slot in 0..<8 where Double.random(in: 0..<1, using: &rng) < p.density * 0.8 {
                pluckDegree = min(max(pluckDegree + Int.random(in: -2...2, using: &rng), 0), n)
                let swing = slot % 2 == 1 ? beat * 0.08 : 0
                events.append(NoteEvent(layer: .pluck, midi: midi(degree: pluckDegree + n, keyOffset: chordKey),
                                        velocity: slot % 2 == 0 ? 0.55 : 0.4,
                                        offset: Double(slot) * beat / 2 + swing, duration: 0))
            }
            if recipe.mood == .brainstorm, p.gains[Layer.bell.rawValue] > 0,
               Double.random(in: 0..<1, using: &rng) < 0.08 {
                let chord = recipe.chords[chordIndex]
                events.append(NoteEvent(layer: .bell, midi: midi(degree: chord[0] + 2 * n, keyOffset: chordKey),
                                        velocity: 0.35, offset: Double(Int.random(in: 0..<8, using: &rng)) * beat / 2,
                                        duration: 0))
            }
        }

        // Insertion sort: in place, no allocation, and the lists are short.
        if events.count > 1 {
            for i in 1..<events.count {
                let item = events[i]
                var j = i - 1
                while j >= 0, events[j].offset > item.offset { events[j + 1] = events[j]; j -= 1 }
                events[j + 1] = item
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd LifeOSKit && swift test --filter ComposerTests`
Expected: all pass. If `focusBellsAreSparse` lands just outside its range for seed 9, try seeds 1 to 5 and keep the range: the 100 to 200 band is the requirement, not the seed.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Soundscape/Composer.swift LifeOSKit/Tests/SoundscapeTests/ComposerTests.swift
git commit -m "feat(soundscape): a seeded composer that writes each mood a bar at a time"
```

---

### Task 4: Voices, noise and reverb

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/DSP/Voice.swift`
- Create: `LifeOSKit/Sources/Soundscape/DSP/Noise.swift`
- Create: `LifeOSKit/Sources/Soundscape/DSP/Reverb.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/DSPTests.swift`

**Interfaces:**
- Consumes: `Layer`, `NoteEvent`, `TextureKind`.
- Produces:
  - `struct Voice` with `active`, `level`, `layer`, `pan`, `static func frequency(midi:) -> Double`, `mutating func start(_ event: NoteEvent, sampleRate: Double, breathing: Bool, pluckSlot: Int, pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank)`, and `mutating func sample(sampleRate: Double, padCoef: Double, brightness: Double, pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank) -> Double`
  - `Voice.pluckSlotLength = 2048`
  - `struct NoiseBank` with `white()`, `pinkL/pinkR` and `brownL/brownR` via `mutating func bed(colour: Double) -> (Double, Double)`, and `mutating func texture(_ kind: TextureKind, sampleRate: Double) -> (Double, Double)`
  - `struct Reverb` with `init(sampleRate:)` and `mutating func process(_ l: Float, _ r: Float, size: Float) -> (Float, Float)`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Soundscape

@Suite struct DSPTests {
    let sr = 48_000.0

    func run(_ layer: Layer, midi: Int = 60, seconds: Double = 2, brightness: Double = 0.6) -> [Double] {
        var voice = Voice()
        var noise = NoiseBank(seed: 1)
        let buffers = UnsafeMutablePointer<Float>.allocate(capacity: 8 * Voice.pluckSlotLength)
        defer { buffers.deallocate() }
        buffers.initialize(repeating: 0, count: 8 * Voice.pluckSlotLength)
        voice.start(NoteEvent(layer: layer, midi: midi, velocity: 0.8, offset: 0, duration: 1),
                    sampleRate: sr, breathing: false, pluckSlot: 0, pluckBuffers: buffers, noise: &noise)
        let coef = 1 - exp(-2 * Double.pi * 1500 / sr)
        return (0..<Int(seconds * sr)).map { _ in
            voice.sample(sampleRate: sr, padCoef: coef, brightness: brightness, pluckBuffers: buffers, noise: &noise)
        }
    }

    @Test(arguments: [Layer.pad, .bell, .pluck, .pulse, .drone])
    func voicesStayFiniteAndBounded(_ layer: Layer) {
        for midi in [24, 48, 72, 100] {
            let out = run(layer, midi: midi)
            #expect(out.allSatisfy { $0.isFinite && abs($0) <= 1.5 })
            #expect(out.contains { abs($0) > 0.01 }, "\(layer) \(midi) is silent")
        }
    }

    @Test func struckVoicesDieAway() {
        for layer in [Layer.bell, .pluck, .pulse] {
            var voice = Voice(); var noise = NoiseBank(seed: 2)
            let buffers = UnsafeMutablePointer<Float>.allocate(capacity: 8 * Voice.pluckSlotLength)
            defer { buffers.deallocate() }
            buffers.initialize(repeating: 0, count: 8 * Voice.pluckSlotLength)
            voice.start(NoteEvent(layer: layer, midi: 60, velocity: 1, offset: 0, duration: 0),
                        sampleRate: sr, breathing: false, pluckSlot: 0, pluckBuffers: buffers, noise: &noise)
            for _ in 0..<Int(12 * sr) { _ = voice.sample(sampleRate: sr, padCoef: 0.1, brightness: 0.5, pluckBuffers: buffers, noise: &noise) }
            #expect(!voice.active, "\(layer) never released its voice")
        }
    }

    @Test func aHeldPadReleasesAfterItsDuration() {
        let out = run(.pad, seconds: 20)
        let early = out[Int(2 * sr)..<Int(3 * sr)].map(abs).max()!
        let late = out[Int(19 * sr)..<Int(20 * sr)].map(abs).max()!
        #expect(late < early * 0.05)
    }

    @Test func frequencyIsConcertPitch() {
        #expect(abs(Voice.frequency(midi: 69) - 440) < 1e-9)
        #expect(abs(Voice.frequency(midi: 57) - 220) < 1e-9)
    }

    @Test(arguments: [TextureKind.rain, .wind, .brown, .hiss])
    func texturesAreAudibleAndBounded(_ kind: TextureKind) {
        var noise = NoiseBank(seed: 3)
        let out = (0..<Int(2 * sr)).map { _ in noise.texture(kind, sampleRate: sr) }
        #expect(out.allSatisfy { $0.0.isFinite && $0.1.isFinite && abs($0.0) < 2 && abs($0.1) < 2 })
        #expect(out.contains { abs($0.0) > 0.01 })
        #expect(out.map(\.0) != out.map(\.1), "texture is mono")
    }

    @Test func theBedMovesFromPinkToBrown() {
        var a = NoiseBank(seed: 4); var b = NoiseBank(seed: 4)
        let pink = (0..<48_000).map { _ in a.bed(colour: 0).0 }
        let brown = (0..<48_000).map { _ in b.bed(colour: 1).0 }
        // Brown noise moves slower: smaller sample-to-sample steps for its size.
        func roughness(_ x: [Double]) -> Double {
            let steps = zip(x.dropFirst(), x).map { abs($0 - $1) }.reduce(0, +)
            return steps / max(1e-9, x.map(abs).reduce(0, +))
        }
        #expect(roughness(brown) < roughness(pink))
    }

    @Test func reverbIsStableAndHasATail() {
        var reverb = Reverb(sampleRate: sr)
        var tail: Float = 0
        for i in 0..<Int(4 * sr) {
            let x: Float = i < 100 ? 1 : 0
            let (l, r) = reverb.process(x, x, size: 1)
            #expect(l.isFinite && r.isFinite && abs(l) < 4 && abs(r) < 4)
            if i > Int(0.5 * sr), i < Int(sr) { tail = max(tail, abs(l)) }
        }
        #expect(tail > 1e-4)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter DSPTests`
Expected: compile failure, `cannot find 'Voice' in scope`.

- [ ] **Step 3: Implement `Noise.swift`**

```swift
import Foundation

/// Every noise the soundscape uses, left and right drawn separately so the
/// beds are wide. A xorshift generator: no allocation, no locks.
struct NoiseBank {
    private var state: UInt32
    private var pink: (l: SIMD3<Double>, r: SIMD3<Double>) = (.zero, .zero)
    private var brown: (l: Double, r: Double) = (0, 0)
    private var rainLow: (l: Double, r: Double) = (0, 0)
    private var rainWander = 0.85
    private var drop: (l: (freq: Double, phase: Double, amp: Double), r: (freq: Double, phase: Double, amp: Double)) =
        ((0, 0, 0), (0, 0, 0))
    private var wind: (l: (low: Double, band: Double), r: (low: Double, band: Double)) = ((0, 0), (0, 0))
    private var windPhase = 0.0
    private var hissLow: (l: Double, r: Double) = (0, 0)

    init(seed: UInt32 = 0x1234_5678) { state = seed == 0 ? 1 : seed }

    mutating func white() -> Double {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }

    private mutating func pinkSample(_ b: inout SIMD3<Double>) -> Double {
        let w = white()
        b[0] = 0.99765 * b[0] + w * 0.0990460
        b[1] = 0.96300 * b[1] + w * 0.2965164
        b[2] = 0.57000 * b[2] + w * 1.0526913
        return (b[0] + b[1] + b[2] + w * 0.1848) * 0.11
    }

    private mutating func brownSample(_ x: inout Double) -> Double {
        x = (x + 0.02 * white()) / 1.02
        return x * 3.5
    }

    /// The bed under every mood: 0 is pink, 1 is brown.
    mutating func bed(colour: Double) -> (Double, Double) {
        let pl = pinkSample(&pink.l), pr = pinkSample(&pink.r)
        let bl = brownSample(&brown.l), br = brownSample(&brown.r)
        return (pl + (bl - pl) * colour, pr + (br - pr) * colour)
    }

    mutating func texture(_ kind: TextureKind, sampleRate sr: Double) -> (Double, Double) {
        switch kind {
        case .none: return (0, 0)
        case .brown: return (brownSample(&brown.l), brownSample(&brown.r))
        case .hiss:
            let a = 1 - exp(-2 * .pi * 3000 / sr)
            let wl = white(), wr = white()
            hissLow.l += a * (wl - hissLow.l); hissLow.r += a * (wr - hissLow.r)
            return ((wl - hissLow.l) * 0.25, (wr - hissLow.r) * 0.25)
        case .rain:
            rainWander = min(1, max(0.7, rainWander + white() * 0.0005))
            let a = 1 - exp(-2 * .pi * 1500 / sr)
            let wl = white(), wr = white()
            rainLow.l += a * (wl - rainLow.l); rainLow.r += a * (wr - rainLow.r)
            var l = (wl - rainLow.l) * 0.5 * rainWander
            var r = (wr - rainLow.r) * 0.5 * rainWander
            l += dropSample(&drop.l, sr: sr)
            r += dropSample(&drop.r, sr: sr)
            return (l, r)
        case .wind:
            windPhase += 0.05 / sr
            if windPhase >= 1 { windPhase -= 1 }
            let swell = 0.6 + 0.4 * sin(2 * .pi * windPhase * 0.7)
            let l = windSample(&wind.l, centre: 300 + 900 * (0.5 + 0.5 * sin(2 * .pi * windPhase)), sr: sr)
            let r = windSample(&wind.r, centre: 300 + 900 * (0.5 + 0.5 * cos(2 * .pi * windPhase)), sr: sr)
            return (l * swell, r * swell)
        }
    }

    /// A single raindrop at a time per side: a short, bright, decaying ping.
    private mutating func dropSample(_ d: inout (freq: Double, phase: Double, amp: Double), sr: Double) -> Double {
        if d.amp < 1e-4, (white() + 1) / 2 < 25 / sr {
            d.freq = 2000 + (white() + 1) * 1500
            d.amp = 0.05 + (white() + 1) * 0.075
            d.phase = 0
        }
        guard d.amp >= 1e-4 else { return 0 }
        d.phase += d.freq / sr
        if d.phase >= 1 { d.phase -= 1 }
        let out = sin(2 * .pi * d.phase) * d.amp
        d.amp *= exp(-1 / (0.008 * sr))
        return out
    }

    /// State-variable band-pass, Q about 2.
    private mutating func windSample(_ s: inout (low: Double, band: Double), centre: Double, sr: Double) -> Double {
        let f = 2 * sin(.pi * min(centre, sr / 6) / sr)
        let q = 0.5
        let high = white() - s.low - q * s.band
        s.band += f * high
        s.low += f * s.band
        return s.band * 0.6
    }
}
```

- [ ] **Step 4: Implement `Voice.swift`**

```swift
import Foundation

/// One sounding note. Plain stored values only, so the voice pool is a flat
/// buffer the audio thread can walk without reference counting.
struct Voice {
    static let pluckSlotLength = 2048

    var active = false
    var layer: Layer = .pad
    var level = 0.0
    var velocity = 0.0
    var freq = 0.0
    var pan = 0.5
    private var age = 0
    private var attackSamples = 1
    private var holdSamples = 0
    private var releaseCoef = 0.999
    private var phases = SIMD4<Double>(repeating: 0)
    private var detune = SIMD4<Double>(1, 1, 1, 1)
    private var lp1 = 0.0
    private var lp2 = 0.0
    private var pluckSlot = 0
    private var pluckLength = 0
    private var pluckPos = 0

    static func frequency(midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    mutating func start(_ event: NoteEvent, sampleRate sr: Double, breathing: Bool, pluckSlot slot: Int,
                        pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank) {
        active = true
        layer = event.layer
        velocity = event.velocity
        freq = Self.frequency(midi: Double(event.midi))
        pan = 0.5 + 0.35 * sin(Double(event.midi) * 1.7)
        age = 0; level = 0; lp1 = 0; lp2 = 0
        phases = SIMD4(noise.white() * 0.5 + 0.5, noise.white() * 0.5 + 0.5, noise.white() * 0.5 + 0.5, 0)
        let (attack, release): (Double, Double)
        switch event.layer {
        case .pad: (attack, release) = (breathing ? 4 : 3, 2)
        case .drone: (attack, release) = (6, 3)
        case .bell: (attack, release) = (0.004, 0.9)
        case .pluck: (attack, release) = (0.002, 1.2)
        case .pulse: (attack, release) = (0.002, 0.12)
        case .bed, .texture: (attack, release) = (1, 1)
        }
        attackSamples = max(1, Int(attack * sr))
        holdSamples = Int(max(0, event.duration) * sr)
        releaseCoef = exp(-1 / (release * sr))
        detune = SIMD4(pow(2, -7.0 / 1200), 1, pow(2, 7.0 / 1200), 1)
        if layer == .pluck {
            pluckSlot = slot
            pluckLength = min(Self.pluckSlotLength, max(2, Int(sr / freq)))
            pluckPos = 0
            let base = pluckBuffers + slot * Self.pluckSlotLength
            var smooth = 0.0
            for k in 0..<pluckLength {
                smooth += (noise.white() - smooth) * 0.5
                base[k] = Float(smooth)
            }
        }
    }

    mutating func sample(sampleRate sr: Double, padCoef: Double, brightness: Double,
                         pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank) -> Double {
        guard active else { return 0 }
        if age < attackSamples {
            level = Double(age) / Double(attackSamples)
        } else if age < attackSamples + holdSamples {
            level = 1
        } else {
            level *= releaseCoef
            if level < 0.001 { active = false; return 0 }
        }
        age += 1
        let tau = 2 * Double.pi
        switch layer {
        case .pad:
            var s = 0.0
            for k in 0..<3 {
                phases[k] += freq * detune[k] / sr
                if phases[k] >= 1 { phases[k] -= 1 }
                s += 2 * phases[k] - 1
            }
            lp1 += padCoef * (s / 3 - lp1)
            lp2 += padCoef * (lp1 - lp2)
            return lp2 * 1.6 * level * velocity
        case .drone:
            phases[0] += freq / sr; if phases[0] >= 1 { phases[0] -= 1 }
            phases[1] += freq * 1.5 / sr; if phases[1] >= 1 { phases[1] -= 1 }
            return (sin(tau * phases[0]) + 0.3 * sin(tau * phases[1])) * 0.75 * level * velocity
        case .bell:
            phases[0] += freq / sr; if phases[0] >= 1 { phases[0] -= 1 }
            phases[1] += freq * 3.5 / sr; if phases[1] >= 1 { phases[1] -= 1 }
            let index = (0.5 + 2.5 * brightness) * level
            return sin(tau * phases[0] + index * sin(tau * phases[1])) * level * velocity
        case .pluck:
            let base = pluckBuffers + pluckSlot * Self.pluckSlotLength
            let next = pluckPos + 1 == pluckLength ? 0 : pluckPos + 1
            let out = Double(base[pluckPos])
            base[pluckPos] = Float(0.996 * 0.5 * (out + Double(base[next])))
            pluckPos = next
            return out * 1.4 * level * velocity
        case .pulse:
            let drop = 1 + exp(-Double(age) / (0.01 * sr))
            phases[0] += freq * drop / sr; if phases[0] >= 1 { phases[0] -= 1 }
            var s = sin(tau * phases[0])
            if Double(age) < 0.002 * sr { s += noise.white() * 0.3 }
            return s * level * velocity
        case .bed, .texture:
            return 0
        }
    }
}
```

- [ ] **Step 5: Implement `Reverb.swift`**

```swift
/// Freeverb's shape: four damped combs and two all-passes per side, the
/// right side's delays offset for width. Buffers are made once, up front.
struct Comb {
    private var buffer: [Float]
    private var index = 0
    private var store: Float = 0
    init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }
    mutating func process(_ x: Float, feedback: Float, damp: Float) -> Float {
        let y = buffer[index]
        store = y * (1 - damp) + store * damp
        buffer[index] = x + store * feedback
        index += 1; if index == buffer.count { index = 0 }
        return y
    }
}

struct Allpass {
    private var buffer: [Float]
    private var index = 0
    init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }
    mutating func process(_ x: Float) -> Float {
        let b = buffer[index]
        buffer[index] = x + b * 0.5
        index += 1; if index == buffer.count { index = 0 }
        return b - x
    }
}

struct Reverb {
    private var combsL: [Comb]
    private var combsR: [Comb]
    private var allL: [Allpass]
    private var allR: [Allpass]

    init(sampleRate: Double) {
        let scale = sampleRate / 44_100
        func n(_ v: Int) -> Int { Int(Double(v) * scale) }
        combsL = [1116, 1188, 1277, 1356].map { Comb(length: n($0)) }
        combsR = [1116, 1188, 1277, 1356].map { Comb(length: n($0 + 23)) }
        allL = [556, 441].map { Allpass(length: n($0)) }
        allR = [556, 441].map { Allpass(length: n($0 + 23)) }
    }

    /// `size` 0 to 1 sets the room; returns the wet signal only.
    mutating func process(_ l: Float, _ r: Float, size: Float) -> (Float, Float) {
        let input = (l + r) * 0.1
        let feedback = 0.7 + 0.14 * size
        var outL: Float = 0, outR: Float = 0
        for k in 0..<4 {
            outL += combsL[k].process(input, feedback: feedback, damp: 0.3)
            outR += combsR[k].process(input, feedback: feedback, damp: 0.3)
        }
        for k in 0..<2 { outL = allL[k].process(outL); outR = allR[k].process(outR) }
        return (outL * 0.5, outR * 0.5)
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `cd LifeOSKit && swift test --filter DSPTests`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Soundscape/DSP LifeOSKit/Tests/SoundscapeTests/DSPTests.swift
git commit -m "feat(soundscape): pad, bell, pluck, pulse and drone voices, noise textures and reverb"
```

---

### Task 5: The renderer and WAV writer

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/SoundscapeRenderer.swift`
- Create: `LifeOSKit/Sources/Soundscape/WAVWriter.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/RendererTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 to 4.
- Produces:
  - `final class SoundscapeRenderer: @unchecked Sendable`
  - `init(mood: Mood, sampleRate: Double = 48_000, seed: UInt64 = 1, parameters: SoundParameters)`
  - `func set(_ parameters: SoundParameters)`, safe from any thread
  - `func setLight(_ on: Bool)`, safe from any thread
  - `func chime()`, safe from any thread; plays one bell at the next sample
  - `func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int)`, for the audio thread only
  - `func render(seconds: Double) -> (left: [Float], right: [Float])`, offline (the CLI uses it for whole minutes)
  - `var isLight: Bool`, readable after render
  - `enum WAVWriter { static func data(left: [Float], right: [Float], sampleRate: Int) -> Data }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Soundscape

@Suite struct RendererTests {
    func params(_ mood: Mood, phase: SoundPhase = .work, texture: Texture = .auto, weather: WeatherInput? = nil) -> SoundParameters {
        .make(.for(mood), Conditions(date: Date(timeIntervalSince1970: 1_791_460_800), timeZone: TimeZone(identifier: "UTC")!,
                                     phase: phase, weather: weather, texture: texture))
    }

    @Test(arguments: Mood.allCases)
    func everyMoodMakesSoundUnderZeroDecibels(_ mood: Mood) {
        let r = SoundscapeRenderer(mood: mood, seed: 4, parameters: params(mood, weather: WeatherInput(kind: .rain, windKph: 40)))
        let (l, rr) = r.render(seconds: 20)
        #expect(l.count == 960_000 && rr.count == 960_000)
        #expect(l.allSatisfy { $0.isFinite && abs($0) < 1 })
        #expect(rr.allSatisfy { $0.isFinite && abs($0) < 1 })
        let rms = sqrt(l.map { Double($0 * $0) }.reduce(0, +) / Double(l.count))
        #expect(rms > 0.01, "\(mood) is nearly silent: \(rms)")
    }

    @Test func theSameSeedRendersTheSameAudio() {
        let a = SoundscapeRenderer(mood: .focus, seed: 9, parameters: params(.focus)).render(seconds: 5)
        let b = SoundscapeRenderer(mood: .focus, seed: 9, parameters: params(.focus)).render(seconds: 5)
        #expect(a.left == b.left)
    }

    @Test func aFinishedFadeIsSilent() {
        let r = SoundscapeRenderer(mood: .sleep, seed: 1, parameters: params(.sleep, phase: .fading(1)))
        let (l, _) = r.render(seconds: 2)
        #expect(l.map(abs).max()! < 1e-3)
    }

    @Test func newParametersGlideRatherThanJump() {
        let r = SoundscapeRenderer(mood: .focus, seed: 2, parameters: params(.focus))
        _ = r.render(seconds: 10)
        r.set(params(.focus, phase: .fading(1)))
        let (l, _) = r.render(seconds: 12)
        let firstHalfSecond = l[0..<24_000].map(abs).max()!
        let last = l[(l.count - 24_000)...].map(abs).max()!
        #expect(firstHalfSecond > 0.01)
        #expect(last < firstHalfSecond * 0.1)
    }

    @Test func lightModeDropsStruckLayersAndStillPlays() {
        let r = SoundscapeRenderer(mood: .brainstorm, seed: 3, parameters: params(.brainstorm))
        r.setLight(true)
        let (l, _) = r.render(seconds: 10)
        #expect(r.isLight)
        #expect(l.contains { abs($0) > 0.01 })
    }

    @Test func aChimeIsHeardEvenWhenBellsAreMuted() {
        // Bells are muted this late in a fade and the master is low: the chime
        // has its own gain and sits after the master.
        let quiet = SoundscapeRenderer(mood: .sleep, seed: 1, parameters: params(.sleep, phase: .fading(0.9)))
        _ = quiet.render(seconds: 8)
        quiet.chime()
        let (l, _) = quiet.render(seconds: 1)
        #expect(l.map(abs).max()! > 0.05)
    }

    @Test func rendersFasterThanRealTimeEvenInDebug() {
        let r = SoundscapeRenderer(mood: .brainstorm, seed: 5, parameters: params(.brainstorm, weather: WeatherInput(kind: .rain, windKph: 5)))
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = r.render(seconds: 120) }
        // Two minutes of the busiest mood in under two minutes on an unoptimised
        // build; release builds are several times faster.
        #expect(elapsed < .seconds(120), "\(elapsed)")
    }

    @Test func wavHeaderIsStandard() {
        let data = WAVWriter.data(left: [0, 0.5, -0.5], right: [0, 0.5, -0.5], sampleRate: 48_000)
        #expect(data.count == 44 + 3 * 4)
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(String(data: data[36..<40], encoding: .ascii) == "data")
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 48_000)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter RendererTests`
Expected: compile failure, `cannot find 'SoundscapeRenderer' in scope`.

- [ ] **Step 3: Implement `SoundscapeRenderer.swift`**

```swift
import Foundation
import Synchronization

/// Plays one mood. `set`, `setLight` and `chime` may be called from any
/// thread; `render` only from the audio thread (or offline). Everything the
/// render path touches is allocated in `init`.
public final class SoundscapeRenderer: @unchecked Sendable {
    public let mood: Mood
    public let sampleRate: Double
    public private(set) var isLight = false

    private static let block = 64
    private static let voiceCount = 40
    private static let pluckSlots = 8
    private static let glideSeconds = 3.0

    private let inbox = Mutex<SoundParameters?>(nil)
    private let lightRequest = Atomic<Bool>(false)
    private let chimeRequest = Atomic<Bool>(false)

    private var target: SoundParameters
    private var current: SoundParameters
    private var composer: Composer
    private var events: [NoteEvent]
    private var nextEvent = 0
    private var samplesIntoBar = 0
    private var barSamples = 0
    private let voices: UnsafeMutablePointer<Voice>
    private let pluckBuffers: UnsafeMutablePointer<Float>
    private var nextPluckSlot = 0
    private var noise: NoiseBank
    private var reverb: Reverb
    private var breathPhase = 0.0
    private var padCoef = 0.1
    private var overruns = 0
    /// The voice playing a chime, which ignores layer gains and the master.
    private var chimeVoice: Int?

    public init(mood: Mood, sampleRate: Double = 48_000, seed: UInt64 = 1, parameters: SoundParameters) {
        self.mood = mood
        self.sampleRate = sampleRate
        self.target = parameters
        self.current = parameters
        self.composer = Composer(recipe: .for(mood), seed: seed)
        self.events = []
        self.events.reserveCapacity(128)
        self.voices = .allocate(capacity: Self.voiceCount)
        self.voices.initialize(repeating: Voice(), count: Self.voiceCount)
        self.pluckBuffers = .allocate(capacity: Self.pluckSlots * Voice.pluckSlotLength)
        self.pluckBuffers.initialize(repeating: 0, count: Self.pluckSlots * Voice.pluckSlotLength)
        self.noise = NoiseBank(seed: UInt32(truncatingIfNeeded: seed &* 2_654_435_761) | 1)
        self.reverb = Reverb(sampleRate: sampleRate)
    }

    deinit {
        voices.deinitialize(count: Self.voiceCount); voices.deallocate()
        pluckBuffers.deallocate()
    }

    public func set(_ parameters: SoundParameters) { inbox.withLock { $0 = parameters } }
    public func setLight(_ on: Bool) { lightRequest.store(on, ordering: .relaxed) }
    public func chime() { chimeRequest.store(true, ordering: .relaxed) }

    public func render(seconds: Double) -> (left: [Float], right: [Float]) {
        let frames = Int(seconds * sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                render(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
            }
        }
        return (left, right)
    }

    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let began = ContinuousClock.now
        if let fresh = inbox.withLockIfAvailable({ value -> SoundParameters? in
            defer { value = nil }
            return value
        }), let parameters = fresh {
            target = parameters
        }
        isLight = lightRequest.load(ordering: .relaxed) || overruns >= 8
        if chimeRequest.exchange(false, ordering: .relaxed) {
            chimeVoice = trigger(NoteEvent(layer: .bell, midi: composer.midi(degree: composer.recipe.scale.count * 2, keyOffset: current.keyOffset),
                                           velocity: 0.9, offset: 0, duration: 0), force: true)
        }
        var done = 0
        while done < frames {
            let n = min(Self.block, frames - done)
            glide(samples: n)
            renderBlock(left + done, right + done, n)
            done += n
        }
        // Light mode after eight renders in a row that used most of their
        // time budget; it clears once renders are comfortably fast again.
        let budget = Double(frames) / sampleRate
        let took = began.duration(to: .now)
        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) * 1e-18
        if seconds > budget * 0.7 { overruns = min(overruns + 1, 16) } else if seconds < budget * 0.3 { overruns = max(overruns - 1, 0) }
    }

    private func glide(samples: Int) {
        let c = 1 - exp(-Double(samples) / (sampleRate * Self.glideSeconds))
        func step(_ a: inout Double, _ b: Double) { a += (b - a) * c }
        step(&current.tempo, target.tempo)
        step(&current.density, target.density)
        step(&current.brightness, target.brightness)
        step(&current.reverb, target.reverb)
        step(&current.master, target.master)
        step(&current.bedColour, target.bedColour)
        current.gains += (target.gains - current.gains) * c
        if let to = target.breathPeriod {
            current.breathPeriod = (current.breathPeriod ?? to) + (to - (current.breathPeriod ?? to)) * c
        } else {
            current.breathPeriod = nil
        }
        current.keyOffset = target.keyOffset
        current.texture = target.texture
        let fc = 250 + current.brightness * current.brightness * 3500
        padCoef = 1 - exp(-2 * Double.pi * fc / sampleRate)
    }

    private func startBar() {
        composer.nextBar(current, into: &events)
        nextEvent = 0
        samplesIntoBar = 0
        barSamples = max(1, Int(current.barSeconds * sampleRate))
    }

    @discardableResult
    private func trigger(_ event: NoteEvent, force: Bool = false) -> Int? {
        if isLight, !force, event.layer == .bell || event.layer == .pluck || event.layer == .pulse { return nil }
        var pick = 0
        var quietest = Double.infinity
        for i in 0..<Self.voiceCount {
            if !voices[i].active { pick = i; quietest = -1; break }
            if voices[i].level < quietest { quietest = voices[i].level; pick = i }
        }
        let slot = nextPluckSlot
        if event.layer == .pluck { nextPluckSlot = (nextPluckSlot + 1) % Self.pluckSlots }
        if pick == chimeVoice { chimeVoice = nil }
        voices[pick].start(event, sampleRate: sampleRate, breathing: current.breathPeriod != nil,
                           pluckSlot: slot, pluckBuffers: pluckBuffers, noise: &noise)
        return pick
    }

    private func renderBlock(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ n: Int) {
        let gains = current.gains
        let bedGain = gains[Layer.bed.rawValue]
        let textureGain = gains[Layer.texture.rawValue]
        let wet = Float(isLight ? 0 : 0.15 + 0.35 * current.reverb)
        let size = Float(current.reverb)
        for s in 0..<n {
            if samplesIntoBar >= barSamples { startBar() }
            while nextEvent < events.count, Int(events[nextEvent].offset * sampleRate) <= samplesIntoBar {
                trigger(events[nextEvent]); nextEvent += 1
            }
            samplesIntoBar += 1

            var swell = 1.0
            if let period = current.breathPeriod {
                breathPhase += 1 / (period * sampleRate)
                if breathPhase >= 1 { breathPhase -= 1 }
                let inhale = 0.4
                let x = breathPhase < inhale ? breathPhase / inhale : (breathPhase - inhale) / (1 - inhale)
                let shape = breathPhase < inhale ? 0.5 - 0.5 * cos(.pi * x) : 0.5 + 0.5 * cos(.pi * x)
                swell = 0.55 + 0.45 * shape
            }

            var l = 0.0, r = 0.0, chime = 0.0
            for i in 0..<Self.voiceCount where voices[i].active {
                let layer = voices[i].layer
                let raw = voices[i].sample(sampleRate: sampleRate, padCoef: padCoef, brightness: current.brightness,
                                           pluckBuffers: pluckBuffers, noise: &noise)
                if i == chimeVoice { chime += raw * 0.6; continue }
                var x = raw * gains[layer.rawValue]
                if layer == .pad || layer == .drone { x *= swell }
                let pan = voices[i].pan
                l += x * cos(pan * .pi / 2)
                r += x * sin(pan * .pi / 2)
            }
            if let c = chimeVoice, !voices[c].active { chimeVoice = nil }
            if bedGain > 0 {
                let (bl, br) = noise.bed(colour: current.bedColour)
                l += bl * bedGain * swell; r += br * bedGain * swell
            }
            if textureGain > 0, current.texture != .none {
                let (tl, tr) = noise.texture(current.texture, sampleRate: sampleRate)
                l += tl * textureGain; r += tr * textureGain
            }
            var fl = Float(l * 0.5), fr = Float(r * 0.5)
            if wet > 0 {
                let (rl, rr) = reverb.process(fl, fr, size: size)
                fl += rl * wet; fr += rr * wet
            }
            let master = Float(current.master)
            left[s] = 0.95 * tanh(fl * master + Float(chime))
            right[s] = 0.95 * tanh(fr * master + Float(chime))
        }
    }
}
```

`tanh` on `Float` comes from Foundation. `0.95 * tanh(x)` keeps every sample strictly under 1 (0 dBFS).

- [ ] **Step 4: Implement `WAVWriter.swift`**

```swift
import Foundation

/// 16-bit stereo PCM, for listening while tuning.
public enum WAVWriter {
    public static func data(left: [Float], right: [Float], sampleRate: Int) -> Data {
        let frames = min(left.count, right.count)
        let bytes = frames * 4
        var d = Data(capacity: 44 + bytes)
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + bytes)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        ascii("data"); u32(UInt32(bytes))
        for i in 0..<frames {
            for s in [left[i], right[i]] {
                u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767)))
            }
        }
        return d
    }
}
```

- [ ] **Step 5: Run the tests**

Also run the performance bound once in release to see real headroom: `cd LifeOSKit && swift test -c release --filter rendersFasterThanRealTimeEvenInDebug` (expect well under 20 s).

Run: `cd LifeOSKit && swift test --filter RendererTests`
Expected: all pass. If `everyMoodMakesSoundUnderZeroDecibels` reports a mood nearly silent, raise that recipe's pad gain in Task 1's recipe rather than lowering the threshold, and re-run `MoodRecipeTests`.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Soundscape LifeOSKit/Tests/SoundscapeTests/RendererTests.swift
git commit -m "feat(soundscape): a renderer that glides between parameters, plays live or offline, and writes WAVs"
```

---

### Task 6: `soundscape-render` and the listening set

**Files:**
- Modify: `LifeOSKit/Sources/soundscape-render/main.swift`
- Create: `scripts/render-soundscapes.sh`

**Interfaces:**
- Consumes: `SoundscapeRenderer`, `SoundParameters.make`, `Conditions`, `WAVWriter`, `WeatherInput`.
- Produces: the CLI `swift run soundscape-render --mood <m> --minutes <n> --hour <h> [--hr <bpm>] [--weather rain|snow|wind|clear] [--seed <n>] [--out <path>]`, and the script that writes the listening set into a directory.

- [ ] **Step 1: Implement the CLI**

```swift
import Foundation
import Soundscape

/// Writes a soundscape to a WAV for listening while tuning.
var options: [String: String] = [:]
var args = CommandLine.arguments.dropFirst().makeIterator()
while let key = args.next() {
    guard key.hasPrefix("--"), let value = args.next() else {
        FileHandle.standardError.write(Data("usage: soundscape-render --mood focus --minutes 3 --hour 9 [--hr 95] [--weather rain] [--seed 7] [--out file.wav]\n".utf8))
        exit(2)
    }
    options[String(key.dropFirst(2))] = value
}

guard let mood = Mood(rawValue: options["mood"] ?? "focus") else {
    FileHandle.standardError.write(Data("unknown mood; use focus, brainstorm, relax or sleep\n".utf8)); exit(2)
}
let minutes = Double(options["minutes"] ?? "3") ?? 3
let hour = Int(options["hour"] ?? "14") ?? 14
let seed = UInt64(options["seed"] ?? "7") ?? 7
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
let weather: WeatherInput? = switch options["weather"] {
case "rain": WeatherInput(kind: .rain, windKph: 5)
case "snow": WeatherInput(kind: .snow, windKph: 5)
case "wind": WeatherInput(kind: .clear, windKph: 45)
case "clear": WeatherInput(kind: .clear, windKph: 5)
default: nil
}
let conditions = Conditions(date: date, heartRate: options["hr"].flatMap(Double.init), restingHeartRate: 60,
                            phase: mood == .sleep ? .fading(0.2) : .work, weather: weather)
let parameters = SoundParameters.make(.for(mood), conditions)
let renderer = SoundscapeRenderer(mood: mood, sampleRate: 48_000, seed: seed, parameters: parameters)
let (left, right) = renderer.render(seconds: minutes * 60)
let out = options["out"] ?? "\(mood.rawValue)-\(hour)h\(options["hr"].map { "-hr\($0)" } ?? "")\(options["weather"].map { "-\($0)" } ?? "").wav"
try WAVWriter.data(left: left, right: right, sampleRate: 48_000).write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
```

- [ ] **Step 2: Write `scripts/render-soundscapes.sh`**

```bash
#!/bin/sh
# Renders the listening set: each mood at 09:00 and 23:00, at rest and with a
# high heart rate, and with rain. Usage: scripts/render-soundscapes.sh <out-dir>
set -e
out="${1:?usage: scripts/render-soundscapes.sh <out-dir>}"
mkdir -p "$out"
cd "$(dirname "$0")/../LifeOSKit"
swift build -c release --product soundscape-render
bin="$(swift build -c release --show-bin-path)/soundscape-render"
for mood in focus brainstorm relax sleep; do
  "$bin" --mood "$mood" --minutes 2 --hour 9 --out "$out/$mood-morning.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 23 --out "$out/$mood-night.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 14 --hr 105 --out "$out/$mood-high-hr.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 14 --weather rain --out "$out/$mood-rain.wav"
done
```

`chmod +x scripts/render-soundscapes.sh`.

- [ ] **Step 3: Run it**

Run: `scripts/render-soundscapes.sh /private/tmp/claude-501/-Users-shivvyas-LIfeOS/b2439d0c-8c01-496a-98e7-5a704564dfbf/scratchpad/soundscapes`
Expected: 16 files of about 23 MB each, each printed as `wrote ...`. Open two with `afplay -t 10 <file>` and confirm they play.

- [ ] **Step 4: Commit**

```bash
git add LifeOSKit/Sources/soundscape-render scripts/render-soundscapes.sh
git commit -m "feat(soundscape): render any mood to a WAV for tuning by ear"
```

---

### Task 7: The timer

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/FocusTimer.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/FocusTimerTests.swift`

**Interfaces:**
- Consumes: `SoundPhase` (Task 2).
- Produces:
  - `TimerPlan`: `pomodoro(work:rest:longRest:longEvery:blocks:)`, `countdown(TimeInterval?)`, `fade(TimeInterval?)`
  - `TimerPhase`: `work(block:)`, `rest(afterBlock:)`, `longRest(afterBlock:)`, `open`, `fading`, `finished`
  - `TimerReading` fields `phase, phaseLength, remaining, completedBlocks, focusedSeconds, isPaused`, computed `progress`
  - `PhaseEnd(ending:next:at:)`
  - `FocusTimer(plan:startedAt:)` with `reading(at:)`, `pause(at:)`, `resume(at:)`, `skip(at:)`, `upcomingEnds(after:limit:)`, `plan`
  - `SoundPhase.init(_ reading: TimerReading)`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Soundscape

@Suite struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let classic = TimerPlan.pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: 4)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aPomodoroWalksThroughItsBlocks() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        #expect(timer.reading(at: at(0)).phase == .work(block: 1))
        #expect(timer.reading(at: at(0)).remaining == 1500)
        #expect(timer.reading(at: at(1500)).phase == .rest(afterBlock: 1))
        #expect(timer.reading(at: at(1800)).phase == .work(block: 2))
        #expect(timer.reading(at: at(1800)).completedBlocks == 1)
        #expect(timer.reading(at: at(1860)).focusedSeconds == 1560)
        #expect(timer.reading(at: at(6899)).phase == .work(block: 4))
        let done = timer.reading(at: at(6900))
        #expect(done.phase == .finished)
        #expect(done.completedBlocks == 4)
        #expect(done.focusedSeconds == 6000)
    }

    @Test func anOpenEndedPomodoroTakesALongBreakAfterEveryFourth() {
        let timer = FocusTimer(plan: .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: nil), startedAt: t0)
        // Four blocks and three short breaks: 6900 s.
        #expect(timer.reading(at: at(6900)).phase == .longRest(afterBlock: 4))
        #expect(timer.reading(at: at(6900)).remaining == 900)
        #expect(timer.reading(at: at(7800)).phase == .work(block: 5))
    }

    @Test func aLongGapLandsInTheRightPhase() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        // Locked for two hours: the session finished while the phone slept.
        #expect(timer.reading(at: at(7200)).phase == .finished)
        let open = FocusTimer(plan: .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: nil), startedAt: t0)
        // 3 h = 10800 s. One full cycle is 4*1500 + 3*300 + 900 = 7800 s; block 5 runs 7800 to 9300,
        // a break to 9600, then block 6 from 9600: 1200 s in, 300 s left.
        #expect(open.reading(at: at(10_800)).phase == .work(block: 6))
        #expect(open.reading(at: at(10_800)).remaining == 300)
    }

    @Test func skipAndPauseKeepTheClock() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(600))
        #expect(timer.reading(at: at(5000)).remaining == 900)
        #expect(timer.reading(at: at(5000)).isPaused)
        timer.resume(at: at(5000))
        #expect(timer.reading(at: at(5900)).phase == .rest(afterBlock: 1))
        timer.skip(at: at(5960))
        #expect(timer.reading(at: at(5960)).phase == .work(block: 2))
        #expect(timer.reading(at: at(5960)).remaining == 1500)
        #expect(timer.reading(at: at(5960)).focusedSeconds == 1500)
    }

    @Test func skippingWorkCountsWhatWasDone() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.skip(at: at(100))
        let r = timer.reading(at: at(100))
        #expect(r.phase == .rest(afterBlock: 1))
        #expect(r.focusedSeconds == 100)
    }

    @Test func skipWhilePausedStaysPaused() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(200))
        timer.skip(at: at(400))
        #expect(timer.reading(at: at(900)).phase == .rest(afterBlock: 1))
        #expect(timer.reading(at: at(900)).remaining == 300)
    }

    @Test func countdownAndOpenEnded() {
        let twenty = FocusTimer(plan: .countdown(1200), startedAt: t0)
        #expect(twenty.reading(at: at(100)).phase == .open)
        #expect(twenty.reading(at: at(100)).remaining == 1100)
        #expect(twenty.reading(at: at(1200)).phase == .finished)
        let open = FocusTimer(plan: .countdown(nil), startedAt: t0)
        #expect(open.reading(at: at(100_000)).phase == .open)
        #expect(open.reading(at: at(100_000)).remaining == nil)
        #expect(open.reading(at: at(100)).focusedSeconds == 100)
    }

    @Test func sleepFadesThenFinishesAndAllNightNeverDoes() {
        let fade = FocusTimer(plan: .fade(1800), startedAt: t0)
        #expect(fade.reading(at: at(900)).phase == .fading)
        #expect(fade.reading(at: at(900)).progress == 0.5)
        #expect(fade.reading(at: at(1800)).phase == .finished)
        #expect(FocusTimer(plan: .fade(nil), startedAt: t0).reading(at: at(40_000)).phase == .open)
    }

    @Test func soundPhaseFollowsTheReading() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        #expect(SoundPhase(timer.reading(at: at(100))) == .work)
        #expect(SoundPhase(timer.reading(at: at(1470))) == .closing(0.5))
        #expect(SoundPhase(timer.reading(at: at(1600))) == .rest)
        #expect(SoundPhase(FocusTimer(plan: .fade(1000), startedAt: t0).reading(at: at(250))) == .fading(0.25))
        #expect(SoundPhase(timer.reading(at: at(99_999))) == .fading(1))
    }

    @Test func upcomingEndsListTheNextBoundaries() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        let ends = timer.upcomingEnds(after: at(10), limit: 12)
        #expect(ends.count == 7)
        #expect(ends[0] == PhaseEnd(ending: .work(block: 1), next: .rest(afterBlock: 1), at: at(1500)))
        #expect(ends.last == PhaseEnd(ending: .work(block: 4), next: .finished, at: at(6900)))
        var paused = timer; paused.pause(at: at(10))
        #expect(paused.upcomingEnds(after: at(10), limit: 12).isEmpty)
        #expect(FocusTimer(plan: .countdown(nil), startedAt: t0).upcomingEnds(after: at(0), limit: 12).isEmpty)
    }

    @Test func aTimerSurvivesEncoding() throws {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(30))
        let copy = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
        #expect(copy == timer)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FocusTimerTests`
Expected: compile failure, `cannot find 'FocusTimer' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum TimerPlan: Codable, Equatable, Sendable {
    /// `blocks` nil runs until ended.
    case pomodoro(work: TimeInterval, rest: TimeInterval, longRest: TimeInterval, longEvery: Int, blocks: Int?)
    /// nil is open-ended.
    case countdown(TimeInterval?)
    /// nil plays all night without fading.
    case fade(TimeInterval?)
}

public enum TimerPhase: Codable, Equatable, Sendable {
    case work(block: Int)
    case rest(afterBlock: Int)
    case longRest(afterBlock: Int)
    case open
    case fading
    case finished
}

public struct TimerReading: Equatable, Sendable {
    public var phase: TimerPhase
    public var phaseLength: TimeInterval?
    public var remaining: TimeInterval?
    public var completedBlocks: Int
    public var focusedSeconds: TimeInterval
    public var isPaused: Bool
    public var progress: Double? {
        guard let phaseLength, phaseLength > 0, let remaining else { return nil }
        return 1 - remaining / phaseLength
    }
}

public struct PhaseEnd: Equatable, Sendable {
    public var ending: TimerPhase
    public var next: TimerPhase
    public var at: Date
}

/// The session clock: a run of segments (work, breaks, a countdown, a
/// fade) measured from wall-clock dates, so a suspended app reads it right.
public struct FocusTimer: Codable, Equatable, Sendable {
    public let plan: TimerPlan
    private var segment = 0
    private var segmentStart: Date
    private var pausedAt: Date?
    /// Focused seconds from segments before `segment`.
    private var banked: TimeInterval = 0

    public init(plan: TimerPlan, startedAt: Date) {
        self.plan = plan
        self.segmentStart = startedAt
    }

    private var segmentCount: Int? {
        switch plan {
        case .pomodoro(_, _, _, _, let blocks): blocks.map { 2 * $0 - 1 }
        case .countdown, .fade: 1
        }
    }

    private func phase(of index: Int) -> TimerPhase {
        if let count = segmentCount, index >= count { return .finished }
        switch plan {
        case .pomodoro(_, _, _, let every, _):
            if index % 2 == 0 { return .work(block: index / 2 + 1) }
            let block = (index + 1) / 2
            return block % max(1, every) == 0 ? .longRest(afterBlock: block) : .rest(afterBlock: block)
        case .countdown: return .open
        case .fade(let length): return length == nil ? .open : .fading
        }
    }

    private func length(of index: Int) -> TimeInterval? {
        switch plan {
        case .pomodoro(let work, let rest, let longRest, _, _):
            if index % 2 == 0 { return work }
            if case .longRest = phase(of: index) { return longRest }
            return rest
        case .countdown(let length), .fade(let length): return length
        }
    }

    private func counts(_ index: Int) -> Bool {
        if case .pomodoro = plan { return index % 2 == 0 }
        return true
    }

    private func completed(before index: Int) -> Int {
        guard case .pomodoro = plan else { return 0 }
        return (index + 1) / 2
    }

    /// The segment holding `clock`, its start, and the focus banked before it.
    private func locate(_ clock: Date) -> (index: Int, start: Date, banked: TimeInterval) {
        var index = segment, start = segmentStart, total = banked
        while true {
            if let count = segmentCount, index >= count { break }
            guard let length = length(of: index), clock.timeIntervalSince(start) >= length else { break }
            if counts(index) { total += length }
            start = start.addingTimeInterval(length)
            index += 1
        }
        return (index, start, total)
    }

    public func reading(at now: Date) -> TimerReading {
        let clock = pausedAt ?? now
        let (index, start, total) = locate(clock)
        let phase = phase(of: index)
        if phase == .finished {
            return TimerReading(phase: .finished, phaseLength: nil, remaining: nil,
                                completedBlocks: completed(before: index), focusedSeconds: total, isPaused: pausedAt != nil)
        }
        let elapsed = max(0, clock.timeIntervalSince(start))
        let length = length(of: index)
        return TimerReading(phase: phase, phaseLength: length, remaining: length.map { max(0, $0 - elapsed) },
                            completedBlocks: completed(before: index),
                            focusedSeconds: total + (counts(index) ? elapsed : 0), isPaused: pausedAt != nil)
    }

    private mutating func settle(at now: Date) {
        let (index, start, total) = locate(pausedAt ?? now)
        segment = index; segmentStart = start; banked = total
    }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        settle(at: now)
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        segmentStart = segmentStart.addingTimeInterval(now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    public mutating func skip(at now: Date) {
        settle(at: now)
        if let count = segmentCount, segment >= count { return }
        let clock = pausedAt ?? now
        if counts(segment) {
            let elapsed = max(0, clock.timeIntervalSince(segmentStart))
            banked += min(elapsed, length(of: segment) ?? elapsed)
        }
        segment += 1
        segmentStart = clock
    }

    /// The next boundaries, for notifications. Empty while paused.
    public func upcomingEnds(after now: Date, limit: Int) -> [PhaseEnd] {
        guard pausedAt == nil else { return [] }
        var (index, start, _) = locate(now)
        var ends: [PhaseEnd] = []
        while ends.count < limit, phase(of: index) != .finished, let length = length(of: index) {
            let end = start.addingTimeInterval(length)
            ends.append(PhaseEnd(ending: phase(of: index), next: phase(of: index + 1), at: end))
            start = end
            index += 1
        }
        return ends
    }
}

extension SoundPhase {
    public init(_ reading: TimerReading) {
        switch reading.phase {
        case .work:
            if let remaining = reading.remaining, remaining <= 60 { self = .closing(1 - remaining / 60) } else { self = .work }
        case .rest, .longRest: self = .rest
        case .open: self = .work
        case .fading: self = .fading(reading.progress ?? 0)
        case .finished: self = .fading(1)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd LifeOSKit && swift test --filter FocusTimerTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Soundscape/FocusTimer.swift LifeOSKit/Tests/SoundscapeTests/FocusTimerTests.swift
git commit -m "feat(soundscape): a wall-clock Pomodoro, countdown and sleep-fade timer"
```

---

### Task 8: Setup, presets, preferences and source fallback

**Files:**
- Create: `LifeOSKit/Sources/Soundscape/FocusSetup.swift`
- Test: `LifeOSKit/Tests/SoundscapeTests/FocusSetupTests.swift`

**Interfaces:**
- Consumes: `Mood`, `Texture`, `TimerPlan`.
- Produces:
  - `SoundSource` (`soundscape, appleMusic, silence`; `title`)
  - `TimerPreset(id:title:)`
  - `Mood.presets: [TimerPreset]`
  - `FocusSetup(mood:source:presetID:blocks:texture:)` with computed `plan: TimerPlan` and `static func standard(for:)`
  - `FocusPreferences` with `lastMood`, `func setup(for:) -> FocusSetup`, `mutating func remember(_:)`, `static func load(from: UserDefaults, key: String)`, and `func save(to:key:)`
  - `MusicAvailability` (`available, notSubscribed, denied, unknown`)
  - `func resolveSource(_ requested: SoundSource, music: MusicAvailability) -> (source: SoundSource, notice: String?)`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Soundscape

@Suite struct FocusSetupTests {
    @Test func presetsMatchTheSpec() {
        #expect(Mood.focus.presets.map(\.id) == ["25-5", "50-10", "90-20"])
        #expect(Mood.brainstorm.presets.map(\.id) == ["25-5", "50-10", "90-20"])
        #expect(Mood.relax.presets.map(\.id) == ["10", "20", "30", "open"])
        #expect(Mood.sleep.presets.map(\.id) == ["15", "30", "60", "night"])
    }

    @Test func theDefaultFocusIsTwentyFiveFiveFourTimes() {
        let setup = FocusSetup.standard(for: .focus)
        #expect(setup.plan == .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: 4))
        #expect(setup.source == .soundscape && setup.texture == .auto)
    }

    @Test func plansFollowThePresetAndBlocks() {
        var setup = FocusSetup.standard(for: .brainstorm)
        setup.presetID = "90-20"; setup.blocks = nil
        #expect(setup.plan == .pomodoro(work: 5400, rest: 1200, longRest: 1800, longEvery: 4, blocks: nil))
        #expect(FocusSetup(mood: .relax, presetID: "open").plan == .countdown(nil))
        #expect(FocusSetup(mood: .relax, presetID: "20").plan == .countdown(1200))
        #expect(FocusSetup(mood: .sleep, presetID: "night").plan == .fade(nil))
        #expect(FocusSetup(mood: .sleep, presetID: "60").plan == .fade(3600))
    }

    @Test func anUnknownPresetFallsBackToTheMoodsDefault() {
        #expect(FocusSetup(mood: .sleep, presetID: "25-5").plan == .fade(1800))
    }

    @Test func preferencesRememberEachMoodAndTheLastOne() {
        let defaults = UserDefaults(suiteName: "FocusSetupTests-\(UUID())")!
        var prefs = FocusPreferences.load(from: defaults, key: "focus")
        #expect(prefs.lastMood == .focus)
        prefs.remember(FocusSetup(mood: .sleep, source: .appleMusic, presetID: "60", texture: .rain))
        prefs.save(to: defaults, key: "focus")
        let back = FocusPreferences.load(from: defaults, key: "focus")
        #expect(back.lastMood == .sleep)
        #expect(back.setup(for: .sleep).presetID == "60")
        #expect(back.setup(for: .sleep).texture == .rain)
        #expect(back.setup(for: .focus) == .standard(for: .focus))
    }

    @Test func appleMusicFallsBackWithANotice() {
        let ok = resolveSource(.appleMusic, music: .available)
        #expect(ok.source == .appleMusic && ok.notice == nil)
        let none = resolveSource(.appleMusic, music: .notSubscribed)
        #expect(none.source == .soundscape && none.notice == "Apple Music needs a subscription. Playing a soundscape instead.")
        let denied = resolveSource(.appleMusic, music: .denied)
        #expect(denied.source == .soundscape && denied.notice == "Allow Apple Music for Almanac in Settings. Playing a soundscape instead.")
        #expect(resolveSource(.appleMusic, music: .unknown).source == .soundscape)
        let silent = resolveSource(.silence, music: .denied)
        #expect(silent.source == .silence && silent.notice == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FocusSetupTests`
Expected: compile failure, `cannot find 'FocusSetup' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum SoundSource: String, CaseIterable, Codable, Sendable {
    case soundscape, appleMusic, silence
    public var title: String {
        switch self { case .soundscape: "Soundscape"; case .appleMusic: "Apple Music"; case .silence: "Silence" }
    }
}

public struct TimerPreset: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
}

extension Mood {
    public var presets: [TimerPreset] {
        switch self {
        case .focus, .brainstorm:
            [.init(id: "25-5", title: "25 / 5"), .init(id: "50-10", title: "50 / 10"), .init(id: "90-20", title: "90 / 20")]
        case .relax:
            [.init(id: "10", title: "10 min"), .init(id: "20", title: "20 min"), .init(id: "30", title: "30 min"), .init(id: "open", title: "Open")]
        case .sleep:
            [.init(id: "15", title: "15 min"), .init(id: "30", title: "30 min"), .init(id: "60", title: "60 min"), .init(id: "night", title: "All night")]
        }
    }

    var standardPresetID: String {
        switch self { case .focus, .brainstorm: "25-5"; case .relax: "20"; case .sleep: "30" }
    }
}

public struct FocusSetup: Codable, Equatable, Sendable {
    public var mood: Mood
    public var source: SoundSource
    public var presetID: String
    /// Pomodoro block count; nil runs until ended.
    public var blocks: Int?
    public var texture: Texture

    public init(mood: Mood, source: SoundSource = .soundscape, presetID: String, blocks: Int? = 4, texture: Texture = .auto) {
        self.mood = mood; self.source = source; self.presetID = presetID; self.blocks = blocks; self.texture = texture
    }

    public static func standard(for mood: Mood) -> FocusSetup { FocusSetup(mood: mood, presetID: mood.standardPresetID) }

    public var plan: TimerPlan {
        let id = mood.presets.contains { $0.id == presetID } ? presetID : mood.standardPresetID
        switch (mood, id) {
        case (.focus, "50-10"), (.brainstorm, "50-10"): return .pomodoro(work: 3000, rest: 600, longRest: 1200, longEvery: 4, blocks: blocks)
        case (.focus, "90-20"), (.brainstorm, "90-20"): return .pomodoro(work: 5400, rest: 1200, longRest: 1800, longEvery: 4, blocks: blocks)
        case (.focus, _), (.brainstorm, _): return .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: blocks)
        case (.relax, "open"): return .countdown(nil)
        case (.relax, let minutes): return .countdown((Double(minutes) ?? 20) * 60)
        case (.sleep, "night"): return .fade(nil)
        case (.sleep, let minutes): return .fade((Double(minutes) ?? 30) * 60)
        }
    }
}

/// What each mood was last set to, so Start is one tap.
public struct FocusPreferences: Codable, Equatable, Sendable {
    public private(set) var lastMood: Mood = .focus
    private var perMood: [String: FocusSetup] = [:]

    public init() {}

    public func setup(for mood: Mood) -> FocusSetup { perMood[mood.rawValue] ?? .standard(for: mood) }

    public mutating func remember(_ setup: FocusSetup) {
        perMood[setup.mood.rawValue] = setup
        lastMood = setup.mood
    }

    public static func load(from defaults: UserDefaults, key: String) -> FocusPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(FocusPreferences.self, from: data) else { return FocusPreferences() }
        return prefs
    }

    public func save(to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}

public enum MusicAvailability: Equatable, Sendable { case available, notSubscribed, denied, unknown }

/// Apple Music only when it can play; otherwise a soundscape and one line why.
public func resolveSource(_ requested: SoundSource, music: MusicAvailability) -> (source: SoundSource, notice: String?) {
    guard requested == .appleMusic else { return (requested, nil) }
    switch music {
    case .available: return (.appleMusic, nil)
    case .notSubscribed: return (.soundscape, "Apple Music needs a subscription. Playing a soundscape instead.")
    case .denied: return (.soundscape, "Allow Apple Music for Almanac in Settings. Playing a soundscape instead.")
    case .unknown: return (.soundscape, "Apple Music isn't available right now. Playing a soundscape instead.")
    }
}
```


- [ ] **Step 4: Run the tests, then the whole Soundscape suite**

Run: `cd LifeOSKit && swift test --filter FocusSetupTests && swift test --filter SoundscapeTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Soundscape/FocusSetup.swift LifeOSKit/Tests/SoundscapeTests/FocusSetupTests.swift
git commit -m "feat(soundscape): timer presets per mood, remembered setups, and the Apple Music fallback"
```

---

### Task 9: Focus history in Persistence, and the Today module's catalog entry

**Files:**
- Create: `LifeOSKit/Sources/Persistence/FocusSessionRecord.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift:5` (schema list)
- Test: `LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift`
- Modify: `LifeOSKit/Sources/DesignSystem/TodayLayout.swift`
- Modify: `LifeOSKit/Tests/DesignSystemTests/TodayLayoutTests.swift`

**Interfaces:**
- Produces:
  - `@Model FocusSessionRecord` fields `id: UUID, mood: String, source: String, startedAt: Date, endedAt: Date?, focusedSeconds: Double, blocksCompleted: Int, projectTaskID: UUID?`
  - `FocusStore(context:)` with `record(mood:source:startedAt:endedAt:focusedSeconds:blocksCompleted:projectTaskID:) throws` and `focusedSeconds(on day: Date, calendar: Calendar = .current) throws -> TimeInterval`
  - `TodayModule.focus` (title "Focus"), placed in `TodayLayout.standard.left` after `.tasks`

- [ ] **Step 1: Write the failing store tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite struct FocusStoreTests {
    @MainActor @Test func focusedTimeAddsUpForTheDayOnly() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9))!
        try store.record(mood: "focus", source: "soundscape", startedAt: day, endedAt: day.addingTimeInterval(3000),
                         focusedSeconds: 3000, blocksCompleted: 2, projectTaskID: nil)
        try store.record(mood: "brainstorm", source: "appleMusic", startedAt: day.addingTimeInterval(7200),
                         endedAt: day.addingTimeInterval(9000), focusedSeconds: 1500, blocksCompleted: 1, projectTaskID: UUID())
        try store.record(mood: "focus", source: "silence", startedAt: day.addingTimeInterval(-86_400),
                         endedAt: nil, focusedSeconds: 900, blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.focusedSeconds(on: day, calendar: cal) == 4500)
    }

    @MainActor @Test func sleepIsNotFocusedTime() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "sleep", source: "soundscape", startedAt: .now, endedAt: .now, focusedSeconds: 1800,
                         blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.focusedSeconds(on: .now) == 0)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: compile failure, `cannot find 'FocusStore' in scope`.

- [ ] **Step 3: Implement**

`LifeOSKit/Sources/Persistence/FocusSessionRecord.swift`:

```swift
import Foundation
import SwiftData

/// One finished focus session. Every field has a default so stores made
/// before this model existed still open.
@Model public final class FocusSessionRecord {
    public var id: UUID = UUID()
    public var mood: String = "focus"
    public var source: String = "soundscape"
    public var startedAt: Date = Date.now
    public var endedAt: Date?
    public var focusedSeconds: Double = 0
    public var blocksCompleted: Int = 0
    public var projectTaskID: UUID?

    public init(mood: String, source: String, startedAt: Date, endedAt: Date?, focusedSeconds: Double,
                blocksCompleted: Int, projectTaskID: UUID?) {
        self.mood = mood; self.source = source; self.startedAt = startedAt; self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds; self.blocksCompleted = blocksCompleted; self.projectTaskID = projectTaskID
    }
}

public struct FocusStore {
    let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func record(mood: String, source: String, startedAt: Date, endedAt: Date?, focusedSeconds: Double,
                       blocksCompleted: Int, projectTaskID: UUID?) throws {
        context.insert(FocusSessionRecord(mood: mood, source: source, startedAt: startedAt, endedAt: endedAt,
                                          focusedSeconds: focusedSeconds, blocksCompleted: blocksCompleted,
                                          projectTaskID: projectTaskID))
        try context.save()
    }

    /// Focused time on a day: every mood but Sleep.
    public func focusedSeconds(on day: Date, calendar: Calendar = .current) throws -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt < end && $0.mood != "sleep"
        })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.focusedSeconds }
    }
}
```

In `LifeOSContainer.swift`, add `FocusSessionRecord.self,` after `ProjectTaskRecord.self` in the `Schema([...])` list.

- [ ] **Step 4: Run the store tests**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: pass.

- [ ] **Step 5: Add the Today module, test first**

Read `LifeOSKit/Tests/DesignSystemTests/TodayLayoutTests.swift` and update the tests that list `TodayLayout.standard` and the hidden tray:
- `theDefaultIsTheIPadEstate`: the expected left column becomes `[.nextUp, .month, .tasks, .focus, .scheduledWorkout]`.
- Any `hidden` expectation for the standard layout must not contain `.focus`.
- Add:

```swift
    @Test func aLayoutSavedBeforeFocusKeepsItHidden() throws {
        let old = TodayLayout(left: [.nextUp, .tasks], right: [.steps])
        let data = try JSONEncoder().encode(old)
        let back = TodayLayout.decoded(data)
        #expect(!back.left.contains(.focus) && !back.right.contains(.focus))
        #expect(back.hidden.contains(.focus))
    }
```

Copy the shape of the existing `aLayoutSavedBeforeProjectsKeepsItHidden` exactly (its constructor and `decoded` call), changing only the module. If that test builds the old layout differently, follow it.

Run: `cd LifeOSKit && swift test --filter TodayLayoutTests`
Expected: FAIL (`.focus` does not exist).

In `TodayLayout.swift`: add `focus` to the `TodayModule` cases (after `projects`), `case .focus: "Focus"` to `title`, and put `.focus` after `.tasks` in `TodayLayout.standard`'s `left`. `daySection` returns nil for it (the `default`/`nil` branch already covers it; if the switch is exhaustive, add `.focus` to the nil list).

Run: `cd LifeOSKit && swift test --filter TodayLayoutTests`
Expected: pass.

- [ ] **Step 6: Run the whole package**

Run: `cd LifeOSKit && swift test --parallel`
Expected: all pass (about 1600+ tests).

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift LifeOSKit/Sources/DesignSystem/TodayLayout.swift LifeOSKit/Tests/DesignSystemTests/TodayLayoutTests.swift
git commit -m "feat(focus): keep focus history and give Today a Focus module slot"
```

---

### Task 10: Link the kit, background audio, and the engine host

**Files:**
- Modify: `LIfeOS.xcodeproj/project.pbxproj`
- Modify: `Config/App-Info.plist`
- Create: `LIfeOS/Features/Focus/Model/SoundscapeEngine.swift`
- Create: `LIfeOS/Features/Focus/Model/FocusNowPlaying.swift`

**Interfaces:**
- Consumes: `SoundscapeRenderer`, `SoundParameters`, `Mood`.
- Produces:
  - `@MainActor final class SoundscapeEngine` with `start(mood:parameters:) throws`, `update(_:)`, `change(to:parameters:)`, `pause()`, `resume() throws`, `stop()`, `setLight(_:)`, `chime()`, and `isRunning`
  - `@MainActor final class FocusNowPlaying` with `activate(title:onPlay:onPause:onSkip:)`, `update(title:elapsed:duration:playing:)`, and `clear()`

- [ ] **Step 1: Link the `Soundscape` product to the app target**

In `project.pbxproj`, find the three entries for `Motion` (`PBXBuildFile` at line 10, the Frameworks phase entry at line 170, the target's `packageProductDependencies` entry at line 443, and the `XCSwiftPackageProductDependency` at line 1119). Add a parallel set for `Soundscape` using two fresh 24-character uppercase hex IDs (generate with `uuidgen | tr -d - | cut -c1-24`), in the same sections and the same order:

```
		<ID1> /* Soundscape in Frameworks */ = {isa = PBXBuildFile; productRef = <ID2> /* Soundscape */; };
...
				<ID1> /* Soundscape in Frameworks */,
...
				<ID2> /* Soundscape */,
...
		<ID2> /* Soundscape */ = {
			isa = XCSwiftPackageProductDependency;
			productName = Soundscape;
		};
```

Copy the `XCSwiftPackageProductDependency` block of `Motion` exactly, including its `package = ...` line if it has one.

- [ ] **Step 2: Background audio and the Apple Music prompt**

In `Config/App-Info.plist`, add `<string>audio</string>` to the `UIBackgroundModes` array (keep `remote-notification` and `bluetooth-central`), and add:

```xml
	<key>NSAppleMusicUsageDescription</key>
	<string>Almanac plays Apple Music playlists during focus sessions when you choose Apple Music as the sound.</string>
```

- [ ] **Step 3: Write `SoundscapeEngine.swift`**

```swift
import AVFoundation
import Soundscape

/// Hosts the soundscape on `AVAudioEngine`. Two renderers can play at once
/// so a change of mood crossfades over eight seconds.
@MainActor
final class SoundscapeEngine {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var slots: [(renderer: SoundscapeRenderer, node: AVAudioSourceNode)] = []
    private var fade: Task<Void, Never>?
    private var light = false
    private(set) var isRunning = false

    func start(mood: Mood, parameters: SoundParameters) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if slots.isEmpty { attach(mood: mood, parameters: parameters, volume: 1) }
        try engine.start()
        isRunning = true
    }

    func update(_ parameters: SoundParameters) { slots.last?.renderer.set(parameters) }

    func change(to mood: Mood, parameters: SoundParameters) {
        fade?.cancel()
        // A change during a crossfade drops the oldest voice at once.
        while slots.count > 1 { engine.detach(slots.removeFirst().node) }
        guard let old = slots.last else { return }
        attach(mood: mood, parameters: parameters, volume: 0)
        let new = slots[slots.count - 1]
        fade = Task { [weak self] in
            for step in 1...40 {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                let t = Float(step) / 40
                old.node.volume = 1 - t
                new.node.volume = t
            }
            guard let self, let index = self.slots.firstIndex(where: { $0.node === old.node }) else { return }
            self.engine.detach(old.node)
            self.slots.remove(at: index)
        }
    }

    func pause() { engine.pause(); isRunning = false }

    func resume() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        isRunning = true
    }

    func stop() {
        fade?.cancel(); fade = nil
        engine.stop()
        for slot in slots { engine.detach(slot.node) }
        slots = []
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setLight(_ on: Bool) {
        light = on
        for slot in slots { slot.renderer.setLight(on) }
    }

    func chime() { slots.last?.renderer.chime() }

    private func attach(mood: Mood, parameters: SoundParameters, volume: Float) {
        let renderer = SoundscapeRenderer(mood: mood, sampleRate: format.sampleRate,
                                          seed: UInt64.random(in: 1...UInt64.max), parameters: parameters)
        renderer.setLight(light)
        let node = Self.makeNode(renderer, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = volume
        slots.append((renderer, node))
    }

    /// `nonisolated` so the render block is not main-actor isolated: the
    /// audio thread calls it, and an isolated closure would trap there.
    nonisolated private static func makeNode(_ renderer: SoundscapeRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            renderer.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }
}
```

- [ ] **Step 4: Write `FocusNowPlaying.swift`**

```swift
import MediaPlayer

/// The lock screen's title and play, pause and skip-phase buttons for a
/// soundscape session. Apple Music publishes its own.
@MainActor
final class FocusNowPlaying {
    private var targets: [Any] = []

    func activate(title: String, onPlay: @escaping () -> Void, onPause: @escaping () -> Void, onSkip: @escaping () -> Void) {
        clear()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        targets = [
            center.playCommand.addTarget { _ in onPlay(); return .success },
            center.pauseCommand.addTarget { _ in onPause(); return .success },
            center.nextTrackCommand.addTarget { _ in onSkip(); return .success },
        ]
        update(title: title, elapsed: 0, duration: nil, playing: true)
    }

    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Almanac",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        let center = MPRemoteCommandCenter.shared()
        for target in targets {
            center.playCommand.removeTarget(target)
            center.pauseCommand.removeTarget(target)
            center.nextTrackCommand.removeTarget(target)
        }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
```

The remote-command handlers run on the main thread; if the compiler flags their `@Sendable` closures capturing main-actor closures, wrap each call as `MainActor.assumeIsolated { onPlay() }`.

- [ ] **Step 5: Build the app**

Run: the app build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **` (with `-quiet`, no error output).

- [ ] **Step 6: Commit**

```bash
git add LIfeOS.xcodeproj/project.pbxproj Config/App-Info.plist LIfeOS/Features/Focus
git commit -m "feat(focus): play the soundscape on AVAudioEngine in the background, with lock-screen controls"
```

---

### Task 11: Apple Music source

**Files:**
- Create: `LIfeOS/Features/Focus/Model/MusicSource.swift`

**Interfaces:**
- Consumes: `Mood.musicSearchTerm`, `Mood.musicKeywords`, `MusicAvailability`.
- Produces: `@MainActor final class MusicSource` with `availability() async -> MusicAvailability`, `play(_ mood: Mood) async throws`, `pause()`, `resume() async`, `stop()`, and `playlistName: String?`.

- [ ] **Step 1: Implement**

```swift
import MusicKit
import Soundscape

enum MusicSourceError: Error { case nothingFound }

/// Apple Music for a focus session: a personal recommendation that fits
/// the mood when there is one, else an Apple-curated catalog playlist.
@MainActor
final class MusicSource {
    private(set) var playlistName: String?
    private let player = ApplicationMusicPlayer.shared

    func availability() async -> MusicAvailability {
        let status = MusicAuthorization.currentStatus == .notDetermined
            ? await MusicAuthorization.request() : MusicAuthorization.currentStatus
        guard status == .authorized else { return .denied }
        guard let subscription = try? await MusicSubscription.current else { return .unknown }
        return subscription.canPlayCatalogContent ? .available : .notSubscribed
    }

    func play(_ mood: Mood) async throws {
        let playlist = try await pick(for: mood)
        playlistName = playlist.name
        player.queue = [playlist]
        player.state.repeatMode = .all
        try await player.play()
    }

    func pause() { player.pause() }
    func resume() async { try? await player.play() }
    func stop() { player.stop(); playlistName = nil }

    private func pick(for mood: Mood) async throws -> Playlist {
        if let personal = try? await MusicPersonalRecommendationsRequest().response() {
            for recommendation in personal.recommendations {
                if let match = recommendation.playlists.first(where: { playlist in
                    mood.musicKeywords.contains { playlist.name.localizedCaseInsensitiveContains($0) }
                }) { return match }
            }
        }
        var search = MusicCatalogSearchRequest(term: mood.musicSearchTerm, types: [Playlist.self])
        search.limit = 15
        let found = try await search.response().playlists
        if let curated = found.first(where: { $0.curatorName == "Apple Music" }) { return curated }
        guard let any = found.first else { throw MusicSourceError.nothingFound }
        return any
    }
}
```

- [ ] **Step 2: Build**

Run: the app build command.
Expected: success. (Playback needs a device, a subscription, and the MusicKit App ID service; it is a hardware check in Task 16.)

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Focus/Model/MusicSource.swift
git commit -m "feat(focus): Apple Music playlists chosen by mood"
```

---

### Task 12: Watch heart rate for focus

**Files:**
- Modify: `LIfeOS/App/Surfaces/WatchSessionBridge.swift` (properties near line 24, `installMirroringHandler` at line 35, `adopt` at line 67, the remote-data delegate near line 172)
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift:178` (the `defer` that replays `watch?.session`)
- Create: `LIfeOS/Features/Focus/Model/FocusHeartRate.swift`
- Modify: `AlmanacWatch/WatchWorkoutController.swift` (state near line 16, `start(_:asksForSetup:)` at line 117)
- Create: `AlmanacWatch/WatchFocusScreen.swift`
- Modify: `AlmanacWatch/AlmanacWatchApp.swift:23-24`

**Interfaces:**
- Consumes: `WatchWire.packet(from:)`, `WatchPacket.heartRate`, `WatchSessionBridge.startWatchApp(_:)`, `WatchSessionBridge.end(after:)`.
- Produces:
  - On `WatchSessionBridge`: `var onFocusPacket: ((Data) -> Void)?`, `static func isFocus(_ session: HKWorkoutSession) -> Bool`, and `var isFocusSession: Bool`
  - `@MainActor final class FocusHeartRate` with `var onHeartRate: ((Int) -> Void)?`, `start() async`, and `stop()`
  - On the Watch: `WatchWorkoutController.isFocus`

- [ ] **Step 1: Route focus sessions in the bridge**

Add next to the other callbacks:

```swift
    /// A focus session listens for heart rate only. A mind-and-body session
    /// is always a focus session: it never reaches `onSession`, so no
    /// recorder adopts it as a workout and nothing is saved to Health.
    var onFocusPacket: ((Data) -> Void)?
    static func isFocus(_ session: HKWorkoutSession) -> Bool { session.workoutConfiguration.activityType == .mindAndBody }
    var isFocusSession: Bool { session.map(Self.isFocus) ?? false }
```

In `installMirroringHandler`, change `if unattended { ... }` to `if unattended, !isFocus(session) { ... }` (no placeholder Live Activity for focus).

Replace `adopt(_:)` with:

```swift
    func adopt(_ session: HKWorkoutSession) {
        self.session?.delegate = nil
        dropping = false
        self.session = session
        session.delegate = self
        if Self.isFocus(session) {
            // No focus session is listening (the app was relaunched): end it
            // on the wrist rather than leave it running.
            if onFocusPacket == nil { end(after: .discard) }
            return
        }
        onSession?(session)
    }
```

In `workoutSession(_:didReceiveDataFromRemoteWorkoutSession:)`, change the loop to:

```swift
            for item in data {
                if self.isFocusSession { self.onFocusPacket?(item) } else { self.onPacket?(item) }
            }
```

- [ ] **Step 2: Never let the recorder replay a focus session**

In `ActivityRecorder.attach(_:)`, change the replay line to:

```swift
        defer { if let mirrored = watch?.session, !WatchSessionBridge.isFocus(mirrored) { adoptMirroredSession(mirrored) } }
```

- [ ] **Step 3: Write `FocusHeartRate.swift`**

```swift
import Foundation
import HealthKit
import AppSurfaces

/// Live heart rate for a focus session: the Watch runs a mind-and-body
/// session (streaming every few seconds), which is discarded at the end.
@MainActor
final class FocusHeartRate {
    var onHeartRate: ((Int) -> Void)?
    private var running = false

    func start() async {
        let bridge = WatchSessionBridge.shared
        guard WatchSessionBridge.watchAvailable, !bridge.hasSession else { return }
        bridge.onFocusPacket = { [weak self] data in
            guard let packet = WatchWire.packet(from: data), let rate = packet.heartRate, (30...220).contains(rate),
                  packet.sentAt > Date.now.addingTimeInterval(-30) else { return }
            self?.onHeartRate?(rate)
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        running = true
        try? await WatchSessionBridge.startWatchApp(configuration)
    }

    func stop() {
        guard running else { return }
        running = false
        let bridge = WatchSessionBridge.shared
        if bridge.isFocusSession { bridge.end(after: .discard) }
        bridge.onFocusPacket = nil
    }
}
```

- [ ] **Step 4: The Watch side**

In `WatchWorkoutController`, add `private(set) var isFocus = false` with the other state, and in `start(_:asksForSetup:)` right after `state = .starting` add `isFocus = configuration.activityType == .mindAndBody`.

Create `AlmanacWatch/WatchFocusScreen.swift`:

```swift
import SwiftUI

/// A focus session on the wrist: only the heart rate the phone's
/// soundscape is listening to, and a way to stop.
struct WatchFocusScreen: View {
    let workout: WatchWorkoutController

    var body: some View {
        VStack(spacing: 8) {
            Text("Focus").font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Text(workout.heartRate.map(String.init) ?? "--").font(.system(.title, design: .rounded).monospacedDigit())
            }
            Text("Heart rate shapes the sound on your iPhone.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Stop") { workout.discard() }.tint(.secondary)
        }
        .padding()
    }
}
```

In `AlmanacWatchApp.swift`, change `WatchWorkoutScreen(workout: workout)` to:

```swift
                    if workout.isFocus { WatchFocusScreen(workout: workout) } else { WatchWorkoutScreen(workout: workout) }
```

- [ ] **Step 5: Build both targets**

Run: the app build command, then the Watch build command.
Expected: both succeed.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/App/Surfaces/WatchSessionBridge.swift LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift LIfeOS/Features/Focus/Model/FocusHeartRate.swift AlmanacWatch
git commit -m "feat(focus): live heart rate from a mind-and-body Watch session that is never saved as a workout"
```

---

### Task 13: Inputs, notifications and the session model

**Files:**
- Create: `LIfeOS/Features/Focus/Model/FocusInputs.swift`
- Create: `LIfeOS/Features/Focus/Model/FocusNotifications.swift`
- Create: `LIfeOS/Features/Focus/Model/FocusLauncher.swift`
- Create: `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift`

**Interfaces:**
- Consumes: `SoundscapeEngine`, `MusicSource`, `FocusHeartRate`, `FocusNowPlaying` (Tasks 10 to 12); kit `FocusTimer`, `FocusSetup`, `FocusPreferences`, `resolveSource`, `SoundParameters`, `Conditions`, `WeatherInput`, `RecoveryLevel`, `FocusStore`, `MetricsStore`, `DayProviders`, and `ProjectsStore.moveTask(id:to:at:)`.
- Produces:
  - `struct FocusInputs` with `weather`, `recovery`, `restingHeartRate`, and `static func gather(context:providers:) async -> FocusInputs`
  - `FocusLauncher.shared` with `request: FocusLauncher.Request?` and `open(mood:taskID:taskTitle:)`
  - `FocusSessionModel(defaults:notifies:)`:
    - `soundPlaying` and `resumeSound()`
    - stored state `stage`, `setup`, `reading`, `parameters`, `heartRate`, `notice`, `activeSource`, `taskTitle`, `preferences`, and `isPresented`
    - methods `start(_:inputs:context:taskID:taskTitle:) async`, `pause()`, `resume()`, `skip()`, `end()`, `changeMood(_:)`, `markTaskDone()`, and `dismissSummary()`
  - `FocusSessionModel.Summary` with `mood`, `focusedSeconds`, `blocks`, `taskID`, and `taskTitle`

- [ ] **Step 1: `FocusInputs.swift`**

```swift
import Foundation
import SwiftData
import CoreLocation
import Persistence
import Soundscape

/// What the soundscape reads from the day, gathered once at the start.
struct FocusInputs {
    var weather: WeatherInput?
    var recovery: RecoveryLevel?
    var restingHeartRate: Double?

    static func gather(context: ModelContext, providers: DayProviders) async -> FocusInputs {
        var inputs = FocusInputs()
        let today = Calendar.current.startOfDay(for: .now)
        if let metrics = try? MetricsStore(context: context, calendar: .current).metrics(from: today, to: today).first {
            inputs.recovery = metrics.whoopRecoveryPct.map(RecoveryLevel.init(percentage:))
            inputs.restingHeartRate = metrics.restingHR
        }
        // Weather only when location is already allowed, and only if it comes
        // back within five seconds; the session never waits longer than that.
        if providers.location.access == .allowed {
            let began = Date.now
            let fetch = Task { @MainActor () -> WeatherInput? in
                guard let location = try? await providers.location.currentLocation(),
                      let forecast = try? await providers.weather.forecast(for: .now, at: location) else { return nil }
                let hour = Calendar.current.component(.hour, from: .now)
                let chance = forecast.rainChanceByHour.indices.contains(hour) ? forecast.rainChanceByHour[hour] : nil
                return WeatherInput(symbol: forecast.conditionSymbol, windKph: forecast.windKph, rainChanceNow: chance)
            }
            let timeout = Task { try? await Task.sleep(for: .seconds(5)); fetch.cancel() }
            let weather = await fetch.value
            timeout.cancel()
            if Date.now.timeIntervalSince(began) <= 5.5 { inputs.weather = weather }
        }
        return inputs
    }
}
```

Check `LocationAccess`'s case names in `LIfeOS/Features/Day/Model/WeatherProviding.swift` and use the "authorized" case it defines in place of `.allowed`. Check `MetricsStore`'s init label order at `LifeOSKit/Sources/Persistence/MetricsStore.swift` and match `DayViewModel.swift:84-90`.

- [ ] **Step 2: `FocusNotifications.swift`**

```swift
import UserNotifications
import Soundscape

/// The bell at each block's end, scheduled ahead so it rings with the
/// phone locked. A sleep fade ends quietly, with no notification.
@MainActor
struct FocusNotifications {
    private static let prefix = "focus."

    func schedule(_ ends: [PhaseEnd], plan: TimerPlan) async {
        await cancel()
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        var restMinutes = 5, longRestMinutes = 15
        if case .pomodoro(_, let rest, let longRest, _, _) = plan {
            restMinutes = Int(rest / 60); longRestMinutes = Int(longRest / 60)
        }
        for (index, end) in ends.enumerated() where end.ending != .fading {
            let content = UNMutableNotificationContent()
            switch end.next {
            case .rest: content.title = "Break time"; content.body = "\(restMinutes) minutes. Stand up, look away."
            case .longRest(let block): content.title = "Long break"; content.body = "\(block) blocks done. Take \(longRestMinutes) minutes."
            case .work(let block): content.title = "Back to focus"; content.body = "Block \(block) is starting."
            case .finished: content.title = "Session complete"; content.body = "Nice work."
            case .open, .fading: continue
            }
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.at.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(Self.prefix)\(index)", content: content, trigger: trigger))
        }
    }

    func cancel() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
```

- [ ] **Step 3: `FocusLauncher.swift`**

```swift
import Foundation
import Soundscape

/// Any screen (Today, a project task, Siri) asks for the setup sheet here;
/// the root view presents it.
@MainActor @Observable
final class FocusLauncher {
    static let shared = FocusLauncher()

    struct Request: Identifiable, Equatable {
        let id = UUID()
        var mood: Mood?
        var taskID: UUID?
        var taskTitle: String?
    }

    var request: Request?

    func open(mood: Mood? = nil, taskID: UUID? = nil, taskTitle: String? = nil) {
        request = Request(mood: mood, taskID: taskID, taskTitle: taskTitle)
    }
}
```

- [ ] **Step 4: `FocusSessionModel.swift`**

```swift
import Foundation
import SwiftData
import AVFoundation
import UIKit
import Persistence
import Soundscape

/// One focus session: the clock, the sound, and what the sound listens to.
@MainActor @Observable
final class FocusSessionModel {
    struct Summary: Equatable {
        var mood: Mood
        var focusedSeconds: TimeInterval
        var blocks: Int
        var taskID: UUID?
        var taskTitle: String?
    }

    enum Stage: Equatable { case idle, running, summary(Summary) }

    private(set) var stage: Stage = .idle
    private(set) var setup = FocusSetup.standard(for: .focus)
    private(set) var reading: TimerReading?
    private(set) var parameters: SoundParameters?
    private(set) var heartRate: Int?
    private(set) var notice: String?
    private(set) var activeSource: SoundSource = .soundscape
    private(set) var taskTitle: String?
    private(set) var preferences: FocusPreferences
    var isPresented: Bool { stage != .idle }

    static let preferencesKey = "focus.preferences"

    private let engine = SoundscapeEngine()
    private let music = MusicSource()
    private let watch = FocusHeartRate()
    private let nowPlaying = FocusNowPlaying()
    private let notifications = FocusNotifications()
    private let defaults: UserDefaults
    private var timer: FocusTimer?
    private var inputs = FocusInputs()
    private var context: ModelContext?
    private var taskID: UUID?
    private var startedAt = Date.now
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastPhase: TimerPhase?
    private var lastPush = Date.distantPast
    /// Off in the design preview, so no permission prompt covers UI tests.
    private let notifies: Bool

    /// Whether sound is coming out: a soundscape paused by a route change is not.
    var soundPlaying: Bool { activeSource != .soundscape || engine.isRunning }

    init(defaults: UserDefaults = .standard, notifies: Bool = true) {
        self.defaults = defaults
        self.notifies = notifies
        self.preferences = FocusPreferences.load(from: defaults, key: Self.preferencesKey)
    }

    func resumeSound() { try? engine.resume() }

    func start(_ setup: FocusSetup, inputs: FocusInputs, context: ModelContext, taskID: UUID? = nil, taskTitle: String? = nil) async {
        guard stage != .running else { return }
        self.setup = setup
        self.inputs = inputs
        self.context = context
        self.taskID = taskID
        self.taskTitle = taskTitle
        preferences.remember(setup)
        preferences.save(to: defaults, key: Self.preferencesKey)
        startedAt = .now
        timer = FocusTimer(plan: setup.plan, startedAt: startedAt)
        reading = timer?.reading(at: .now)
        lastPhase = reading?.phase
        notice = nil
        heartRate = nil
        stage = .running

        let availability: MusicAvailability = setup.source == .appleMusic ? await music.availability() : .unknown
        let resolved = resolveSource(setup.source, music: availability)
        activeSource = resolved.source
        notice = resolved.notice
        await startSound()

        watch.onHeartRate = { [weak self] rate in self?.heartRate = rate; self?.push(force: false) }
        await watch.start()
        observe()
        await reschedule()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startSound() async {
        switch activeSource {
        case .soundscape:
            let p = makeParameters()
            parameters = p
            do { try engine.start(mood: setup.mood, parameters: p) } catch { notice = "The soundscape couldn't start. Timer only." }
            nowPlaying.activate(title: "\(setup.mood.title) · Soundscape",
                                onPlay: { [weak self] in self?.resume() },
                                onPause: { [weak self] in self?.pause() },
                                onSkip: { [weak self] in self?.skip() })
        case .appleMusic:
            do { try await music.play(setup.mood) } catch {
                activeSource = .soundscape
                notice = "No Apple Music playlist fits right now. Playing a soundscape instead."
                await startSound()
            }
        case .silence:
            break
        }
    }

    private func makeParameters() -> SoundParameters {
        let phase = reading.map(SoundPhase.init) ?? .work
        let conditions = Conditions(date: .now, heartRate: heartRate.map(Double.init),
                                    restingHeartRate: inputs.restingHeartRate, phase: phase,
                                    weather: inputs.weather, recovery: inputs.recovery, texture: setup.texture)
        return .make(.for(setup.mood), conditions)
    }

    /// New parameters at most every five seconds, or at once on a phase change.
    private func push(force: Bool) {
        guard activeSource == .soundscape, stage == .running else { return }
        guard force || Date.now.timeIntervalSince(lastPush) >= 5 else { return }
        lastPush = .now
        let p = makeParameters()
        parameters = p
        engine.update(p)
    }

    private func tick() {
        guard stage == .running, let timer else { return }
        let now = Date.now
        let reading = timer.reading(at: now)
        self.reading = reading
        if reading.phase != lastPhase {
            phaseChanged(from: lastPhase, to: reading.phase)
            lastPhase = reading.phase
            push(force: true)
        } else {
            push(force: false)
        }
        if activeSource == .soundscape {
            nowPlaying.update(title: "\(setup.mood.title) · \(phaseTitle(reading.phase))",
                              elapsed: (reading.phaseLength ?? 0) - (reading.remaining ?? 0),
                              duration: reading.phaseLength, playing: !reading.isPaused)
        }
        if reading.phase == .finished { end() }
    }

    private func phaseChanged(from old: TimerPhase?, to new: TimerPhase) {
        if UIApplication.shared.applicationState == .active, new != .finished {
            if activeSource == .soundscape { engine.chime() }
            else { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        guard activeSource == .appleMusic else { return }
        switch new {
        case .rest, .longRest: music.pause()
        case .work: Task { await music.resume() }
        default: break
        }
    }

    func phaseTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .work(let block):
            if case .pomodoro(_, _, _, _, let blocks) = setup.plan, let blocks { return "Focus \(block) of \(blocks)" }
            return "Focus \(block)"
        case .rest: return "Break"
        case .longRest: return "Long break"
        case .open: return setup.mood == .sleep ? "Sleep" : setup.mood.title
        case .fading: return "Fading out"
        case .finished: return "Done"
        }
    }

    func pause() {
        guard stage == .running, var timer, !timer.reading(at: .now).isPaused else { return }
        timer.pause(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        switch activeSource {
        case .soundscape: engine.pause()
        case .appleMusic: music.pause()
        case .silence: break
        }
        Task { await notifications.cancel() }
    }

    func resume() {
        guard stage == .running, var timer, timer.reading(at: .now).isPaused else { return }
        timer.resume(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        switch activeSource {
        case .soundscape: try? engine.resume()
        case .appleMusic:
            if case .work = reading?.phase { Task { await music.resume() } }
        case .silence: break
        }
        Task { await reschedule() }
    }

    func skip() {
        guard stage == .running, var timer else { return }
        timer.skip(at: .now); self.timer = timer
        tick()
        Task { await reschedule() }
    }

    /// A new mood crossfades; the clock is untouched.
    func changeMood(_ mood: Mood) {
        guard stage == .running, mood != setup.mood else { return }
        var next = preferences.setup(for: mood)
        next.source = setup.source
        setup.mood = mood
        setup.texture = next.texture
        switch activeSource {
        case .soundscape:
            let p = makeParameters()
            parameters = p
            engine.change(to: mood, parameters: p)
        case .appleMusic:
            Task { try? await music.play(mood) }
        case .silence: break
        }
    }

    func end() {
        guard stage == .running, let timer else { return }
        let reading = timer.reading(at: .now)
        ticker?.cancel(); ticker = nil
        engine.stop(); music.stop(); watch.stop(); nowPlaying.clear()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        Task { await notifications.cancel() }
        if let context {
            try? FocusStore(context: context).record(mood: setup.mood.rawValue, source: activeSource.rawValue,
                                                     startedAt: startedAt, endedAt: .now,
                                                     focusedSeconds: reading.focusedSeconds,
                                                     blocksCompleted: reading.completedBlocks, projectTaskID: taskID)
        }
        self.timer = nil
        stage = .summary(Summary(mood: setup.mood, focusedSeconds: reading.focusedSeconds,
                                 blocks: reading.completedBlocks, taskID: taskID, taskTitle: taskTitle))
    }

    func markTaskDone() {
        guard case .summary(let summary) = stage, let id = summary.taskID, let context else { return }
        try? ProjectsStore(context: context).moveTask(id: id, to: .done, at: 0)
    }

    func dismissSummary() { stage = .idle; taskID = nil; taskTitle = nil }

    private func reschedule() async {
        guard notifies, let timer else { return }
        await notifications.schedule(timer.upcomingEnds(after: .now, limit: 12), plan: timer.plan)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let self, self.activeSource == .soundscape else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue { self.engine.pause() }
                else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                        self.reading?.isPaused == false { try? self.engine.resume() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      self.activeSource == .soundscape else { return }
                self.engine.pause()
            }
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let state = ProcessInfo.processInfo.thermalState
                self?.engine.setLight(state == .serious || state == .critical)
            }
        })
    }
}
```

A route change pauses only the sound; the timer keeps running, and the session screen's play control (shown while `soundPlaying` is false) calls `resumeSound()`.

- [ ] **Step 5: Build**

Run: the app build command.
Expected: success. Fix any isolation complaints by following the existing `ActivityRecorder` patterns. Do not add `nonisolated(unsafe)`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Focus
git commit -m "feat(focus): the session model that runs the clock, the sound, heart rate and notifications"
```

---

### Task 14: The screens

**Files:**
- Create: `LIfeOS/Features/Focus/View/FocusSetupSheet.swift`
- Create: `LIfeOS/Features/Focus/View/FocusVisual.swift`
- Create: `LIfeOS/Features/Focus/View/FocusSessionScreen.swift`
- Create: `LIfeOS/Features/Focus/View/FocusSummaryView.swift`
- Create: `LIfeOS/Features/Focus/View/FocusDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:139` (dispatch)

**Interfaces:**
- Consumes: `FocusSessionModel`, `FocusSetup`, `Mood.presets`, `SoundSource`, `Texture`, `SoundParameters`, `TimerReading`.
- Produces:
  - `FocusSetupSheet(initial: FocusSetup, taskTitle: String?, onStart: (FocusSetup) -> Void)`
  - `FocusSessionScreen(model: FocusSessionModel)`
  - `FocusVisual(parameters: SoundParameters?, reading: TimerReading?)`
  - `FocusDesignPreview(page: String)`
  - Accessibility identifiers used by the UI test: `focus.mood.<raw>`, `focus.source.<raw>`, `focus.preset.<id>`, `focus.start`, `focus.timer`, `focus.phase`, `focus.pause`, `focus.skip`, `focus.end`, `focus.changeMood`, `focus.summary`, `focus.summary.done`

Before writing, read `LIfeOS/Features/Day/View/DayScreen.swift` and `LIfeOS/Features/Projects/View/TaskSheet.swift` for the exact editorial helpers (`LifeOSType`, `Editorial.quietInk`, `EditorialSectionHeader`, `.buttonStyle(.editorial(.primary, size: .regular, fullWidth: true))`, `LifeOSTokens.canvas.resolve(scheme)`) and use them as they are used there.

- [ ] **Step 1: `FocusSetupSheet.swift`**

```swift
import SwiftUI
import DesignSystem
import Soundscape

/// Mood, sound, timer and texture. Everything starts at what was used last.
struct FocusSetupSheet: View {
    @State var setup: FocusSetup
    var preferences: FocusPreferences
    var taskTitle: String?
    var onStart: (FocusSetup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(initial: FocusSetup, preferences: FocusPreferences, taskTitle: String?, onStart: @escaping (FocusSetup) -> Void) {
        _setup = State(initialValue: initial)
        self.preferences = preferences
        self.taskTitle = taskTitle
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if let taskTitle {
                        Text(taskTitle).font(LifeOSType.rowTitle).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    moods
                    choice("Sound", SoundSource.allCases, \.rawValue, \.title, selection: $setup.source, id: "source")
                    choice("Timer", setup.mood.presets, \.id, \.title, selection: $setup.presetID, id: "preset")
                    if setup.mood == .focus || setup.mood == .brainstorm {
                        Toggle("Stop after 4 blocks", isOn: Binding(get: { setup.blocks != nil }, set: { setup.blocks = $0 ? 4 : nil }))
                            .font(LifeOSType.body)
                    }
                    if setup.source == .soundscape {
                        choice("Texture", Texture.allCases, \.rawValue, \.title, selection: $setup.texture, id: "texture")
                    }
                }
                .padding(Space.x2)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Start") { onStart(setup); dismiss() }
                    .buttonStyle(.editorial(.primary, size: .regular, fullWidth: true))
                    .accessibilityIdentifier("focus.start")
                    .padding(Space.x2)
            }
            .navigationTitle("Focus session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var moods: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.x1) {
            ForEach(Mood.allCases, id: \.self) { mood in
                Button {
                    let remembered = preferences.setup(for: mood)
                    setup = FocusSetup(mood: mood, source: setup.source, presetID: remembered.presetID,
                                       blocks: remembered.blocks, texture: remembered.texture)
                } label: {
                    Text(mood.title).font(LifeOSType.rowTitle)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(setup.mood == mood ? LifeOSTokens.accent.resolve(scheme).opacity(0.18) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: Space.small).stroke(Editorial.rule(scheme)))
                        .clipShape(RoundedRectangle(cornerRadius: Space.small))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus.mood.\(mood.rawValue)")
                .accessibilityAddTraits(setup.mood == mood ? .isSelected : [])
            }
        }
    }

    private func choice<Item, Value: Hashable>(_ title: String, _ items: [Item], _ value: KeyPath<Item, Value>,
                                               _ label: KeyPath<Item, String>, selection: Binding<Value>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title.uppercased()).editorialEyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x1) {
                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
                        Button(item[keyPath: label]) { selection.wrappedValue = item[keyPath: value] }
                            .buttonStyle(.editorial(selection.wrappedValue == item[keyPath: value] ? .primary : .secondary, size: .compact, fullWidth: false))
                            .accessibilityIdentifier("focus.\(id).\(item[keyPath: value])")
                    }
                }
            }
        }
    }
}
```

`Space.small` is a radius constant named in the design system; if it lives on a separate `Radius` type, use that.

- [ ] **Step 2: `FocusVisual.swift`**

```swift
import SwiftUI
import Soundscape

/// Soft rings that breathe at the music's pace and brighten with it.
/// Still when Reduce Motion is on.
struct FocusVisual: View {
    var parameters: SoundParameters?
    var reading: TimerReading?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || reading?.isPaused == true)) { context in
            Canvas { gc, size in
                let period = parameters?.barSeconds ?? 8
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(2 * .pi * t / period)
                let brightness = parameters?.brightness ?? 0.4
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height) / 2
                let ink: Color = scheme == .dark ? .white : .black
                for ring in 0..<5 {
                    let r = base * (0.3 + 0.14 * Double(ring)) * (0.92 + 0.08 * breath)
                    let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
                    let alpha = (0.05 + 0.12 * brightness) * (1 - Double(ring) * 0.15)
                    gc.fill(Path(ellipseIn: rect), with: .color(ink.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: `FocusSummaryView.swift`**

```swift
import SwiftUI
import DesignSystem
import Soundscape

struct FocusSummaryView: View {
    let summary: FocusSessionModel.Summary
    var onMarkDone: () -> Void
    var onDone: () -> Void
    @State private var marked = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("SESSION").editorialEyebrow()
            Text(minutes).font(LifeOSType.display)
            if summary.blocks > 0 { Text("\(summary.blocks) \(summary.blocks == 1 ? "block" : "blocks") completed").font(LifeOSType.body) }
            if let title = summary.taskTitle, summary.taskID != nil {
                Button(marked ? "Marked done" : "Mark \u{201C}\(title)\u{201D} done") { onMarkDone(); marked = true }
                    .buttonStyle(.editorial(.secondary, size: .regular, fullWidth: true))
                    .disabled(marked)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.editorial(.primary, size: .regular, fullWidth: true))
                .accessibilityIdentifier("focus.summary.done")
        }
        .padding(Space.x3)
        .accessibilityIdentifier("focus.summary")
    }

    private var minutes: String {
        let m = Int(summary.focusedSeconds / 60)
        let label = summary.mood == .sleep ? "listened" : "focused"
        return m >= 60 ? "\(m / 60)h \(m % 60)m \(label)" : "\(m) min \(label)"
    }
}
```

- [ ] **Step 4: `FocusSessionScreen.swift`**

```swift
import SwiftUI
import DesignSystem
import Soundscape

/// The full-screen session: the clock, the phase, the visual, and the few
/// controls a person needs without leaving their work.
struct FocusSessionScreen: View {
    @Bindable var model: FocusSessionModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            switch model.stage {
            case .summary(let summary):
                FocusSummaryView(summary: summary, onMarkDone: model.markTaskDone, onDone: model.dismissSummary)
            default:
                running
            }
        }
    }

    private var isSleep: Bool { model.setup.mood == .sleep }

    private var background: Color {
        isSleep ? .black : LifeOSTokens.canvas.resolve(scheme)
    }

    private var running: some View {
        VStack(spacing: Space.x3) {
            HStack {
                Text(model.setup.mood.title.uppercased()).editorialEyebrow()
                Spacer()
                if let rate = model.heartRate { Label("\(rate)", systemImage: "heart.fill").font(LifeOSType.label) }
            }
            if let title = model.taskTitle { Text(title).font(LifeOSType.rowTitle).frame(maxWidth: .infinity, alignment: .leading) }
            Spacer(minLength: 0)
            ZStack {
                if !isSleep { FocusVisual(parameters: model.parameters, reading: model.reading).frame(height: 300) }
                VStack(spacing: Space.x1) {
                    Text(clock).font(LifeOSType.numeral(isSleep ? 40 : 72, weight: .light)).monospacedDigit()
                        .accessibilityIdentifier("focus.timer")
                    Text(model.reading.map { model.phaseTitle($0.phase) } ?? "")
                        .font(LifeOSType.label).accessibilityIdentifier("focus.phase")
                }
            }
            .opacity(isSleep ? 0.5 : 1)
            Spacer(minLength: 0)
            if let notice = model.notice { Text(notice).font(LifeOSType.caption).multilineTextAlignment(.center) }
            footnote
            controls
        }
        .padding(Space.x3)
        .foregroundStyle(isSleep ? Color.white.opacity(0.6) : LifeOSTokens.primaryText.resolve(scheme))
    }

    private var footnote: some View {
        HStack(spacing: Space.x2) {
            Text(model.activeSource.title)
            if model.activeSource == .soundscape, let texture = model.parameters?.texture, texture != .none {
                Text(String(describing: texture).capitalized)
            }
        }
        .font(LifeOSType.caption)
        .foregroundStyle(Editorial.quietInk(scheme))
    }

    private var controls: some View {
        HStack(spacing: Space.x2) {
            Menu {
                ForEach(Mood.allCases, id: \.self) { mood in Button(mood.title) { model.changeMood(mood) } }
            } label: { Image(systemName: "waveform").frame(width: 44, height: 44) }
                .accessibilityLabel("Change mood").accessibilityIdentifier("focus.changeMood")
            Button {
                if model.reading?.isPaused == true { model.resume() }
                else if !model.soundPlaying { model.resumeSound() }
                else { model.pause() }
            } label: {
                Image(systemName: model.reading?.isPaused == true || !model.soundPlaying ? "play.fill" : "pause.fill")
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(model.reading?.isPaused == true ? "Resume" : "Pause").accessibilityIdentifier("focus.pause")
            Button { model.skip() } label: { Image(systemName: "forward.end").frame(width: 44, height: 44) }
                .accessibilityLabel("Skip phase").accessibilityIdentifier("focus.skip")
            Button("End") { model.end() }
                .buttonStyle(.editorial(.quiet, size: .compact, fullWidth: false))
                .accessibilityIdentifier("focus.end")
        }
        .font(.title2)
    }

    private var clock: String {
        guard let reading = model.reading else { return "--:--" }
        let seconds = Int((reading.remaining ?? reading.focusedSeconds).rounded(.up))
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
```

`LifeOSType.numeral(_:weight:)` exists per the design system; match its parameter types.

- [ ] **Step 5: `FocusDesignPreview.swift` and the dispatch**

```swift
#if DEBUG
import SwiftUI
import Persistence
import Soundscape

/// `--page=focus`: a button that opens the real setup sheet, then the real
/// session screen on an in-memory store.
struct FocusDesignPreview: View {
    let page: String
    @State private var model = FocusSessionModel(defaults: UserDefaults(suiteName: "focus-preview")!, notifies: false)
    @State private var showSetup = false
    private let container = try! LifeOSContainer.make(inMemory: true)

    var body: some View {
        Button("Open focus") { showSetup = true }
            .accessibilityIdentifier("focus.open")
            .sheet(isPresented: $showSetup) {
                FocusSetupSheet(initial: model.preferences.setup(for: model.preferences.lastMood), preferences: model.preferences,
                                taskTitle: page == "focus-task" ? "Write the launch post" : nil) { setup in
                    Task { await model.start(setup, inputs: FocusInputs(), context: container.mainContext,
                                             taskID: page == "focus-task" ? UUID() : nil,
                                             taskTitle: page == "focus-task" ? "Write the launch post" : nil) }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { model.isPresented }, set: { _ in })) {
                FocusSessionScreen(model: model)
            }
    }
}
#endif
```

In `HealthActivityDesignPreview.swift`, next to the `projects` branch (line 139), add:

```swift
        else if page == "focus" || page.hasPrefix("focus-") { FocusDesignPreview(page: page) }
```

- [ ] **Step 6: Build and look at it**

Run: the app build command. Then launch on the simulator with the preview page:

```bash
xcrun simctl boot D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB 2>/dev/null; open -a Simulator
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*focus-soundscape*" -prune -o -name "LIfeOS.app" -path "*Debug-iphonesimulator*" -print | head -1)
xcrun simctl install D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB "$APP"
xcrun simctl launch D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB com.shivvyas.lifeos --design-preview --page=focus
```

Find the worktree's `LIfeOS.app` by the DerivedData folder whose `info.plist` mentions `focus-soundscape` (see memory: worktree build gotchas) if the `find` picks another one. Screenshot with `xcrun simctl io D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB screenshot <scratchpad>/focus.png` and look at it; check both light and dark (`xcrun simctl ui ... appearance dark`).

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/Features/Focus/View LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(focus): the setup sheet, the full-screen session with its breathing visual, and the summary"
```

---

### Task 15: Entry points: Today, project tasks, Siri, and the root view

**Files:**
- Modify: `LIfeOS/Features/Today/View/TodayModules.swift` (switch at line 24; new `focusModule`)
- Modify: `LIfeOS/Features/Projects/View/TaskSheet.swift` (new section before "Delete task", around line 74)
- Create: `LIfeOS/Features/Focus/Intents/StartFocusSessionIntent.swift`
- Modify: `LIfeOS/App/RootView.swift` (state near lines 53-98; modifiers near 254-266)

**Interfaces:**
- Consumes: `FocusLauncher.shared`, `FocusSessionModel`, `FocusSetupSheet`, `FocusSessionScreen`, `FocusInputs.gather`, `FocusStore.focusedSeconds(on:)`, and `@Environment(\.dayProviders)`.
- Produces: the user-visible entry points.

- [ ] **Step 1: The Today module**

In `moduleView`, add `case .focus: focusModule`. Add to the extension:

```swift
    /// Four moods and how long you've focused today; a tap opens the setup.
    @ViewBuilder
    private var focusModule: some View {
        let focused = (try? FocusStore(context: context).focusedSeconds(on: .now)) ?? 0
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Focus") {
                if focused >= 60 { Text("\(Int(focused / 60)) min today").font(LifeOSType.caption) }
            }
            HStack(spacing: Space.x1) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    Button(mood.title) { if !self.store.isArranging { FocusLauncher.shared.open(mood: mood) } }
                        .buttonStyle(.editorial(.secondary, size: .compact, fullWidth: true))
                }
            }
            Button("Resume last") { if !self.store.isArranging { FocusLauncher.shared.open() } }
                .buttonStyle(.editorial(.quiet, size: .compact, fullWidth: false))
        }
    }
```

Add `import Soundscape` at the top. Match `EditorialSectionHeader`'s trailing-content initializer to its definition in `Editorial.swift:108`.

- [ ] **Step 2: "Focus on this" in the task sheet**

Before the `if existing != nil { Section { Button("Delete task" ...` block, add:

```swift
                if let existing {
                    Section {
                        Button("Focus on this") {
                            dismiss()
                            FocusLauncher.shared.open(mood: .focus, taskID: existing.id, taskTitle: existing.title)
                        }
                    }
                }
```

- [ ] **Step 3: The App Intent**

```swift
import AppIntents
import Soundscape

enum FocusMoodOption: String, AppEnum {
    case focus, brainstorm, relax, sleep
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [FocusMoodOption: DisplayRepresentation] = [
        .focus: "Focus", .brainstorm: "Brainstorm", .relax: "Relax", .sleep: "Sleep",
    ]
}

struct StartFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a focus session"
    static let description = IntentDescription("Opens Almanac's focus session setup, ready to start.")
    static let openAppWhenRun = true

    @Parameter(title: "Mood") var mood: FocusMoodOption?

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusLauncher.shared.open(mood: mood.flatMap { Mood(rawValue: $0.rawValue) })
        return .result()
    }
}

struct AlmanacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusSessionIntent(),
                    phrases: ["Start a focus session in \(.applicationName)", "Focus with \(.applicationName)"],
                    shortTitle: "Focus", systemImageName: "timer")
    }
}
```

The app target defaults to main-actor isolation. If the compiler says a main actor-isolated member cannot satisfy a nonisolated `AppEnum` or `AppIntent` requirement, mark the two types `nonisolated` (`nonisolated enum FocusMoodOption`, `nonisolated struct StartFocusSessionIntent`) and keep `perform()` `@MainActor`.

- [ ] **Step 4: Present from the root view**

In `RootView`, add with the other `@State` view models:

```swift
    @State private var focus = FocusSessionModel()
    @State private var focusLauncher = FocusLauncher.shared
```

If `RootView` has no `@Environment(\.modelContext) private var modelContext`, add one. Add next to the `.environment(\.dayProviders, ...)` modifiers (read `@Environment(\.modelContext)` and the day providers the way the surrounding code does; RootView builds `DayProviders` itself at line 266, so reuse that value):

```swift
        .sheet(item: $focusLauncher.request) { request in
            let mood = request.mood ?? focus.preferences.lastMood
            FocusSetupSheet(initial: focus.preferences.setup(for: mood), preferences: focus.preferences,
                            taskTitle: request.taskTitle) { setup in
                Task {
                    let inputs = await FocusInputs.gather(context: modelContext, providers: dayProviders)
                    await focus.start(setup, inputs: inputs, context: modelContext,
                                      taskID: request.taskID, taskTitle: request.taskTitle)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { focus.isPresented }, set: { _ in })) {
            FocusSessionScreen(model: focus)
        }
```

Where `dayProviders` is the `DayProviders` value RootView already constructs for `.environment(\.dayProviders, ...)`; hoist it into a `private var` or `let` if it is built inline.

- [ ] **Step 5: Build, then run the package tests again**

Run: the app build command, then `cd LifeOSKit && swift test --parallel`.
Expected: both succeed.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Today/View/TodayModules.swift LIfeOS/Features/Projects/View/TaskSheet.swift LIfeOS/Features/Focus/Intents LIfeOS/App/RootView.swift
git commit -m "feat(focus): start a session from Today, a project task, or Siri"
```

---

### Task 16: UI test, listening, and the hardware checklist

**Files:**
- Create: `LIfeOSUITests/FocusUITests.swift`

- [ ] **Step 1: Write the UI test**

```swift
import XCTest

final class FocusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testStartChangeMoodAndEndASession() {
        let app = launch("focus")
        XCTAssertTrue(app.buttons["focus.open"].waitForExistence(timeout: 8))
        app.buttons["focus.open"].tap()

        XCTAssertTrue(app.buttons["focus.mood.brainstorm"].waitForExistence(timeout: 5))
        app.buttons["focus.mood.brainstorm"].tap()
        app.buttons["focus.preset.50-10"].tap()
        app.buttons["focus.start"].tap()

        let phase = app.staticTexts["focus.phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 8))
        XCTAssertEqual(phase.label, "Focus 1 of 4")
        let timer = app.staticTexts["focus.timer"]
        XCTAssertTrue(timer.label.hasPrefix("50:") || timer.label.hasPrefix("49:"))

        app.buttons["focus.changeMood"].tap()
        app.buttons["Relax"].tap()
        XCTAssertTrue(app.staticTexts["RELAX"].waitForExistence(timeout: 3))
        XCTAssertEqual(phase.label, "Focus 1 of 4", "changing mood must not touch the clock")

        app.buttons["focus.skip"].tap()
        XCTAssertTrue(phase.label == "Break" || phase.waitForLabel("Break"))

        app.buttons["focus.end"].tap()
        XCTAssertTrue(app.buttons["focus.summary.done"].waitForExistence(timeout: 5))
        app.buttons["focus.summary.done"].tap()
        XCTAssertTrue(app.buttons["focus.open"].waitForExistence(timeout: 5))
    }

    func testAProjectTaskSessionOffersToMarkItDone() {
        let app = launch("focus-task")
        app.buttons["focus.open"].tap()
        XCTAssertTrue(app.staticTexts["Write the launch post"].waitForExistence(timeout: 5))
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.buttons["focus.end"].waitForExistence(timeout: 8))
        app.buttons["focus.end"].tap()
        XCTAssertTrue(app.buttons["Mark \u{201C}Write the launch post\u{201D} done"].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func waitForLabel(_ label: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
```

After changing mood the eyebrow reads "RELAX" because `setup.mood` changes; the phase stays "Focus 1 of 4" because the plan is untouched.

- [ ] **Step 2: Run it**

Run: `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'id=D6CEC8FF-AAEB-4B02-BEA6-09D15B4C12EB' -only-testing:LIfeOSUITests/FocusUITests -quiet`
Expected: `** TEST SUCCEEDED **`. If the LIfeOS scheme does not include the UI test bundle, use `-scheme LIfeOSUITests`.

- [ ] **Step 3: Run the existing Today and Projects UI tests (regression)**

Run: the same command with `-only-testing:LIfeOSUITests/TodayLayoutUITests -only-testing:LIfeOSUITests/ProjectsUITests` (check the class names in `LIfeOSUITests/`).
Expected: pass.

- [ ] **Step 4: Render the listening set**

Run: `scripts/render-soundscapes.sh /private/tmp/claude-501/-Users-shivvyas-LIfeOS/b2439d0c-8c01-496a-98e7-5a704564dfbf/scratchpad/soundscapes`
Expected: 16 WAVs. Hand them to the owner for listening; tuning changes go into the recipes (Task 1) or voices (Task 4), re-running their tests.

- [ ] **Step 5: Write the hardware checklist into the PR description**

These checks need a real iPhone, a Watch, an Apple Music subscription, and the MusicKit App ID service:
- Lock the phone during a Soundscape session for 10 minutes: the sound keeps playing, and the block-end notification rings.
- Use the lock-screen play, pause and skip controls.
- With the Watch paired, start a session: the Watch shows Focus with a heart rate, the phone's readout updates, and ending the session stops the Watch without saving anything to Health (check the Fitness app).
- Open the Activity screen during a focus session: no workout appears.
- Apple Music: a playlist plays, pauses in the break, and resumes at the next block. Without a subscription, the notice appears and a soundscape plays.
- Unplug headphones: the sound pauses, the timer runs on, and Play brings the sound back.

- [ ] **Step 6: Final full verification**

Run, and paste the results into the PR:
- `cd LifeOSKit && swift test --parallel`
- the app build
- the Watch build
- the Focus UI tests

- [ ] **Step 7: Commit**

```bash
git add LIfeOSUITests/FocusUITests.swift
git commit -m "test(focus): start, change mood, skip and end a session, and a project task's session"
```
