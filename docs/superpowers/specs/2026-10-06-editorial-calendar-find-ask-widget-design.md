# Editorial calendar: one screen, find and ask, and a widget

Decided 2026-10-06 with the owner, after the month screen and the day
schedule from the two Daily UI references shipped in PR #20:

- **The Today tab does not change.** Its masthead, agenda field, dot grid
  and tiles stay as PR #20 left them.
- **The header's calendar button opens one calendar screen** with a
  `Monthly | Weekly` switch. The week is no longer a pushed screen; tapping
  a day in the month switches to its week in place.
- **The screen gets a find-and-ask field.** Typing finds events locally and
  instantly. Return hands the words to the calendar assistant, whose reply
  lands on the same screen and moves the calendar to what it found.
- **A second widget**, on paper and ink, joins the existing `Your week`
  widget rather than replacing it.
- The LIFO and assistant restyle (part two §5) and the guide (part two §6)
  stay as specified; §6 below fixes the order they ship in around this work.

Everything follows the rules already set: paper is `LifeOSTokens.canvas`,
ink is `primaryText`, hairlines are `Editorial.rule`, the accent only for
today and the hatch, every button an `.editorial(role)` style, no gradient
field on any of these screens, and no per-module palette anywhere.

## 1. Calendar screen

`MonthScreen` becomes `CalendarScreen` (file renamed). `DayScheduleScreen`
becomes `WeekBands` (file renamed): the seven stacked bands as a body view
with no masthead and no scroll view of its own. Both callers move: the
header button in `RootView` and the `Schedule` link in `AssistantSheet`.

```swift
enum CalendarMode: Hashable { case monthly, weekly }
```

The mode is `@State` on the screen with an `initialMode` init parameter
(default `.monthly`) so previews can open on either.

Top to bottom:

1. **Header row.** `EditorialMasthead` as a button that opens the existing
   Go-to-date sheet; trailing, in one row: `Today` as
   `.editorial(.secondary, size: .compact)`, then the two chevron buttons as
   they are. `Today` is disabled when there is nothing to go back to: in
   Monthly when `model.month` is in the current month, in Weekly when the
   selected week contains today. The system bar's `Today` item goes, so the
   bar holds only Back.
   - Eyebrow by mode: Monthly `MONTHLY · 2026` (the year of `model.month`,
     not of today); Weekly `WEEKLY · OCTOBER` (the wide month of
     `model.selection`). Title `Calendar` in both. Detail line: none in
     Monthly; in Weekly the range, `Oct 4 to Oct 10`, abbreviated month and
     day of the first and last day of the week.
   - `CalendarHeadline.make(mode:month:selection:calendar:)` in
     `DesignSystem` owns this wording, with tests: the Monthly year follows
     the shown month across a year boundary; the Weekly month follows the
     selection; a range that crosses months reads `Sep 27 to Oct 3`.
2. **Switch.** `UnderlinePicker(selection: $mode, options:
   [(.monthly, "Monthly"), (.weekly, "Weekly")])`, the same control the Life
   board uses for its modes.
3. **Find-and-ask field** (§2).
4. **Connect card** when the calendar is not connected, as today.
5. **Body by mode.**
   - *Monthly*: the two month blocks exactly as PR #20 built them (hairline
     grid, hatched past days, accent today, a 2pt dot under days with
     events). A day tap calls `model.select(date)` and sets `mode = .weekly`
     inside `withAnimation(.snappy(duration: 0.22))`. The cell's accessibility
     hint becomes "Shows its week".
   - *Weekly*: `WeekBands(model:onTapEvent:onAddEvent:)` for
     `WeekSpan.days(containing: model.selection)`. The open band is the one
     whose day is `model.selection`; the number button of any band calls
     `model.select(date)`. Bands keep the 64pt figure, weekday eyebrow,
     `time · title · arrow.right` rows, `Add`, and the count tag on closed
     bands.
6. **`Go back`** as `.editorial(.secondary, fullWidth: true)` at the foot in
   both modes.

Navigation:

- Chevrons and the horizontal swipe step one month in Monthly
  (`model.step(±1)`) and one week in Weekly (`model.stepWeek(±1)`).
- `MonthViewModel.stepWeek(_ weeks: Int)`: moves `selection` by seven times
  `weeks` days (start of day), updates `anchorDay`, sets `month = selection`,
  and calls `load()` only when the month changed. The existing `load()`
  already pads a week either side of the two fetched months, so a week that
  starts in the previous month is answerable without a second fetch.
- `Today` calls `model.goToToday()` in both modes. The date picker calls
  `model.goTo(date)` and keeps the mode.

Accessibility: the switch options carry `.isSelected`; cells and bands keep
their labels and hints.

## 2. Find and ask

### The field

The Notes shelf's private hairline search becomes `HairlineField` in
`DesignSystem`, and Notes adopts it: a leading glyph (`magnifyingglass` by
default), a `TextField` with a placeholder, a clear glyph (`xmark.circle`)
while there is text, an optional trailing accessory view, and a `Hairline`
underneath. Here the placeholder is "Find or ask about your schedule" and
the submit label is `.search`. The accessory is the ask arrow below.

### Find, as you type

- `ScheduleSearch.matches(_ query: String, in events: [CalendarEventSnapshot])
  -> [CalendarEventSnapshot]` in `Persistence`, beside `nextUp(now:)`:
  trims whitespace; an empty query matches nothing; a match is
  `localizedStandardContains` (case- and diacritic-insensitive) on the
  title, the location or the calendar title; results are sorted by start
  then title and de-duplicated by id. Tests cover case and diacritics, a
  location-only match, the empty query, and the ordering.
- The scope is everything in `model.eventsByDay`: the two shown months plus
  their padding. Nothing is fetched on a keystroke.
- **Results block**, between the field and the body: eyebrow `FOUND 3` or
  `NOTHING FOUND`; one quiet sentence naming the scope, `In October and
  November. Ask for anything further out.`; then up to eight rows, each
  `Tue 13 · 10:00` in quiet ink (`All day` for all-day events), the title in
  ink, `arrow.right`, separated by hairlines. Past eight, a quiet `4 more`.
- A result tap calls `model.select(day)` and switches to Weekly with that
  day open. The query stays so several results can be visited.
- **Grid marks while a query is live**: a matching day draws its number and
  its dot in the accent (on the today cell the number stays paper); in
  Weekly a matching row draws a 6pt accent dot before its time.

### Ask, on return or the arrow

- The arrow is an ink circle, 32pt, with `arrow.up` in paper. It shows when
  the text is not empty and `canAsk` holds: an assistant model was passed,
  `modelAvailable` is true and `isAuthorized` is true.
- Sending sets `assistant.draft` to the text, awaits `assistant.send()`, and
  clears the field. From then until `Clear`, the **reply card** replaces the
  results block. It is an `editorialCard()` holding, top to bottom:
  - eyebrow `ASSISTANT`;
  - the question, as a quiet line;
  - `Thinking…` in quiet ink while `isThinking` and nothing is pending;
  - the reply text in `LifeOSType.secondary`;
  - the events the reply was about (`eventsByMessage[reply.id]`), drawn as
    the same rows the results block uses, each jumping the calendar;
  - tool summaries as `EditorialTag`s in a wrapping row;
  - each `PendingWrite` as its preview lines over `Confirm`
    (`.editorial(.primary, size: .compact)`) and `Cancel`
    (`.editorial(.secondary, size: .compact)`);
  - `Clear` as `.editorial(.quiet, size: .compact)`, which hides the card.
    The conversation itself stays in the assistant sheet.
- **The calendar follows the answer.** When a reply arrives with events, the
  screen selects the earliest one's day and switches to Weekly, so "find my
  dentist" lands on the week with the dentist in it.
- **Created events count as found.** `CalendarWriting.create` returns the
  created `CalendarEventSnapshot` (`CalendarSync.create` already gets one
  back from its source; the protocol just drops it today), and
  `CreateEventTool` records it in the `CalendarEventCollector`, so the card
  lists the new event and the calendar jumps to it. The existing
  `AssistantTests` for the tool are extended for this.
- **One assistant.** `CalendarScreen` takes `assistant: AssistantViewModel?`.
  `RootView` passes the `assistantModel` it already owns; the sheet passes
  its own; previews may pass nil. The screen calls `assistant.appear()` in
  its `.task`. A question asked here is a turn in the same conversation the
  sheet shows, and a confirmation answered here is answered there.
- **Without Apple Intelligence** the arrow is hidden and, once the field has
  text, a quiet line under it says `Asking needs Apple Intelligence on this
  device.` Find keeps working. **Without a connected calendar** the arrow is
  hidden too; the connect card already says what to do.
- **Cost.** The device model answers; the remote tier runs only when the
  project is configured for one, exactly as the sheet behaves today. Find
  never calls a model.

## 3. Calendar widget

A new widget beside `Your week`, which is untouched.

- Kind `LifeOSCalendar` (`AgendaSnapshot.calendarWidgetKind`); display name
  `Calendar`; description "Your month on paper: the days gone, today, and
  what is next." Families: `systemSmall`, `systemMedium`, `systemLarge`,
  `accessoryInline`, `accessoryCircular`, `accessoryRectangular`. The
  container background is paper (`LifeOSTokens.canvas`), resolving by
  colour scheme. The tap URL is `SurfaceRoute.calendar.url`.

### Layouts

- **Small.** Eyebrow `TUESDAY · OCT` top-leading; the day number in
  `Editorial.figure(56)` in the accent; under it the next event as one line,
  `09:00 Standup`, or `Nothing more today` in quiet ink.
- **Medium.** Today's band from the Weekly screen: the number in
  `Editorial.figure(64)` in the accent over the weekday eyebrow, 96pt wide
  on the left; on the right up to three of today's remaining events as
  `time · title` rows separated by hairlines. With nothing left today, the
  right side reads `Nothing more today` over the next event prefixed with
  its weekday, `Wed 10:00 Dentist`.
- **Large.** Eyebrow `MONTHLY · 2026`; the month name in
  `Editorial.headline(28)` in the accent; `WeekdayHeader(spacing: 0)` in
  quiet ink; the month grid as hairline cells 30pt tall, past days hatched
  (`HatchedCell` stroked in the accent at 0.55), today an accent cell with a
  paper number, a 2pt ink dot under days with events; under the grid, up to
  two of today's remaining events as rows when they fit (`ViewThatFits`).
- **Rectangular.** Eyebrow `TODAY · TUE 6`, then up to three rows
  `09:00  Standup`, titles `.privacySensitive()`; `Nothing scheduled` when
  empty.
- **Inline.** `Label("09:00 Standup", systemImage: "calendar")`, or
  `Nothing scheduled`.
- **Circular.** The weekday as a caption above the day number in
  `Editorial.figure(28)`, `.widgetAccentable()`, with up to three 3pt dots
  below for today's events.
- **Empty states.** No envelope, a foreign owner or an expired envelope:
  `Open LifeOS to sync` in each family's layout (the small and medium show
  the glyph, one line and a quiet sentence; large keeps the month grid
  without dots above the sentence). An envelope with no events: the grid
  without dots and the `Nothing` lines above.
- Accessory families are system-tinted; the style there is the type
  hierarchy, not colour.

### Data

- `AgendaSnapshot` keeps its stored fields. `windowDays` goes from 14 to
  42, and `window(around:)` now starts at the start of the week containing
  the first day of the month of the reference date, so a month grid has
  dots for every day it draws and the next-events list has at least two
  weeks of headroom on the last day of a month. `eventCap` goes from 80 to
  120. `weekStart` and `weekDays(calendar:)` are unchanged, so `Your week`
  draws the same week it does today.
- New `monthStart(calendar:)`, derived from `generatedAt`, and
  `isAvailable(at:grace:)` with `grace: TimeInterval = 0`. The agenda widget
  keeps the six-hour-or-midnight rule; the calendar widget passes a grace
  of 48 hours, because a month grid is still right tomorrow morning while a
  list of next events is not.
- `SurfaceCoordinator.publishAgenda()` reloads both kinds. The tombstone
  path is unchanged.
- `CalendarTimeline`: entries at now, at each event end within 24 hours,
  at the next two midnights (so the hatch and today advance without the
  app), and at `generatedAt + 48h` with a nil snapshot. Policy
  `.after(now + 30 min)`. At most 30 entries.

### Code placement

- New `LifeOSKit` library `WidgetViews` (target and product), depending on
  `AppSurfaces` and `DesignSystem`, importing `WidgetKit`. It holds
  `CalendarWidgetEntry` (`TimelineEntry`: `date`, `snapshot`),
  `CalendarWidgetView(entry:family:)`, and `CalendarWidgetText`, the tested
  wording: `dayEyebrow(_:)` ("TUESDAY · OCT"), `lockEyebrow(_:)`
  ("TODAY · TUE 6"), `monthEyebrow(_:)` ("MONTHLY · 2026"), `line(for:at:)`
  ("09:00 Standup", "All day Standup", "Wed 10:00 Dentist" for a later
  day), and the `nothing` lines. `AgendaSnapshot.sample(now:calendar:)`
  moves here from the widget target and becomes public; `AgendaWidget`
  reads it from here.
- `AlmanacWidgets/CalendarWidget.swift`: the `Widget`, the timeline
  provider, and the registration in `AlmanacWidgets.swift` after
  `AgendaWidget()`.
- Project file: the `WidgetViews` product is added to the `LIfeOS` and
  `AlmanacWidgets` targets (one `XCSwiftPackageProductDependency` and one
  Frameworks build file each), and `CalendarWidget.swift` to the
  extension's Sources, the way `AgendaWidget.swift` was.
- `SurfaceRoute` gains `calendar`. `RootView.openSurfaceRoute()` handles it
  with `tab = .today; showMonth = true`.
- Preview page `--page=widget-calendar` in `TodayDesignPreview`: the six
  families at their point sizes (small 158, medium 338 by 158, large 338 by
  354, rectangular 160 by 72 and circular 72 on black, inline as a line),
  fed by the sample, with `--dark` and `--empty`.

## 4. LIFO, the assistant sheet and the guide

Unchanged from the part-two spec §5 and §6, with three touches:

- The sheet's `Schedule` link opens `CalendarScreen` with the sheet's model
  (§1).
- `SurfaceRoute.calendar` lands with the widget PR; PR 5 adds `money`,
  `notes`, `life`, `coach` and `assistant` as the part-two spec says.
- The guide's row 08 reads: "Tap the calendar glyph in the header and ask,
  or ask from the calendar itself."

## 5. Verification

- Tests: `CalendarHeadlineTests` (DesignSystem), `ScheduleSearchTests`
  (Persistence), the `CreateEventTool` collector test (Assistant), the
  `AgendaSnapshotTests` updates (window from the month's first week, 42
  days, cap 120, grace), and `CalendarWidgetTextTests` (WidgetViewsTests).
- `scripts/check-typography.sh` reports nothing new versus the base branch.
- Builds: the app, `AlmanacWidgets`, `AlmanacWatchWidgets` and the Watch
  app.
- Preview pages, each with `--dark`: `month` and `schedule` now mount
  `CalendarScreen` in Monthly and Weekly; `calendar-find` (`--query=den`)
  shows the results block and the grid marks; `calendar-ask` shows the reply
  card from a seeded conversation (one user turn and one assistant turn with
  event ids, written into the in-memory `ChatStore` under the stored
  conversation id, so no model runs); `widget-calendar` as above.
- Simulator: open from the header button, switch modes, tap a day, type to
  find, tap a result, and tap the widget from the Home Screen.

## 6. Delivery

Five PRs, each planned from its spec and rebased on the one before:

1. `feat/editorial-calendar`: this spec; §1 (the screen, the switch, the
   week step, `CalendarHeadline`).
2. `feat/editorial-coach`: part two §5 (LIFO and the assistant on paper,
   the shared `ChatTurn` and `ChatComposer`, deletion of the aura and orb).
3. `feat/editorial-calendar-ask`: §2 (`HairlineField`, `ScheduleSearch`,
   find, the reply card, the create-event collector), on PR 2 so the card
   shares the chat pieces.
4. `feat/editorial-calendar-widget`: §3 and the `calendar` route.
5. `feat/editorial-guide`: part two §6.

Then build 50.

## Out of scope

- The Today tab, in any part.
- The look of `Your week` and the Health widget; the generated wallpaper;
  the watch.
- Settings, Profile, Connections, Social, the Workout library.
- Any change to what the assistant sends or stores, beyond returning the
  created event to its caller.
