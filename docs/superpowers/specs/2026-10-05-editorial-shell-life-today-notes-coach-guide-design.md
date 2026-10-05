# Editorial theme, part two: shell, Life, Today, Notes, coach, guide

Decided 2026-10-05. Finishes the "then, in the same style" list from the
2026-10-05 editorial theme spec, so no tab, sheet or tour keeps its own
palette. Two choices made up front with the owner:

- **The demo is teaching empty states**, not a separate demo mode. A tab
  with nothing in it shows a ghosted sample of what it will look like and the
  one action that fills it.
- **The LIFO voice orb goes.** Voice shows a plain ink waveform. The aura
  background and the forced dark scheme go with it.

Everything below follows the rules already set: paper is `LifeOSTokens.canvas`,
ink is `primaryText`, hairlines are `Editorial.rule`, one gradient field per
screen at most, the accent only for what is live or urgent, every button an
`.editorial(role)` style, and no per-module palette anywhere.

## 1. Shell header

One header on all five tabs, built once in `RootView` and applied through the
environment the way `quickActions` already is.

| Position | Control | Form |
|---|---|---|
| Leading (Today only) | Month calendar | Bare `calendar` glyph, as today |
| Trailing, innermost | Calendar assistant | Bare `calendar.badge.clock` glyph, 34pt hit area |
| Trailing | LIFO | Outlined word pill "LIFO" (`EditorialTag` as a button) |
| Trailing | Start / Live | Ink capsule with glyph and word, as today; `Live` with a timer glyph while a session runs |
| Trailing, outermost | Profile | `ProfileAvatar`, 30pt, opens Settings |

- `QuickActionsToolbar` grows a leading-avatar slot fed by a new
  `@Entry var shellProfile: ShellProfile?` (`photo: Data?`, `open: () -> Void`).
  `ProfileAvatar` moves from `LIfeOS/Components` into `DesignSystem` so the
  modifier can draw it. The modifier is renamed `shellToolbar()`; the old name
  stays as a deprecated alias until every call site is moved in this work.
- `ActionFan.row` draws a non-prominent action that has a `shortLabel` as an
  outlined pill rather than a bare glyph; the LIFO action gets
  `shortLabel: "LIFO"` so it reads as a word. The assistant keeps the glyph:
  its label is three words and the bar has no room.
- Every tab's root stack sets `.toolbarBackground(canvas, for: .navigationBar)`
  and `.toolbarBackground(.visible)`, so the bar is paper, not translucent
  system material over the masthead.
- Notes and Life drop their system titles (`navigationTitle`, large title) and
  carry `EditorialMasthead` in content like Health and Money. The bar holds
  only the controls above.
- Pushed screens (metric detail, sector detail, note editor, month) keep inline
  system titles and the back button; they do not repeat the shell controls.

## 2. Life

### Board (`LifeBoardScreen`)

- Masthead. Eyebrow `LIFE · OCTOBER`. Headline by mode: in flight
  `18 days left`; closed `September closed`, or `Nothing closed yet` when no
  month has been scored. Support line: in flight `62% of this month is
  decided`; closed `Lowest: Friends · Biggest move: Body +2`, omitting a part
  that has no value.
- Mode switch. The segmented `Picker` becomes `UnderlinePicker` with
  `This month` and `Last close` (in flight first, because it is the mode with
  something to do).
- Close banner. Becomes an `editorialCard()` with the dashed rule removed:
  title `Close September`, a chevron, and when expanded one sentence and a
  `.editorial(.primary)` `Score now` button.
- Teaching empty state (no closed month and nothing in flight): a ghosted
  deck of three bands at 35% ink with sample sectors and scores, the sentence
  "Nine sectors, scored once a month. The board shows where life stands.",
  and `.editorial(.primary)` `Score this month`.

### Deck (`SectorStack`)

- Cards are paper with a hairline edge (`editorialCard` radius, no fill
  gradient). Neighbours separate by the hairline and by the index, not by
  colour.
- Band: `01` index in quiet ink (`Editorial.index`), sector title in
  `Editorial.headline(22)`, the score as a light figure (`Editorial.figure(28)`,
  `/10` or the in-flight range in quiet ink), and a `chevron.down` in quiet ink
  that rotates 180° when open. The chevron is the affordance the deck was
  missing: the band now says it opens.
- Open card: the screen's one `EditorialField(.dusk)`. The trend line sits
  above a `RoundedBarChart` drawn in ink (new `style: .ink` on the chart: bars
  in the field's ink, track in the rule colour). `Open Body` becomes
  `.editorial(.secondary)` with a trailing `arrow.right`.
- `SectorPalette.tone`, `SectorPalette.hue` and `cardInk` are deleted.
  `SectorPalette.icon` stays.

### Sector detail (`SectorDetailScreen`)

- The pastel header becomes the screen's field: `EditorialField(.dusk)` with
  eyebrow `BODY · SEPTEMBER 2026`, `EditorialFigure(label: "Score", value:
  "7", unit: "/10")`, and the sector icon in the corner.
- Bands become numbered sections on paper: `01 Observations`, `02 Trend`
  (ink bars), `03 Why September` (`EditorialRow`s), `04 Answers over time`,
  `05 Notes`. Index numbers are assigned to the sections present, so a
  sector with no notes ends at `04`.
- `Open Body` is `.editorial(.secondary)` with an arrow, full width, last.
- Empty state card keeps its sentence inside an `editorialCard()`.

### In flight (`InFlightSectorScreen`)

- Masthead: eyebrow `BODY · IN FLIGHT`, headline the range (`6 to 8`) or
  `Not read yet`, support line `18 days left`.
- Sections: `01 What moves it most`, `02 Read it now`, `03 If nothing
  changes`, `04 If you finish at your targets`; rows are `EditorialRow`.
- The default-targets note stays as quiet ink under the last section.

### Monthly close (`MonthlyCloseScreen`)

- Masthead replaces the icon-and-title header: eyebrow
  `CLOSE SEPTEMBER · 3 OF 9`, headline the sector title. The inline nav title
  goes; Skip and Next stay in the bar as text buttons.
- `Proposed` becomes an `EditorialFigure` inside an `editorialCard()`, with
  the evidence as `EditorialRow`s under it and `NO EVIDENCE YET` as an
  `EditorialTag` when there are none.
- `Your score` keeps `HeroNumeral` and the system `Stepper` (accent tinted).
- The done view becomes a masthead `Month closed` with `.editorial(.primary)`
  `Done`.

## 3. Today

- Masthead. Eyebrow `TODAY · MONDAY, OCT 5` (a past day reads `OCT 3` with no
  weekday); headline `Good morning`, `Good afternoon` or `Good evening` by
  hour; support line the streak, `6-day streak`, or `Start a streak today`.
- The one field is the agenda. `AgendaCard` becomes `EditorialField(.dusk)`
  with eyebrow `NEXT UP`, the next event's title as the headline and its time
  as the support line, then the rest of today as `EditorialRow`s (time left,
  title right) and an `Add` text button in the field's ink. When the calendar
  is not connected, the field is the teaching empty state: three ghosted
  sample rows and `.editorial(.primary)` `Connect calendar`.
- The month dot grid stays as it is; it is already ink on paper.
- Metric tiles. `TrendStatTile` gains an `ink` style: hairline card, eyebrow
  label, light figure with unit, a seven-day sparkline in ink, and an
  `arrow.up.right` in quiet ink at the top trailing corner so the tile reads
  as a link. Today uses this style; Health keeps whatever it uses now.
- Scheduled workout becomes an `EditorialRow` with a dumbbell glyph and an
  arrow, inside an `editorialCard()`.
- The health prompt becomes an `editorialCard()` with `.editorial(.primary)`
  `Connect Apple Health`. When Health has no data and nothing is connected,
  the tiles show ghosted sample figures at 35% ink behind that card.

### Month and schedule (added 2026-10-05, from two references)

The Today tab's own dot grid does not change. This covers the two screens
behind it: the month screen the bar's calendar button opens, and the
schedule a day opens onto.

- **Month screen** (`MonthScreen`). Masthead eyebrow `MONTHLY · 2026`,
  then one block per month, scrolling: the month name in `Editorial.headline(34)`
  with the accent for the current month only, a weekday row in quiet ink, and
  a seven-column grid of hairline cells. A past day is hatched: three thin
  diagonal strokes in the accent at 45°, drawn by a `HatchedCell` shape.
  Today is a filled accent cell with paper ink. A day with events carries a
  2pt ink dot under its number. Tapping a day pushes the schedule at that
  day. `Go back` is `.editorial(.secondary)` at the foot, in addition to the
  system back button.
- **Schedule** (`DayScheduleScreen`, replaces `DayDetailSheet` as a push).
  Masthead eyebrow `WEEKLY · OCTOBER`. Then the seven days of the chosen
  week stacked: each day is a band with its number in `Editorial.figure(64)`
  (the accent for today, ink otherwise, quiet ink for past days) and, beside
  it, the day's events as rows of `time · title · arrow.right` separated by
  hairlines. A day with no events shows the number only. The bands are
  separated by hairlines, as in the stacked-day reference, and the chosen
  day's band is the one expanded with its `Add` text button; the others
  show only their numbers and a count tag (`3 events`) until tapped.
- Both screens are paper and ink with the accent for today and the hatch
  only. No gradient field.
- Preview pages `month` and `schedule`, with `--dark`.

Delivered in PR 2 with Today and Notes.

## 4. Notes

- Masthead. Eyebrow `NOTES · 24 PAGES` (`1 PAGE`, `NO PAGES`); headline
  `model.headerTitle` as it is today (`All pages` or the folder name).
- The large-title row goes. The library toggle on iPad stays as a bare glyph
  leading in the bar; on iPhone the folder browser stays in the bar as today.
- Create. The plus square becomes a `.editorial(.primary)` capsule `New page`
  that opens the same menu (blank page, today's journal, task list, new
  folder).
- Search is a hairline underline field: magnifier, the field, a rule under it,
  and a clear glyph while there is a query.
- The count, filter and sort row becomes an `EditorialSectionHeader` titled
  `Pages` with the filter and sort as its trailing text buttons.
- The list loses its card surface. Rows are `NoteCard` on paper separated by
  `Hairline`, each with a trailing `arrow.right` in quiet ink.
- Teaching empty state (no pages, not searching): three ghosted sample rows
  (`Monday journal`, `Groceries`, `Ideas for the trip`), the sentence
  "Pages, journals and task lists, all in one place.", and
  `.editorial(.primary)` `Create a page`. The no-results state keeps its
  sentence and a `.editorial(.secondary)` `Clear search`.

## 5. Chat

### LIFO (`LifoCoachScreen`)

- Follows the system colour scheme. `preferredColorScheme(.dark)`, `LifoAura`,
  `LifoPalette` and `CoachVoiceOrb` are deleted. `CoachScreenStyle` keeps its
  two modes but no colours.
- Header: `LifeOSMark` (from PR #18; the sparkle until that merges) beside
  `LIFO` in `Editorial.headline(22)` with `Your personal coach` or
  `Voice conversation` as the eyebrow. History and close are bare glyphs.
- Opening: the two display lines in ink, `WHERE SHALL WE START?` as an
  eyebrow, suggestions as outlined pills (`EditorialTag` as buttons) that wrap.
- Transcript: a user turn is the question in ink inside a hairline-outlined
  block aligned trailing. A reply is `CoachResponseView` on paper, numbered
  steps drawn with `IndexPill`, tables with hairline rules. `Thinking…` is a
  quiet-ink line. The sent-context disclosure stays, in quiet ink.
- Composer: a hairline-outlined bar with the field, a send button as an ink
  circle with `arrow.up`, and the voice toggle as an outlined circle with a
  `waveform` glyph beside it.
- Voice: `CoachAudioWaveform` in ink, 56pt tall, the full width of the
  content, replaces the orb. It turns accent while listening and while
  speaking, and ink otherwise. Title and subtitle become a masthead
  (`I'm listening` as the headline). The microphone is an ink circle that
  turns accent while listening; the keyboard switch is an outlined circle.

### Calendar assistant (`AssistantSheet`)

- Masthead: eyebrow `CALENDAR ASSISTANT`, headline `Make room for your day`,
  support line the connection sentence.
- Prompt suggestions are hairline rows with a trailing `arrow.up.left`.
- Turns, composer and `Thinking…` match LIFO exactly; both screens share the
  same private views moved into `DesignSystem` as `ChatTurn`, `ChatComposer`.
- The confirmation card is an `editorialCard()` with `.editorial(.primary)`
  `Confirm` and `.editorial(.secondary)` `Cancel`. Tool summaries are
  `EditorialTag`s.
- `Connect calendar` is `.editorial(.primary)`.

## 6. Guide, tour and teaching empty states

### How LifeOS works (`HowLifeOSWorksScreen`)

A pushed screen on paper. Masthead: eyebrow `GUIDE`, headline `How LifeOS
works`, support line `Eight places, one home.` Then eight numbered sections.
Each has one sentence of what and one of how, and a `Go` text button with an
arrow where a route exists.

| # | Section | What | How | Go |
|---|---|---|---|---|
| 01 | Today | Your day on one page: agenda, streak, readings. | Tap a tile for its history, the date for another day. | Today tab |
| 02 | Health | Sleep, recovery, steps and weight from Apple Health, Whoop or Fitbit. | Connect a source in Settings; readings fill in on their own. | Health tab |
| 03 | Money | Every account and transaction, by month and by category. | Connect a bank, or add a transaction by hand with Add. | Money tab |
| 04 | Notes | Pages, journals and task lists. | New page starts one; the folder button files it. | Notes tab |
| 05 | Life | Nine sectors scored once a month. | Open a band for the trend; Score this month when the banner appears. | Life tab |
| 06 | LIFO | A coach that reads your numbers and answers in plain words. | Tap LIFO in the header; speak with the waveform button. | Opens LIFO |
| 07 | Start | A live session from the phone or the watch. | Tap Start, pick an activity; Live brings you back to it. | Opens Start |
| 08 | Calendar assistant | Moves and makes events for you. | Tap the calendar glyph in the header and ask. | Opens the assistant |

`SurfaceRoute` gains `money`, `notes`, `life`, `coach` and `assistant` so
`Go` can hand off to `RootView` the same way notifications already do.

Entry points: a `How LifeOS works` row under `At a glance` in Settings, and
the `Read the guide` button on the tour.

### First-run tour (`FirstRunTour`)

Rebuilt on the theme and kept to one screen: masthead `WELCOME` /
`Welcome home.` / `A few good places to start.`; the cat stays; three numbered
rows on paper with hairlines (`01 Start with Today`, `02 Connect your world`,
`03 Talk it through`); `.editorial(.primary)` `Open my day` and
`.editorial(.secondary)` `Read the guide`, which pushes the guide and marks
the tour seen.

### Teaching empty states (`EditorialEmptyState` in `DesignSystem`)

One component: an eyebrow `SAMPLE`, a ghosted body passed in by the caller
and drawn at 35% ink with hit testing off, one sentence, and one
`.editorial(.primary)` action. Used by Today (agenda, tiles), Notes, Life,
and by Health and Money where they already have empty states; those two only
swap their existing empty views for this component with the sentences below.

| Tab | Sample | Sentence | Action |
|---|---|---|---|
| Health | four readings | Sleep, recovery, steps and weight, read every morning. | Connect Apple Health |
| Money | a month figure and three rows | Every account in one place, by month and by category. | Connect a bank |

## 7. Verification

- Design preview pages, all DEBUG only and fixture fed, each with `--dark`:
  `--page=shell` (a paper screen under the full header), `life`,
  `life-empty`, `life-detail`, `life-inflight`, `life-close`, `today`,
  `today-empty`, `notes`, `notes-empty`, `coach`, `coach-voice`, `assistant`,
  `guide`, `tour`.
- Every PR: `swift test` in LifeOSKit, `scripts/check-typography.sh`, a
  simulator build, and light and dark screenshots of its pages reviewed
  against this spec before the PR opens.
- Accessibility: every band, tile and row that opens something carries
  `.isButton` and a hint; the ghosted samples are `accessibilityHidden`.

## 8. Delivery

Four PRs, each rebased on the one before:

1. `feat/editorial-shell-life`: this spec, the shell header, Life, the
   `ink` chart style, `EditorialEmptyState`.
2. `feat/editorial-today-notes`: Today and Notes, the `ink` tile style, the
   month screen and the day schedule.
3. `feat/editorial-coach`: LIFO and the assistant, the shared chat views,
   deletion of the aura and orb.
4. `feat/editorial-guide`: the guide, the tour, the routes, the Health and
   Money empty-state swaps.

After the fourth merges, build 50 for the next upload.

## Out of scope

- Settings, Profile, Connections, Social and the Workout library screens.
- Health and Money beyond the empty-state swap.
- The watch app and widgets.
- iPad: layouts keep working as they do; no iPad-specific redesign.
- Any change to what the coach or assistant sends or stores.
