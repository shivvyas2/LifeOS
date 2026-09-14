# Coach voice and response UI — 2026-09-14

## Changes

- Replaced the coach's flat animated shape with a SceneKit bubble: lit 3D geometry, continuous organic deformation, gentle breathing, drag-to-tilt and tap feedback.
- The renderer interpolates incoming audio with frame-rate-independent attack/release smoothing. Microphone capture and speech endpoint detection are unchanged. The bubble responds only to microphone levels while listening, and to metered AVAudioPlayer output during spoken replies.
- Voice playback now exposes levels, stops metering with playback, handles stale completion callbacks safely, and stops before opening the microphone. Leaving/backgrounding the screen stops voice activity and the rendering display link. Reduce Motion keeps the bubble static.
- The bubble remains visible at rest, with clear listening/thinking/speaking labels and an explicit Stop action during playback.
- Kept the blue gradient, softened its cyan center and added warm paper response panels. Dynamic metric cells and comparison headers use pale blue; orange remains the action and brand accent. Paragraphs, comparison tables, metric cells and action rows remain content-driven.
- Suggestions, composer and chrome use rounded rectangles. Corrected placeholder contrast on the light composer and enlarged send/history/close targets.
- The main Today screen, its dots, metric tiles and agenda remain unchanged. Earlier calendar/Health edits are preserved separately.

## Verification

- Final normal iOS simulator build: **BUILD SUCCEEDED**.
- Full Swift package suite: **1,174 tests passed in 153 suites**. New audio tests cover fast attack, slow release, silence decay, frame-rate independence, invalid samples and decibel clamping. Existing structured response parsing tests pass.
- iPhone 17 Pro / iOS 26 visual inspection used a separate preview bundle with sample replies and simulated sound. No live microphone capture, provider request or account write was performed during the preview checks.
- Inspected the bubble, response panel, metric cells, comparison headers, listening status and composer. Reduced overbright lighting and fixed a faint placeholder, then rebuilt and inspected the corrected screen.
- A seven-second simulated-audio recording confirmed changing 3D geometry; frames at one and five seconds show different contours. Recording is a local QA artifact at `/private/tmp/lifeos-coach-animation.mp4`.
- `voice-and-cards.png` captures the final layout. The temporary preview app entry point was restored, and the normal app rebuilt successfully.
- `git diff --check` passed. Explicit diff checks confirm TodayScreen, AgendaCard, TrendStatTile, DotGrid, MonthCalendarView and LIfeOSApp remain unchanged.
- Live microphone/TTS end-to-end behavior, physical-device frame rate and iPad runtime layout remain unverified. Reduce Motion and teardown paths were code-reviewed and compiled; the read-only accessibility environment was not overridden in the fixture.
