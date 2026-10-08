# Focus sessions: Pomodoro, a generative soundscape engine, and Apple Music

Decided 2026-10-08 with the owner, who asked to "complete making focus
sessions now, the pomodoro as well as the focus music like Endel ... with
four moods focus, sleep, relax and brainstorming ... get inspirations for
tracks from Endel, let's create an engine".

This replaces the music half of the 2026-10-07 plan (focus blocks with
Apple Music only). Apple Music stays, as a second sound source.

Decisions, in the order they were made:

- **Both sources in this build**: our own generative **Soundscape** and
  **Apple Music** (MusicKit), chosen per session, plus Silence.
- **Four moods**: Focus, Brainstorm, Relax, Sleep.
- **The soundscape adapts to four inputs**: time of day, live heart rate
  from the Watch, the timer's phase, and weather plus the day's recovery.
- **Each mood has its own kind of timer**: Pomodoro for Focus and
  Brainstorm, a countdown or open-ended for Relax, a fade-out for Sleep.
- **Pure real-time synthesis**: every sound is generated on the device by
  our own code on `AVAudioEngine`. No recorded audio, no assets, no
  licences, and it never loops.

Cost: $0 per person per month. Everything runs on the device; no server,
no model calls. Apple Music is the listener's own subscription.

## 1. The four moods

Each mood is a recipe: a scale, a tempo range, a set of layers, and rules
for how it changes. Like Endel's modes, the moods carry little melody and
evolve slowly, so they hold attention without asking for it.

| Mood | Character | Harmony | Pulse | Layers |
|---|---|---|---|---|
| **Focus** | Steady and neutral: a room hum with a heartbeat | Major pentatonic; one chord every 16 to 32 s; no dramatic cadences | 60 to 72 BPM soft sub or marimba pulse, strictly regular | Warm pad, sparse bell motif (one note every 2 to 4 bars), brown-noise bed, optional rain |
| **Brainstorm** | Brighter and more alive; invites wandering | Lydian and major 9th colours; chord change every 8 bars | 76 to 92 BPM syncopated plucks | Shimmer pad, plucks on a random walk over the scale, airy high texture, an occasional "spark" bell |
| **Relax** | Open, slow breathing | Sus2 and sus4 chords over a drone | No beat; swells on a 4 s in, 6 s out breathing cycle | Drone, slow pad swells, wind or ocean noise, rare low bells |
| **Sleep** | Dark and low; simplifies over time | A single root drone with a minor colour | None | Low drone, pink noise easing into brown, a sub swell; layers drop out one by one as the fade runs down |

Each mood also has a **texture** setting: Auto (follows the weather),
None, Rain, Wind, or Brown noise. It is remembered per mood.

### What the inputs change

All inputs move the same small set of knobs: key centre, tempo, density
(notes per bar), brightness (filter cutoff and voice choice), reverb size,
and per-layer gain.

- **Time of day.** Morning (05:00 to 11:00) raises the key centre a whole
  tone and opens the filter; evening (18:00 on) lowers and darkens. After
  22:00, Focus and Brainstorm cap brightness at the evening level.
- **Heart rate.** In Focus and Brainstorm the tempo stays put, but density
  falls as the pulse rises above the person's resting rate (a racing heart
  gets fewer notes). In Relax and Sleep the breathing cycle and the swell
  rate settle toward a pace matching 0.9 times the resting rate, to pull
  the listener down gently. The resting rate comes from Health; if it is
  missing, 60 is used.
- **Timer phase.** Work blocks hold steady. Breaks lift into a lighter
  major variation and drop the pulse. In the last 60 s of a work block the
  density and gain ease down so the end bell is not a shock.
- **Weather and recovery.** With texture on Auto, rain or drizzle adds the
  rain layer, snow adds a soft hiss, wind over 30 km/h adds wind. On a day
  whose recovery is in the red band, tempo drops 8% and brightness drops
  one step.

Parameter changes glide over 2 to 8 s; nothing jumps.

## 2. Timers

| Mood | Kind | Presets |
|---|---|---|
| Focus, Brainstorm | Pomodoro | 25 work / 5 break, a 15-minute long break after every 4th block (default); 50/10; 90/20. Block count: 4 by default, or open-ended. |
| Relax | Countdown | 10, 20, 30 minutes, or open-ended |
| Sleep | Fade-out | 15, 30, 60 minutes, or all night |

The chosen preset is remembered per mood.

Timers run from wall-clock deadlines, not ticks, so a suspended or locked
app stays exact. Each block end is scheduled as a local notification when
the block starts and cancelled if the session pauses or ends. Pausing
freezes the remaining time.

The Sleep fade lowers the master gain along an equal-loudness curve and
drops layers in a fixed order (bells, pad, noise, drone last). At zero the
engine stops and the session ends quietly with no notification.

## 3. Architecture

### LifeOSKit: a new `Soundscape` target

Pure Swift, no UI, testable on macOS, depends on nothing else in the kit.

- **`Mood`** and **`MoodRecipe`**: the four recipes above, expressed as
  data (scale degrees, tempo range, layer list, change rules).
- **`Conditions`**: time of day, heart rate and resting rate (optional),
  phase (work, break, closing minute, fading with progress), weather
  kind and wind (optional), recovery band (optional), texture choice.
- **`SoundParameters.make(recipe:conditions:)`**: one pure function from
  conditions to knob values. Every adaptive rule in section 1 is a branch
  here and gets its own test.
- **`Composer`**: a seeded, deterministic event generator. Each bar it
  emits note and chord events for each layer from the recipe and the
  current parameters. The same seed always yields the same piece.
- **`Voices`**: pad (detuned saws through a low-pass), bell (two-operator
  FM), pluck (Karplus-Strong), pulse (sine sub with a soft click), drone,
  and noise textures (brown, pink, rain as filtered noise plus random
  drops, wind as swept band-pass noise). A shared reverb and a final soft
  limiter. Voices render into preallocated buffers: no allocation, locks,
  or reference counting on the audio thread.
- **`SoundscapeRenderer`**: drives the composer and mixes the voices into
  a stereo buffer. It has two outputs that share every line of DSP code:
  live (pulled by the app's source node) and offline (to a WAV file).
- **`FocusTimer`**: the state machine for all three timer kinds. It takes
  a clock, so tests can jump through hours and through background gaps.

A small executable target, **`soundscape-render`**, writes WAVs for tuning:
`swift run soundscape-render --mood focus --minutes 3 --hour 9 --hr 95 --weather rain --seed 7`.

### The app: `Features/Focus`

- **`SoundscapeEngine`**: owns `AVAudioEngine` with one `AVAudioSourceNode`
  pulling from the renderer. Sets the audio session to `.playback`. Hands
  `SoundParameters` to the render thread as one atomically swapped
  snapshot. Mood swaps crossfade over 8 s between two renderers.
- **`MusicSource`**: MusicKit. Asks for authorisation, checks the
  subscription, and picks Apple Music editorial playlists by mood (Focus:
  focus and deep work; Brainstorm: upbeat instrumental; Relax: calm and
  ambient; Sleep: sleep), preferring ones personalised to the listener
  when MusicKit offers them. Plays through `ApplicationMusicPlayer`.
  Breaks lower the volume rather than change tracks.
- **`FocusSessionModel`**: owns the `FocusTimer`, the active sound
  source, and the inputs (clock, `WeatherKitProvider`, today's recovery,
  Watch heart rate). Rebuilds `Conditions` when any input changes.
- **Screens**: `FocusSetupSheet` and `FocusSessionScreen` (section 4).
- **System**: the `audio` background mode; Now Playing info and lock
  screen play, pause and skip-phase commands through
  `MPRemoteCommandCenter`; block-end notifications.
- **Storage**: a SwiftData `FocusSessionRecord` (mood, source, started,
  ended, focused seconds, blocks completed, optional project task id).
  Every field is optional or defaulted so existing stores still open.

### Watch heart rate

`PhoneCommand` and the bridge gain a **focus** session kind. On it, the
Watch starts an `HKWorkoutSession` with the mind-and-body activity type so
heart rate streams every few seconds, shows a minimal "Focus · ♥ 64"
screen instead of the workout HUD, and discards the workout at the end
instead of saving it. With no paired or reachable Watch, heart rate is
simply absent from `Conditions`.

## 4. The experience

**Starting.** Three ways in:

- **Today**: a new `focus` module in the Today catalog: four mood tiles and
  "Resume last".
- **A project task**: a "Focus on this" action, which ties the session to
  the task.
- **Siri, Shortcuts and LIFO**: a `StartFocusSessionIntent` App Intent with
  an optional mood.

Each opens the setup sheet: mood (four tiles), sound (Soundscape, Apple
Music, Silence), timer preset for that mood, and texture (Soundscape only).
Everything defaults to what was last used, so Start is one tap.

**During.** A full-screen view in the editorial theme:

- a large timer and the phase ("Focus 2 of 4", "Break", "Long break")
- the task name, when the session came from a project task
- a slow generative visual of soft concentric shapes that breathe at the
  engine's tempo and brighten with its brightness, driven by the same
  `SoundParameters`; with Apple Music or Silence it follows the timer only
- small readouts: live heart rate (when the Watch is on), the texture, the
  sound source
- controls: pause, skip phase, end, change mood (crossfades without
  resetting the timer), volume
- Sleep dims to near black and shows only the fade remaining

**Ending.** A short summary: minutes focused, blocks completed, and for a
project task "Mark task done?". Today can show "Focused today" from the
saved records.

**Apple Music unavailable.** Without a subscription or with access denied,
the Apple Music option explains why in one line and the session falls back
to Soundscape.

## 5. Errors and edge cases

- **Interruptions** (calls, Siri, other audio): the engine pauses with the
  audio session and resumes when the interruption says it may. The timer
  keeps running.
- **Route changes**: headphones unplugged pauses playback.
- **Missing inputs are left out, never guessed**: no Watch, no heart rate;
  weather failure, the texture falls back to the per-mood choice (Auto
  becomes None); no recovery, neutral.
- **The audio thread never blocks.** A render overrun outputs silence for
  that buffer rather than stalling.
- **CPU and heat**: the engine targets under 5% CPU on an iPhone 15. At
  the `serious` thermal state it shortens the reverb and drops to the core
  layers.

## 6. Testing

- **Unit tests in `SoundscapeTests`**: each recipe's shape; every adaptive
  rule in `SoundParameters.make`; the composer's determinism and that every
  note stays in the recipe's scale; `FocusTimer` for Pomodoro, countdown
  and fade, including long breaks, pause, skip, and background gaps; voices
  output finite values and the limiter keeps peaks under 0 dBFS; a
  performance test that renders 10 minutes offline well under real time.
- **Listening**: `soundscape-render` WAVs for each mood at 09:00 and
  23:00, at resting and high heart rate, and with rain. The owner listens
  before the engine is called done.
- **App tests**: `FocusSessionModel` with a fake clock and fake inputs
  (conditions rebuild, mood swap, fall back from Apple Music).
- **UI tests (XCUITest)**: start from the Today module, set up, the session
  screen running, change mood, end, the summary.
- **Hardware checks** (cannot be done in the simulator): background audio
  with the screen locked, lock-screen controls, Watch heart rate streaming,
  Apple Music playback.

## 7. Owner steps

- Enable the MusicKit app service on the App ID `com.shivvyas.lifeos`.

## Out of scope

Live Activity and Dynamic Island, music during workouts, recorded field
textures, syncing focus sessions to the server.

## Changes made while planning

- The Watch focus session is marked by its mind-and-body activity type on
  both sides; there is no new phone command, and the phone ends it with the
  existing discard command.
- A render that cannot keep up does not output silence: after sustained
  overruns, or at the `serious` thermal state, the engine drops into a light
  mode (no reverb, no bells, plucks or pulses) and keeps playing.
- The app has no unit-test target, so the session logic a test needs
  (conditions, source fallback, phase mapping, the timer) lives in the kit
  and is tested there; the app's session model is thin glue covered by the
  UI test.
- Apple Music offers no volume control to the app, so breaks pause the
  music and the next work block resumes it.
- LIFO does not call App Intents today, so starting a session from LIFO is
  left out of this build; Siri and Shortcuts get the intent.
