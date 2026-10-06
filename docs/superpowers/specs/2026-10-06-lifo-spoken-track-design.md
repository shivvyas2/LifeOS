# LIFO spoken track: a voice that explains the screen

Decided 2026-10-06 with the owner. Today the model writes one `SAY:` line
that the voice reads while the cards appear in silence under it, and the
result reads as a summary followed by a dump. The owner's words: the speech
should be different from what is shown, but the two should work together so
it feels like LIFO is explaining the screen rather than reading it out.

Chosen: **per-section narration on the existing ElevenLabs voices, capped,
with each card revealing as its narration begins.** Rejected: narration on
the free device voice (two voices in one answer), and a single warmer line
(no explanation of the sections).

## 1. What the person hears and sees

- LIFO speaks in two to four short spoken passages. The first is the
  opening, as now. Each later passage belongs to one section of the written
  answer and says what that section shows in plain speech: the point of the
  table, not its cells.
- The written answer appears section by section, each section sliding in
  the moment its passage starts to play. While a passage plays, the sections
  after it are not yet on screen. When the voice finishes, everything is on
  screen.
- With the voice off, or when it fails, every section appears at once, as
  today, with no narration fetched and nothing billed.
- A passage never contains a table, a list, markdown, a quotation mark or
  more than one figure. A section with nothing worth saying has no passage
  and appears with the passage before it.

## 2. The reply grammar

`SpokenReply` becomes `SpokenTrack` in `Insights`. The model is asked to
interleave:

```
SAY: <opening passage>

<section 1: paragraph, or heading plus table or list>

SAY: <passage about section 1>

<section 2>

SAY: <passage about section 2>

<section 3>
```

Rules the prompt states (`CoachPresentation.spokenTrackInstruction`
replaces `spokenLineInstruction`):

- The reply begins with one `SAY:` line, the opening: one or two sentences,
  the useful answer in speech, at most one figure.
- A `SAY:` line may precede each later section. It says what the section
  shows and why it matters, in one or two sentences, with at most one
  figure, no markdown, no list, no quotation marks. It must not repeat the
  section's cells or the written sentences word for word.
- At most four `SAY:` lines in a reply, each under 220 characters. The
  written sections follow the existing structured rules unchanged.

`SpokenTrack(parsing:)` yields `segments: [Segment]` in order, where
`Segment { spoken: String?; shown: String }`: `shown` is the text of the
sections between this `SAY:` line and the next, and `spoken` is the cleaned
passage (`ResponseStyle.clean`, trimmed) or nil when the segment had none.
The first segment's `shown` may be empty (the opening has no section of its
own); later segments without a `SAY:` line are merged into the segment
before them. `shownText` is every `shown` joined by blank lines, which is
what the transcript stores and the screen renders. `isOpeningPending` is
true while the text so far could still turn out to begin with `SAY:`, the
same rule as today's `isSpokenLinePending`. Built from partial text as well
as whole text, so the voice starts on the opening while the sections are
still arriving, and a later passage can be queued the moment its line is
complete.

`CoachResponse.spokenText`, the flattening that read tables as
`Metric: Value`, is deleted. Nothing may ever speak a table. The fallback
when the model wrote no `SAY:` line at all stays what it is: the first plain
paragraph, once.

## 3. The budget

- `SpokenTrack.capped(to characters: Int = 700)` returns the segments with
  their passages trimmed to the budget in order: a passage that would cross
  the budget is cut at the last sentence boundary that fits, and passages
  after the budget is spent become nil, so their sections reveal with the
  passage before them. The opening is never dropped. This replaces the
  1,200-character cap in `ElevenLabsVoiceClient`, which becomes the
  per-request ceiling for one passage.
- `VoiceBudget` in `Insights`, tested: a per-account monthly counter of
  characters sent for synthesis, keyed `voice.characters.<yyyy-MM>` in
  `UserDefaults.currentAccount`, with `remaining(now:)`, `debit(_:now:)` and
  `monthlyAllowance = 30_000`. At ElevenLabs Flash's published rate of about
  five cents per thousand characters, a full month is about one dollar
  fifty, inside the cost ceiling with room for the rest of the stack, and
  about forty narrated answers.
- When the allowance is spent, narration continues on the device voice
  (`AVSpeechSynthesizer` with the system's enhanced voice if installed) for
  the rest of the month, and the voice screen shows one quiet line,
  `Premium voice resumes on the 1st`. The owner chose ElevenLabs for the
  main path; the device voice is the fallback only, so the voice never
  simply stops mid-month. Settings shows the month's usage under the voice
  picker as `12,400 of 30,000 characters`.

## 4. Playback and reveal

- `VoicePlayer` plays a queue: `play(_ segments: [VoiceSegment])` where
  `VoiceSegment { index: Int; audio: Data }`, in order, and calls
  `onSegmentStart: ((Int) -> Void)?` as each begins. `stop()` clears the
  queue. `isSpeaking` is true from the first start to the last end.
- `CoachViewModel` fetches passages one request each, in order, starting the
  next fetch while the current passage plays, so there is never a gap longer
  than a fetch. A passage whose fetch fails is skipped and its section
  reveals with the next start, or immediately if it was the last. `turnID`
  guards every callback as today.
- `revealedSections: Int?` on the view model (nil means all) is set from
  `onSegmentStart`: segment `i` starting reveals sections up to and including
  the ones in segments `0...i`. `CoachResponseView(text:revealed:)` draws
  only the first `revealed` sections, each entering with `BlockReveal` as it
  is allowed in; sections already shown are never re-animated, exactly as
  `BlockReveal` behaves today. With `revealed` nil, every section is drawn.
- The two-second safety reveal stays: whatever the audio does, the whole
  answer is on screen within two seconds of the reply finishing when no
  passage has started, and any section still hidden when playback ends or
  is stopped is revealed at once.
- Typed questions on the text screen are not asked for a track and reveal
  as today; the track is asked for only when `voiceAvailable` is true, the
  same decision that today adds the spoken line.

## 5. The cloud tier

`supabase/functions/_shared/lifo.ts` carries no copy of the spoken grammar:
the device sends the full instructions for both tiers, as it does today, so
the only change is that `CoachPresentation.spokenTrackInstruction` rides in
the `cloud` render as well as `onDevice`. The Deno test that pins the shared
prohibitions is unchanged.

## 6. Verification

- `SpokenTrackTests` (Insights): whole text with three passages parses to
  three segments in order; partial text inside the opening is pending and
  shows nothing; a section without a passage merges into the previous
  segment; a reply with no `SAY:` lines is one segment with nil spoken and
  the full text shown; `capped(to:)` cuts at a sentence boundary, never drops
  the opening, and nils passages past the budget; `shownText` carries no
  `SAY:` line; the prompt contains the prefix and the written instruction
  does not.
- `VoiceBudgetTests`: debit and remaining within a month; a new month resets;
  the allowance is a constant the test reads rather than repeats.
- `CoachResponseTests`: `spokenText` no longer exists (the compile is the
  test); the parser is otherwise unchanged.
- Simulator: the `coach-voice` preview page (part two §7) gains
  `--track=3` which plays a fixture reply through a stub synthesiser that
  returns short silent audio, so the staged reveal can be captured as three
  frames one second apart; and `--budget-spent` shows the device-voice line.

## 7. Delivery

One PR, `feat/lifo-spoken-track`, after `feat/editorial-coach` (part two §5)
and before `feat/editorial-calendar-ask`, since the calendar's reply card
does not speak and the coach screen it follows must be on paper first. The
calendar spec's §6 order becomes: calendar switch, coach restyle, spoken
track, calendar ask, calendar widget, guide. Then build 50.

## Out of scope

- The assistant sheet and the calendar reply card: they do not speak.
- Any change to the voices offered, the listening side (`SpeechListener`,
  Scribe), or what the coach is given as context.
- A new voice provider.
