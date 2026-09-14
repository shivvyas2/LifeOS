# Health, account and activity update

The two supplied references inform the warm canvas, colored category surfaces, prominent readings, quiet dividers and reflection card. The implementation retains Almanac’s existing SF typography, orange actions and native navigation. Today’s dot screen and the profile’s portrait-derived glass background remain intact.

## Implemented

- Restored the original module pastels on Steps, Sleep, Weight and Recovery. Added matching dark colors and carried the palette through sleep, fitness, weight and journal cards.
- Movement, heart/fitness, body, vitals and walking groups use a featured reading and adaptive supporting cells. Only recorded values are shown; no illustrative health charts or scores are presented as real readings.
- Profile account destinations are glass cards, with a prominent Together destination. Connections and Settings have a warm canvas, coherent sections and constrained iPad widths.
- Profile activity sharing has a dedicated card naming its audience and contents. Existing consent and server behavior are preserved. Health-score sharing remains separate per group.
- Connected Fitbit’s Sync action now calls the existing forced refresh instead of reopening OAuth.
- The global plus opens Begin Activity. Quick Log remains available inside it. A running activity changes the action’s icon and label to Current activity.
- Walk, Run, Cycle, Strength, Yoga and Other; timer, pause/resume, finish/save and confirmed discard. Drafts survive closing/relaunch, are scoped to the current account and clear on account changes/logout.
- Native iOS 26 `HKWorkoutSession` / `HKLiveWorkoutBuilder` recording, with explicit Apple Health write permission. Completed sessions save to the current account’s local workout store and, when enabled, Apple Health. A stable local ID prevents repeated saves creating extra workouts.
- Bluetooth SIG heart-rate service discovery and user-selected pairing, including WHOOP Heart Rate Broadcast. Handles 8/16-bit samples, no-contact frames, permission errors, disconnects and stale readings. Scans stop after 30 seconds or when the sheet closes. Streaming stops at finish/discard/account change.

## Real-time boundaries

The live timer and Bluetooth readings update as they arrive. Energy and distance use actual HealthKit builder statistics, and missing measurements remain missing. WHOOP/Fitbit cloud data continues through the existing provider sync; it is not labeled as a live sensor stream.

There is no Apple Watch companion target in this repository. This update does not start/control Apple's Workout app or mirror it live. Existing Apple Watch measurements reach Almanac when they are written to Apple Health. WHOOP offers live heart rate through Bluetooth, not its cloud API. No WHOOP/Fitbit workout-creation endpoint is called.

Native guidance: [Apple workout sessions on iOS](https://developer.apple.com/videos/play/wwdc2025/322/). Provider capability: [WHOOP continuous heart-rate support](https://developer.whoop.com/docs/developing/support/).

## Verification

- iOS Debug build succeeds with the production app entry point.
- 1,202 Swift package tests pass, including elapsed-time, pause, persistence and Bluetooth decoding cases.
- The iPhone UI flow was exercised: Run → Begin → Pause (00:19 held fixed) → Resume → Finish (00:25), with correct local-only success copy.
- Nine native recorder checks pass on the iPad simulator using an in-memory database and disposable account defaults: start without Health access, pause, resume, restoration without unnecessary Health recovery, cross-account isolation, local finish, idempotent save, draft cleanup and deactivation.
- iPhone 17 Pro (402×874 points, iOS 26), iPad (834×1210 points, iOS 26.2), accessibility text and dark-mode captures are in this folder.
- Physical WHOOP/other Bluetooth sensors, Apple Watch delivery timing and HealthKit write permission/recording were not exercised on hardware. No real accounts or health records were used in validation.
- No backend change or deployment is required. Changes are local and have not been pushed.
