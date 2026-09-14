# Coach: text and voice

The coach now opens into a blue text conversation. The waveform button opens a separate green voice presentation of the same model, history, draft, pending question, and response. Returning to text stops active recording and speech playback, while preserving an answer already being generated or transcribed. Voice mode requires a microphone tap; navigation does not start recording. Spoken replies honor the existing voice setting and provider configuration, and are suppressed in text mode.

## Visual system

- Cobalt/periwinkle light fades into ink on the text screen; compact suggestions sit above the persistent composer.
- Sage light fades into forest-black on the voice screen; an emerald/teal glowing orb responds to measured input/output audio and touch. Its flowing microtexture, continuous deformation, and reduced-motion/transparency behavior are retained.
- The waveform shows rolling amplitude samples, with a quiet baseline when audio is inactive.
- Shared app typography and the small orange LIFO brand mark connect both experiences to Almanac.
- Responses use the existing content parser: plain prose, metric cells for two-column tables, horizontally scrollable comparisons for wider tables, and numbered action rows. Ice-blue and pale-mint cards use dark readable text. All values come from the reply.
- Text shows the conversation; voice surfaces the current/latest turn. Earlier turns remain available through History from either screen.

## Preview fixtures

`CoachDesignPreview` is DEBUG-only and is not the production app entry point. `--empty` shows the opening, `--voice` selects voice with simulated amplitude, and `--controls` exposes the fixture controls. All shown health data are synthetic fixtures. The normal app entry point is restored after preview compilation.

Validation results and limitations are recorded below after the native checks and captures.

## Validation

- Normal iPhone simulator app build: **BUILD SUCCEEDED**, including app/widget/watch targets. Production app entry point is unchanged.
- `CoachResponseTests` + `AudioEnvelopeTests`: **11 tests passed**. Coverage includes short prose, action lists, valid and malformed tables, escaped pipes, negative values, and bounded/smoothed audio levels.
- Five isolated native mode-transition checks covered in-flight reply preservation, conversation/draft preservation, suppression of spoken replies in text, busy-send draft retention, and cancelling unsent recording when returning to text.
- Native preview inspection covered the text opening, blue structured reply, green voice opening, and green structured reply using synthetic data. The reply/control overlap found during inspection was corrected with an opaque footer and a more compact voice presence when a reply exists.
- The Mac locked before interactive tap-through testing could finish. Microphone permission flows, real provider speech round-trips, physical-device animation performance, and iPad hardware interaction were not re-verified in this pass. No microphone or remote AI call was made by the preview.

Follow-up: the voice ribbon was subsequently replaced by a glowing spherical orb. See `../coach-glowing-orb/implementation.md`.
